import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/i_workshop_publish_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/vdf_generator.dart';

/// Implementation of Workshop publish service using steamcmd.
///
/// Login strategy (per Valve docs):
/// 1. Try cached credentials first: `+login <username>` (no password).
///    Providing the password invalidates the cached token, so we avoid it.
/// 2. If cached login fails, require a TOTP code and do a full login:
///    `+set_steam_guard_code <code> +login <username> <password>`.
/// 3. After a successful full login, steamcmd caches credentials in
///    config/config.vdf and ssfn* files — subsequent runs use step 1.
class WorkshopPublishServiceImpl implements IWorkshopPublishService {
  final SteamCmdManager _manager = SteamCmdManager();
  final VdfGenerator _vdfGenerator = VdfGenerator();
  final LoggingService _logger = LoggingService.instance;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  Process? _currentProcess;
  bool _isCancelled = false;

  @override
  Stream<double> get progressStream => _progressController.stream;

  @override
  Stream<String> get outputStream => _outputController.stream;

  @override
  Future<Result<WorkshopPublishResult, SteamServiceException>> publish({
    required WorkshopPublishParams params,
    required String username,
    required String password,
    String? steamGuardCode,
  }) async {
    final startTime = DateTime.now();
    _isCancelled = false;
    Directory? tempContentDir;

    try {
      // Ensure steamcmd is available
      final steamCmdPathResult = await _manager.getSteamCmdPath();
      if (steamCmdPathResult.isErr) {
        return Err(steamCmdPathResult.error);
      }
      final steamCmdPath = steamCmdPathResult.value;

      _progressController.add(0.0);

      // --- Content preparation ---
      // Always create a temp folder with ONLY the target .pack and its .png.
      // The contentFolder may contain many other .pack files from other mods;
      // steamcmd uploads everything in the folder, so we must isolate.
      final previewFile = File(params.previewFile);
      final previewName = previewFile.uri.pathSegments.last;
      // Derive pack name from preview: "modname.png" → "modname.pack"
      final packName =
          '${previewName.substring(0, previewName.lastIndexOf('.'))}.pack';
      final packFile =
          File(path.join(params.contentFolder, packName));

      if (!await packFile.exists()) {
        return Err(WorkshopPublishException(
          'Pack file not found: ${packFile.path}',
        ));
      }

      tempContentDir =
          await Directory.systemTemp.createTemp('twmt_publish_');
      // Copy the .pack file (not symlink — steamcmd may not follow symlinks)
      await packFile.copy(path.join(tempContentDir.path, packName));
      // Copy the preview .png if it's in the same folder
      if (await previewFile.exists()) {
        await previewFile
            .copy(path.join(tempContentDir.path, previewName));
      }

      final publishParams = params.copyWith(
        contentFolder: tempContentDir.path,
      );

      // --- Generate VDF ---
      _outputController.add('Generating VDF configuration...');
      final vdfResult = await _vdfGenerator.generateVdf(publishParams);
      if (vdfResult.isErr) {
        return Err(vdfResult.error);
      }
      final vdfPath = vdfResult.value;

      _logger.info('Publishing Workshop item', {
        'vdfPath': vdfPath,
        'publishedFileId': params.publishedFileId,
        'title': params.title,
      });

      // --- Step 1: Check for cached credentials (file-based, instant) ---
      _outputController.add('Checking cached credentials...');
      _progressController.add(0.02);
      final cachedLoginOk =
          await _hasCachedCredentials(steamCmdPath, username);

      if (_isCancelled) {
        return Err(const SteamServiceException(
          'Publish cancelled by user',
          code: 'PUBLISH_CANCELLED',
        ));
      }

      // --- Step 2: Build the publish command ---
      final List<String> command;
      if (cachedLoginOk) {
        // Cached credentials work — do NOT pass password (would invalidate cache)
        _outputController.add('Cached login OK — starting upload...');
        command = [
          '+login', username,
          '+workshop_build_item', vdfPath,
          '+quit',
        ];
      } else if (steamGuardCode != null) {
        // Full auth with TOTP code as third positional arg to +login
        _outputController.add(
            'Full authentication with Steam Guard code...');
        command = [
          '+login', username, password, steamGuardCode,
          '+workshop_build_item', vdfPath,
          '+quit',
        ];
      } else {
        // No cached creds and no code provided — need Steam Guard
        _outputController.add('Steam Guard code required.');
        // Clean up VDF
        try {
          await File(vdfPath).delete();
        } catch (_) {}
        return Err(const SteamGuardRequiredException(
          'Steam Guard code is required to authenticate',
        ));
      }

      // --- Step 3: Execute steamcmd publish ---
      _outputController.add('Starting steamcmd...');
      _progressController.add(0.05);

      var run = await _runSteamCmd(
        steamCmdPath: steamCmdPath,
        command: command,
        startTime: startTime,
        initialWasUpdate: true,
      );

      // Clean up VDF file
      try {
        await File(vdfPath).delete();
      } catch (_) {}

      if (run.exitCode == -1) {
        return Err(const SteamCmdTimeoutException(
          'Publish operation timed out after 5 minutes',
          timeoutSeconds: 300,
        ));
      }

      if (_isCancelled) {
        return Err(const SteamServiceException(
          'Publish cancelled by user',
          code: 'PUBLISH_CANCELLED',
        ));
      }

      // Check for authentication errors
      if (run.output.contains('Login Failure') ||
          run.output.contains('Invalid Password') ||
          run.output.contains('FAILED login')) {
        return Err(const SteamAuthenticationException(
          'Steam login failed. Check your credentials.',
        ));
      }

      // Check for Workshop item not found (item was deleted from Steam).
      if (run.output.contains('Failed to update workshop item')) {
        _logger.info(
          'Workshop item ${params.publishedFileId} not found on Steam',
        );
        return Err(WorkshopItemNotFoundException(
          'Workshop item #${params.publishedFileId} no longer exists on Steam.',
          workshopId: params.publishedFileId,
        ));
      }

      // Check for success
      // steamcmd can exit with 0, 6, or 7 and still be successful
      if (run.exitCode != 0 && run.exitCode != 6 && run.exitCode != 7) {
        return Err(WorkshopPublishException(
          'steamcmd exited with code ${run.exitCode}',
          workshopId: run.workshopId,
        ));
      }

      // Determine workshop ID
      final workshopId = run.workshopId ?? params.publishedFileId;

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      _progressController.add(1.0);
      _outputController.add('Upload complete! Workshop ID: $workshopId');

      _logger.info('Workshop publish complete', {
        'workshopId': workshopId,
        'wasUpdate': run.wasUpdate,
        'durationMs': duration,
      });

      return Ok(WorkshopPublishResult(
        workshopId: workshopId,
        wasUpdate: run.wasUpdate,
        durationMs: duration,
        timestamp: DateTime.now(),
        rawOutput: run.output,
      ));
    } catch (e, stackTrace) {
      return Err(WorkshopPublishException(
        'Publish failed: $e',
        stackTrace: stackTrace,
      ));
    } finally {
      _currentProcess = null;
      _isCancelled = false;
      if (tempContentDir != null) {
        try {
          await tempContentDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> publishBatch({
    required List<({String name, WorkshopPublishParams params})> items,
    required String username,
    required String password,
    String? steamGuardCode,
    void Function(int index, String name)? onItemStart,
    void Function(int index, double progress)? onItemProgress,
    void Function(
            int index,
            Result<WorkshopPublishResult, SteamServiceException> result)?
        onItemComplete,
  }) async {
    _isCancelled = false;
    final startTime = DateTime.now();

    // Ensure steamcmd is available
    final steamCmdPathResult = await _manager.getSteamCmdPath();
    if (steamCmdPathResult.isErr) {
      throw steamCmdPathResult.error;
    }
    final steamCmdPath = steamCmdPathResult.value;

    // Check cached credentials
    final cachedLoginOk =
        await _hasCachedCredentials(steamCmdPath, username);

    if (!cachedLoginOk && steamGuardCode == null) {
      throw const SteamGuardRequiredException(
        'Steam Guard code is required to authenticate',
      );
    }

    // --- Prepare all items: temp dirs, pack copies, VDF generation ---
    final prepared = <int, _BatchPreparedItem>{};
    final tempDirs = <Directory>[];

    try {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        try {
          final previewFile = File(item.params.previewFile);
          final previewName = previewFile.uri.pathSegments.last;
          final packName =
              '${previewName.substring(0, previewName.lastIndexOf('.'))}.pack';
          final packFile =
              File(path.join(item.params.contentFolder, packName));

          if (!await packFile.exists()) {
            onItemComplete?.call(
              i,
              Err(WorkshopPublishException(
                'Pack file not found: ${packFile.path}',
              )),
            );
            continue;
          }

          final tempDir =
              await Directory.systemTemp.createTemp('twmt_batch_${i}_');
          tempDirs.add(tempDir);

          await packFile.copy(path.join(tempDir.path, packName));
          if (await previewFile.exists()) {
            await previewFile
                .copy(path.join(tempDir.path, previewName));
          }

          final publishParams = item.params.copyWith(
            contentFolder: tempDir.path,
          );

          final vdfResult =
              await _vdfGenerator.generateVdf(publishParams);
          if (vdfResult.isErr) {
            onItemComplete?.call(i, Err(vdfResult.error));
            continue;
          }

          prepared[i] = _BatchPreparedItem(
            vdfPath: vdfResult.value,
            tempDir: tempDir,
            params: item.params,
          );
        } catch (e, stackTrace) {
          onItemComplete?.call(
            i,
            Err(WorkshopPublishException(
              'Preparation failed for ${item.name}: $e',
              stackTrace: stackTrace,
            )),
          );
        }
      }

      if (prepared.isEmpty || _isCancelled) return;

      // --- Build commands with chunking ---
      // Two limits: Windows CreateProcess limit (~32767 chars) and steamcmd
      // stability (crashes after ~30 items in a single process).
      final orderedIndices = prepared.keys.toList()..sort();
      final chunks = <List<int>>[];
      var currentChunk = <int>[];
      var currentLength = 0;
      const maxCmdLength = 32000;
      const loginReserve = 300;
      const maxItemsPerChunk = 15;

      for (final idx in orderedIndices) {
        final itemArg =
            '+workshop_build_item ${prepared[idx]!.vdfPath}'.length + 1;
        if (currentChunk.isNotEmpty &&
            (currentLength + itemArg > maxCmdLength - loginReserve ||
                currentChunk.length >= maxItemsPerChunk)) {
          chunks.add(currentChunk);
          currentChunk = <int>[];
          currentLength = 0;
        }
        currentChunk.add(idx);
        currentLength += itemArg;
      }
      if (currentChunk.isNotEmpty) chunks.add(currentChunk);

      // --- Execute each chunk as a single steamcmd process ---
      for (var chunkIdx = 0; chunkIdx < chunks.length; chunkIdx++) {
        if (_isCancelled) break;

        // Brief pause between chunks to let steamcmd fully release resources
        if (chunkIdx > 0) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }

        final chunk = chunks[chunkIdx];
        final List<String> command;

        // First chunk (or no cached creds): use provided auth
        // Subsequent chunks: credentials are cached from first login
        if (chunkIdx == 0 && !cachedLoginOk && steamGuardCode != null) {
          command = [
            '+login', username, password, steamGuardCode,
            ...chunk.expand((idx) => [
              '+workshop_build_item',
              prepared[idx]!.vdfPath,
            ]),
            '+quit',
          ];
        } else {
          command = [
            '+login', username,
            ...chunk.expand((idx) => [
              '+workshop_build_item',
              prepared[idx]!.vdfPath,
            ]),
            '+quit',
          ];
        }

        _logger.info('Starting steamcmd batch chunk ${chunkIdx + 1}/${chunks.length}', {
          'itemCount': chunk.length,
          'commandLength': command.join(' ').length,
        });

        await _runBatchProcess(
          steamCmdPath: steamCmdPath,
          command: command,
          chunk: chunk,
          items: items,
          prepared: prepared,
          startTime: startTime,
          onItemStart: onItemStart,
          onItemProgress: onItemProgress,
          onItemComplete: onItemComplete,
        );
      }
    } finally {
      // Cleanup all temp directories
      for (final dir in tempDirs) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
      // Cleanup VDF files that might be outside temp dirs
      for (final item in prepared.values) {
        try {
          await File(item.vdfPath).delete();
        } catch (_) {}
      }
      _currentProcess = null;
    }
  }

  /// Run a single steamcmd process for a batch chunk and parse multi-item output.
  Future<void> _runBatchProcess({
    required String steamCmdPath,
    required List<String> command,
    required List<int> chunk,
    required List<({String name, WorkshopPublishParams params})> items,
    required Map<int, _BatchPreparedItem> prepared,
    required DateTime startTime,
    void Function(int index, String name)? onItemStart,
    void Function(int index, double progress)? onItemProgress,
    void Function(
            int index,
            Result<WorkshopPublishResult, SteamServiceException> result)?
        onItemComplete,
  }) async {
    _currentProcess = await Process.start(
      steamCmdPath,
      command,
      runInShell: false,
    );
    _currentProcess!.stdin.close();

    var currentChunkPos = 0;
    final completedInChunk = <int>{};
    var lastOutputTime = DateTime.now();
    final rawOutput = StringBuffer();
    String? currentWorkshopId;
    bool authFailed = false;

    // Signal first item start
    if (chunk.isNotEmpty) {
      onItemStart?.call(chunk[0], items[chunk[0]].name);
    }

    final outputCompleter = Completer<void>();
    var stdoutDone = false;
    var stderrDone = false;
    void checkDone() {
      if (stdoutDone && stderrDone && !outputCompleter.isCompleted) {
        outputCompleter.complete();
      }
    }

    _currentProcess!.stdout.listen(
      (data) {
        lastOutputTime = DateTime.now();
        final output = String.fromCharCodes(data);
        rawOutput.write(output);

        for (final line in output.split(RegExp(r'[\r\n]+'))) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          _outputController.add(trimmed);

          // Check for auth failure (affects entire session)
          if (trimmed.contains('Login Failure') ||
              trimmed.contains('Invalid Password') ||
              trimmed.contains('FAILED login')) {
            authFailed = true;
            continue;
          }

          if (currentChunkPos >= chunk.length) continue;
          final currentIdx = chunk[currentChunkPos];

          // Progress tracking
          final progressMatch =
              RegExp(r'(\d+)%').firstMatch(trimmed);
          if (progressMatch != null) {
            final pct = int.parse(progressMatch.group(1)!);
            onItemProgress?.call(currentIdx, pct / 100.0);
          }

          // Workshop ID detection
          final idMatch =
              RegExp(r'PublishFileID\s*[:=]?\s*(\d+)')
                  .firstMatch(trimmed);
          if (idMatch != null) {
            currentWorkshopId = idMatch.group(1);
          }

          // Success: item completed
          if (trimmed.contains('Success.') ||
              trimmed.contains('Item Updated') ||
              (currentWorkshopId != null &&
                  trimmed.contains('PublishFileID'))) {
            // Determine final workshop ID
            final workshopId = currentWorkshopId ??
                items[currentIdx].params.publishedFileId;

            completedInChunk.add(currentIdx);
            final duration =
                DateTime.now().difference(startTime).inMilliseconds;
            onItemComplete?.call(
              currentIdx,
              Ok(WorkshopPublishResult(
                workshopId: workshopId,
                wasUpdate: true,
                durationMs: duration,
                timestamp: DateTime.now(),
                rawOutput: rawOutput.toString(),
              )),
            );
            currentWorkshopId = null;
            currentChunkPos++;
            if (currentChunkPos < chunk.length) {
              onItemStart?.call(
                chunk[currentChunkPos],
                items[chunk[currentChunkPos]].name,
              );
            }
          }

          // Failure: item not found on Steam
          if (trimmed.contains('Failed to update workshop item')) {
            completedInChunk.add(currentIdx);
            onItemComplete?.call(
              currentIdx,
              Err(WorkshopItemNotFoundException(
                'Workshop item #${items[currentIdx].params.publishedFileId} no longer exists on Steam.',
                workshopId: items[currentIdx].params.publishedFileId,
              )),
            );
            currentWorkshopId = null;
            currentChunkPos++;
            if (currentChunkPos < chunk.length) {
              onItemStart?.call(
                chunk[currentChunkPos],
                items[chunk[currentChunkPos]].name,
              );
            }
          }

          // Generic error for current item
          if (trimmed.contains('ERROR!') &&
              !trimmed.contains('Login') &&
              !completedInChunk.contains(currentIdx)) {
            completedInChunk.add(currentIdx);
            onItemComplete?.call(
              currentIdx,
              Err(WorkshopPublishException(
                'steamcmd error: $trimmed',
              )),
            );
            currentWorkshopId = null;
            currentChunkPos++;
            if (currentChunkPos < chunk.length) {
              onItemStart?.call(
                chunk[currentChunkPos],
                items[chunk[currentChunkPos]].name,
              );
            }
          }
        }
      },
      onDone: () {
        stdoutDone = true;
        checkDone();
      },
    );

    _currentProcess!.stderr.listen(
      (data) {
        lastOutputTime = DateTime.now();
        final output = String.fromCharCodes(data);
        rawOutput.write(output);
        for (final line in output.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            _outputController.add('[stderr] $trimmed');
          }
        }
      },
      onDone: () {
        stderrDone = true;
        checkDone();
      },
    );

    // Inactivity timeout: kill process if no output for 3 minutes
    final inactivityTimer =
        Timer.periodic(const Duration(seconds: 10), (_) {
      final silence = DateTime.now().difference(lastOutputTime);
      if (silence.inMinutes >= 3) {
        _logger.warning('Batch steamcmd inactivity timeout (3 min)');
        _currentProcess?.kill();
      }
    });

    final exitCode = await _currentProcess!.exitCode;
    inactivityTimer.cancel();
    await outputCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );

    // Handle auth failure — all items in chunk fail
    if (authFailed) {
      for (final idx in chunk) {
        if (!completedInChunk.contains(idx)) {
          onItemComplete?.call(
            idx,
            Err(const SteamAuthenticationException(
              'Steam login failed. Check your credentials.',
            )),
          );
        }
      }
      return;
    }

    // Mark any uncompleted items as errors
    for (final idx in chunk) {
      if (!completedInChunk.contains(idx)) {
        final reason = _isCancelled
            ? 'Publish cancelled by user'
            : 'steamcmd process terminated unexpectedly (exit code: $exitCode)';
        onItemComplete?.call(
          idx,
          Err(WorkshopPublishException(reason)),
        );
      }
    }
  }

  /// Run steamcmd with the given command and return structured output.
  Future<({int exitCode, String output, String? workshopId, bool wasUpdate})>
      _runSteamCmd({
    required String steamCmdPath,
    required List<String> command,
    required DateTime startTime,
    required bool initialWasUpdate,
  }) async {
    _currentProcess = await Process.start(
      steamCmdPath,
      command,
      runInShell: false,
    );

    // Close stdin so steamcmd cannot hang waiting for interactive input
    _currentProcess!.stdin.close();

    final stdout = StringBuffer();
    String? detectedWorkshopId;
    bool wasUpdate = initialWasUpdate;
    var lastRealOutputTime = DateTime.now();

    _currentProcess!.stdout.listen((data) {
      lastRealOutputTime = DateTime.now();
      final output = String.fromCharCodes(data);
      stdout.write(output);

      for (final line in output.split(RegExp(r'[\r\n]+'))) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _outputController.add(trimmed);
        }
      }

      _tryExtractProgress(output);

      final publishIdMatch =
          RegExp(r'PublishFileID\s*[:=]?\s*(\d+)').firstMatch(output);
      if (publishIdMatch != null) {
        detectedWorkshopId = publishIdMatch.group(1);
      }

      if (output.contains('Item Updated')) {
        wasUpdate = true;
      }
    });

    _currentProcess!.stderr.listen((data) {
      lastRealOutputTime = DateTime.now();
      final output = String.fromCharCodes(data);
      stdout.write(output);
      for (final line in output.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _outputController.add('[stderr] $trimmed');
        }
      }
    });

    final heartbeatTimer =
        Timer.periodic(const Duration(seconds: 5), (_) {
      final silenceDuration =
          DateTime.now().difference(lastRealOutputTime);
      if (silenceDuration.inSeconds >= 5 && _currentProcess != null) {
        final elapsed = DateTime.now().difference(startTime);
        final minutes = elapsed.inMinutes;
        final seconds = elapsed.inSeconds % 60;
        final timeStr = minutes > 0
            ? '${minutes}m ${seconds.toString().padLeft(2, '0')}s'
            : '${seconds}s';
        _outputController.add('[$timeStr] steamcmd running...');
      }
    });

    final exitCode = await _currentProcess!.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _currentProcess?.kill();
        return -1;
      },
    );

    heartbeatTimer.cancel();

    return (
      exitCode: exitCode,
      output: stdout.toString(),
      workshopId: detectedWorkshopId,
      wasUpdate: wasUpdate,
    );
  }

  /// Check whether steamcmd has cached credentials for [username].
  ///
  /// Looks for config/config.vdf (with ConnectCache) and ssfn* sentry files
  /// in the steamcmd installation directory. This is instant and avoids the
  /// false-positive from running `steamcmd +login user +quit` (which exits 0
  /// regardless of login success due to +quit).
  Future<bool> _hasCachedCredentials(
    String steamCmdPath,
    String username,
  ) async {
    try {
      final steamCmdDir = path.dirname(steamCmdPath);

      // Check for config.vdf with ConnectCache
      final configFile =
          File(path.join(steamCmdDir, 'config', 'config.vdf'));
      if (!await configFile.exists()) {
        _logger.info('No config.vdf found — no cached credentials');
        return false;
      }

      final configContent = await configFile.readAsString();
      if (!configContent.contains('ConnectCache')) {
        _logger.info('config.vdf has no ConnectCache — no cached credentials');
        return false;
      }

      // Check that this specific username has a cached entry
      final lowerUsername = username.toLowerCase();
      final lowerConfig = configContent.toLowerCase();
      if (!lowerConfig.contains(lowerUsername)) {
        _logger.info(
            'config.vdf has no entry for $username — no cached credentials');
        return false;
      }

      _logger.info('Cached credentials found for $username');
      return true;
    } catch (e) {
      _logger.warning('Cached credentials check failed: $e');
      return false;
    }
  }

  @override
  void submitSteamGuardCode(String code) {
    // stdin is closed after process start, so we cannot write to it.
    // Steam Guard codes must be provided upfront via +login args.
    _logger.warning('submitSteamGuardCode called but stdin is closed');
  }

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    _currentProcess?.kill();
    _currentProcess = null;
  }

  @override
  Future<bool> isAvailable() async {
    return await _manager.isAvailable();
  }

  /// Try to extract progress percentage from steamcmd output
  void _tryExtractProgress(String output) {
    final progressRegex = RegExp(r'(\d+)%');
    final match = progressRegex.firstMatch(output);

    if (match != null) {
      final percentage = int.parse(match.group(1)!);
      // Scale progress: 5% (init) to 95% (upload complete)
      _progressController.add(0.05 + (percentage / 100.0) * 0.90);
    }
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
    _outputController.close();
    _currentProcess?.kill();
  }
}

/// Prepared item for batch publishing (internal to service)
class _BatchPreparedItem {
  final String vdfPath;
  final Directory tempDir;
  final WorkshopPublishParams params;

  const _BatchPreparedItem({
    required this.vdfPath,
    required this.tempDir,
    required this.params,
  });
}
