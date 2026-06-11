import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/services/activity_logger.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/shared/i_process_launcher.dart';
import 'package:twmt/services/shared/process_output_drainer.dart';
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
/// True when steamcmd output indicates a login/authentication failure.
bool isSteamLoginFailureOutput(String output) {
  return output.contains('Login Failure') ||
      output.contains('Invalid Password') ||
      output.contains('FAILED login');
}

/// How a steamcmd login failure should be treated.
enum SteamLoginFailureKind {
  /// The cached session expired or was revoked. The cached login sent no
  /// password and no Steam Guard code, so this is not bad credentials — the
  /// cache must be invalidated and the user re-authenticated from scratch.
  staleCacheNeedsReauth,

  /// A full login with supplied credentials failed: the credentials are wrong.
  badCredentials,
}

/// Classifies a steamcmd login failure based on whether the failing attempt
/// used the cached-credentials path.
SteamLoginFailureKind classifySteamLoginFailure({required bool usedCachedLogin}) {
  return usedCachedLogin
      ? SteamLoginFailureKind.staleCacheNeedsReauth
      : SteamLoginFailureKind.badCredentials;
}

class WorkshopPublishServiceImpl implements IWorkshopPublishService {
  final SteamCmdManager _manager;
  final VdfGenerator _vdfGenerator;
  final IProcessLauncher _processLauncher;
  final ILoggingService _logger;
  final ActivityLogger? _activityLogger;

  /// How long steamcmd may stay completely silent before the watchdog kills
  /// it. Output activity (progress lines, heartbeats from steamcmd itself)
  /// resets this window.
  final Duration _inactivityTimeout;

  /// Absolute ceiling on a single steamcmd run: even a process that keeps
  /// producing output is killed past this point (guards against an endless
  /// heartbeat loop that never finishes an item).
  final Duration _absoluteTimeout;

  WorkshopPublishServiceImpl({
    SteamCmdManager? manager,
    VdfGenerator? vdfGenerator,
    IProcessLauncher? processLauncher,
    ILoggingService? logger,
    ActivityLogger? activityLogger,
    Duration inactivityTimeout = const Duration(minutes: 3),
    Duration absoluteTimeout = const Duration(minutes: 90),
  })  : _manager = manager ?? SteamCmdManager(),
        _vdfGenerator = vdfGenerator ?? VdfGenerator(),
        _processLauncher = processLauncher ?? const ProcessLauncher(),
        _logger = logger ?? ServiceLocator.get<ILoggingService>(),
        _activityLogger = activityLogger ?? _tryResolveActivityLogger(),
        _inactivityTimeout = inactivityTimeout,
        _absoluteTimeout = absoluteTimeout;

  static ActivityLogger? _tryResolveActivityLogger() {
    try {
      if (ServiceLocator.isRegistered<ActivityLogger>()) {
        return ServiceLocator.get<ActivityLogger>();
      }
    } catch (_) {}
    return null;
  }

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  Process? _currentProcess;
  bool _isCancelled = false;

  // This service is a lazy singleton with mutable per-run state
  // (_currentProcess / _isCancelled). Guard against concurrent runs so a
  // second publish cannot stomp the first's process handle or cancellation
  // flag. Set before entering the try block; cleared in finally.
  bool _isRunning = false;

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
    if (_isRunning) {
      return Err(WorkshopPublishException(
        'A publish operation is already in progress.',
      ));
    }
    _isRunning = true;
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

      // Cancellation must be checked BEFORE the watchdog-timeout check:
      // cancel() kills the process, and the watchdog may still observe the
      // resulting silence and record a timeout reason before the exit lands.
      // Checking the timeout first would report a deliberate user cancel as
      // a timeout.
      if (_isCancelled) {
        return Err(const SteamServiceException(
          'Publish cancelled by user',
          code: 'PUBLISH_CANCELLED',
        ));
      }

      // Watchdog kill (silent past the inactivity window, or absolute
      // ceiling reached) — report as a timeout, not as a bad exit code.
      final timeoutException = run.timeoutException;
      if (timeoutException != null) {
        return Err(timeoutException);
      }

      // Check for authentication errors
      if (isSteamLoginFailureOutput(run.output)) {
        final kind = classifySteamLoginFailure(usedCachedLogin: cachedLoginOk);
        if (kind == SteamLoginFailureKind.staleCacheNeedsReauth) {
          // The cached steamcmd session was stale (expired token / revoked
          // sentry / password changed elsewhere). We logged in WITHOUT a
          // password or Steam Guard code, so this is a recoverable expired
          // cache — not bad credentials. Invalidate the cache and ask for a
          // fresh Steam Guard authentication so the flow falls back to a full
          // login instead of dead-ending on a non-retryable auth error that
          // never prompts for a code.
          await _invalidateCachedCredentials(steamCmdPath);
          return Err(const SteamGuardRequiredException(
            'Your saved Steam session has expired. Please re-enter your '
            'password and Steam Guard code.',
          ));
        }
        return Err(const SteamAuthenticationException(
          'Steam login failed. Check your credentials.',
        ));
      }

      // steamcmd prints 'ERROR! Failed to update workshop item (<reason>).'
      // for ALL workshop_build_item failures. Only the '(File Not Found)'
      // reason means the item was deleted from Steam; other reasons
      // (Failure, Timeout, Access Denied, Limit Exceeded, ...) are ordinary
      // upload failures and must NOT be reported as a deleted item — that
      // message would push the user to republish as a duplicate new item.
      if (run.output.contains('Failed to update workshop item')) {
        final reason = _extractUpdateFailureReason(run.output);
        if (_isItemDeletedReason(reason)) {
          _logger.info(
            'Workshop item ${params.publishedFileId} not found on Steam',
          );
          return Err(WorkshopItemNotFoundException(
            'Workshop item #${params.publishedFileId} no longer exists on Steam.',
            workshopId: params.publishedFileId,
          ));
        }
        _logger.warning('Workshop item update failed', {
          'reason': reason ?? 'unknown',
          'publishedFileId': params.publishedFileId,
        });
        return Err(WorkshopPublishException(
          'Failed to update workshop item'
          '${reason != null ? ' ($reason)' : ''}.',
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

      _activityLogger?.log(
        ActivityEventType.projectPublished,
        projectId: null, // params.projectId doesn't exist; no cheap lookup
        gameCode: null,
        payload: {
          'projectName': params.title,
          'workshopId': workshopId,
        },
      );

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
      _isRunning = false;
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
    if (_isRunning) {
      throw WorkshopPublishException(
        'A publish operation is already in progress.',
      );
    }
    _isRunning = true;
    _isCancelled = false;
    final startTime = DateTime.now();

    // Declared before the try so the finally can always clean them up.
    final prepared = <int, _BatchPreparedItem>{};
    final tempDirs = <Directory>[];

    try {
      // Ensure steamcmd is available. NOTE: these pre-flight checks MUST stay
      // inside the try so the finally resets _isRunning. The Steam Guard path
      // is a normal flow (no cached creds -> throw SteamGuardRequiredException
      // -> caller retries with a code); if it threw outside the try,
      // _isRunning would stay true forever and the retry would be rejected by
      // the re-entrance guard, permanently locking the service.
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
      _isRunning = false;
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
    // Keep a local handle: a concurrent cancel() kills the process and nulls
    // the _currentProcess FIELD, so every later use here (exitCode await,
    // watchdog kill) must go through this local — using the field would
    // either throw on the null or, worse, kill a LATER publish's process.
    final process = await _processLauncher.start(
      steamCmdPath,
      command,
      runInShell: false,
    );
    _currentProcess = process;
    process.stdin.close();

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

    // Process one COMPLETE output line. The drainer reassembles lines split
    // across stdout chunks and flushes the trailing partial line on done, so
    // a split "Success."/"PublishFileID" line is still recognized and
    // currentChunkPos stays aligned with the item being published.
    void processStdoutLine(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;

      _outputController.add(trimmed);

      // Check for auth failure (affects entire session)
      if (trimmed.contains('Login Failure') ||
          trimmed.contains('Invalid Password') ||
          trimmed.contains('FAILED login')) {
        authFailed = true;
        return;
      }

      if (currentChunkPos >= chunk.length) return;
      final currentIdx = chunk[currentChunkPos];

      // Progress tracking
      final progressMatch = RegExp(r'(\d+)%').firstMatch(trimmed);
      if (progressMatch != null) {
        final pct = int.parse(progressMatch.group(1)!);
        onItemProgress?.call(currentIdx, pct / 100.0);
      }

      // Workshop ID detection
      final idMatch =
          RegExp(r'PublishFileID\s*[:=]?\s*(\d+)').firstMatch(trimmed);
      if (idMatch != null) {
        currentWorkshopId = idMatch.group(1);
      }

      // Success: item completed
      if (trimmed.contains('Success.') ||
          trimmed.contains('Item Updated') ||
          (currentWorkshopId != null && trimmed.contains('PublishFileID'))) {
        // Determine final workshop ID
        final workshopId =
            currentWorkshopId ?? items[currentIdx].params.publishedFileId;

        completedInChunk.add(currentIdx);
        final duration = DateTime.now().difference(startTime).inMilliseconds;
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
        _activityLogger?.log(
          ActivityEventType.projectPublished,
          projectId: null,
          gameCode: null,
          payload: {
            'projectName': items[currentIdx].params.title,
            'workshopId': workshopId,
          },
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

      // Failure: workshop item update rejected by steamcmd. Only the
      // '(File Not Found)' reason means the item was deleted from Steam;
      // any other reason (Failure, Timeout, Access Denied, ...) is a
      // generic upload failure for the current item.
      if (trimmed.contains('Failed to update workshop item')) {
        final reason = _extractUpdateFailureReason(trimmed);
        final SteamServiceException error;
        if (_isItemDeletedReason(reason)) {
          error = WorkshopItemNotFoundException(
            'Workshop item #${items[currentIdx].params.publishedFileId} no longer exists on Steam.',
            workshopId: items[currentIdx].params.publishedFileId,
          );
        } else {
          error = WorkshopPublishException(
            'Failed to update workshop item'
            '${reason != null ? ' ($reason)' : ''}.',
            workshopId: items[currentIdx].params.publishedFileId,
          );
        }
        completedInChunk.add(currentIdx);
        onItemComplete?.call(currentIdx, Err(error));
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

    void processStderrLine(String line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        _outputController.add('[stderr] $trimmed');
      }
    }

    final drainer = ProcessOutputDrainer(
      stdout: process.stdout,
      stderr: process.stderr,
      onStdoutChunk: (output) {
        lastOutputTime = DateTime.now();
        rawOutput.write(output);
      },
      onStdoutLine: processStdoutLine,
      onStderrChunk: (output) {
        lastOutputTime = DateTime.now();
        rawOutput.write(output);
      },
      onStderrLine: processStderrLine,
    );

    // Activity-aware timeout. A fixed wall-clock budget here used to kill
    // healthy uploads (large pack + slow uplink) that were still emitting
    // steady progress output past the budget, reporting them as 'terminated
    // unexpectedly'. The watchdog only kills the process when it has been
    // silent for the inactivity window, or when the absolute ceiling (the
    // old 90-min clamp ceiling) is reached even while still active — so
    // output activity extends the deadline. The uncompleted-items loop below
    // reports the affected items, as a timeout when the watchdog fired.
    final watchdog = _SteamCmdWatchdog(
      inactivityTimeout: _inactivityTimeout,
      absoluteTimeout: _absoluteTimeout,
      lastOutputAt: () => lastOutputTime,
      onTimeout: (reason) {
        _logger.warning(
          'Batch steamcmd timed out $reason '
          '(chunk of ${chunk.length} item(s)) — killing process',
        );
        process.kill();
      },
    );

    // Last-resort bound so an unkillable process cannot block this await
    // forever; the watchdog normally kills well before this fires.
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        _absoluteTimeout + const Duration(minutes: 1),
        onTimeout: () {
          _logger.warning(
            'Batch steamcmd did not exit within the absolute ceiling — '
            'abandoning the wait',
          );
          process.kill();
          return -1;
        },
      );
      // Cancel before the drain grace below so the watchdog cannot record a
      // spurious inactivity timeout while we wait for trailing output.
      watchdog.cancel();
      await drainer.awaitDrained();
    } finally {
      // Re-run the cleanup unconditionally (both calls are idempotent): if
      // anything above throws, a leaked periodic watchdog timer or live
      // stream subscriptions could otherwise fire callbacks into a finished
      // run — or kill a later publish's process.
      watchdog.cancel();
      await drainer.cancel();
    }
    final timeoutException = watchdog.toTimeoutException();

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

    // On cancellation, do NOT report uncompleted items at all: an Err here
    // becomes a `failed` status, but a deliberately-cancelled, never-attempted
    // item must show as cancelled. Leaving it untouched lets
    // BatchWorkshopPublishNotifier reclassify the still-pending/inProgress item
    // to cancelled after the batch returns.
    if (_isCancelled) {
      return;
    }

    // Mark any uncompleted items as errors. A watchdog kill must be reported
    // as a timeout, not as an unexplained termination with the -1 sentinel.
    for (final idx in chunk) {
      if (!completedInChunk.contains(idx)) {
        onItemComplete?.call(
          idx,
          timeoutException != null
              ? Err(timeoutException)
              : Err(WorkshopPublishException(
                  'steamcmd process terminated unexpectedly '
                  '(exit code: $exitCode)',
                )),
        );
      }
    }
  }

  /// Run steamcmd with the given command and return structured output.
  ///
  /// [timeoutException] is set when the activity-aware watchdog killed the
  /// process (silent past the inactivity window, or absolute ceiling
  /// reached); null when the process exited on its own.
  Future<
      ({
        int exitCode,
        String output,
        String? workshopId,
        bool wasUpdate,
        SteamCmdTimeoutException? timeoutException,
      })> _runSteamCmd({
    required String steamCmdPath,
    required List<String> command,
    required DateTime startTime,
    required bool initialWasUpdate,
  }) async {
    // Keep a local handle: a concurrent cancel() kills the process and nulls
    // the _currentProcess FIELD, so every later use here (exitCode await,
    // watchdog kill) must go through this local — using the field would
    // either throw on the null or, worse, kill a LATER publish's process.
    final process = await _processLauncher.start(
      steamCmdPath,
      command,
      runInShell: false,
    );
    _currentProcess = process;

    // Close stdin so steamcmd cannot hang waiting for interactive input
    process.stdin.close();

    final stdout = StringBuffer();
    String? detectedWorkshopId;
    bool wasUpdate = initialWasUpdate;
    var lastRealOutputTime = DateTime.now();

    // Ensure stdout/stderr are fully drained before we read the buffer.
    // The process can exit while output is still queued, so awaiting exitCode
    // alone can truncate `stdout` and miss login/update failures.
    final drainer = ProcessOutputDrainer(
      stdout: process.stdout,
      stderr: process.stderr,
      onStdoutChunk: (output) {
        lastRealOutputTime = DateTime.now();
        stdout.write(output);

        _tryExtractProgress(output);

        final publishIdMatch =
            RegExp(r'PublishFileID\s*[:=]?\s*(\d+)').firstMatch(output);
        if (publishIdMatch != null) {
          detectedWorkshopId = publishIdMatch.group(1);
        }

        if (output.contains('Item Updated')) {
          wasUpdate = true;
        }
      },
      onStdoutLine: (line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _outputController.add(trimmed);
        }
      },
      onStderrChunk: (output) {
        lastRealOutputTime = DateTime.now();
        stdout.write(output);
      },
      onStderrLine: (line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _outputController.add('[stderr] $trimmed');
        }
      },
    );

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

    // Activity-aware timeout, same mechanism as the batch path: a fixed
    // wall-clock cap here used to kill slow-but-progressing uploads. The
    // watchdog only kills on real silence or at the absolute ceiling.
    final watchdog = _SteamCmdWatchdog(
      inactivityTimeout: _inactivityTimeout,
      absoluteTimeout: _absoluteTimeout,
      lastOutputAt: () => lastRealOutputTime,
      onTimeout: (reason) {
        _logger.warning('steamcmd publish timed out $reason — killing process');
        process.kill();
      },
    );

    // Last-resort bound so an unkillable process cannot block this await
    // forever; the watchdog normally kills well before this fires.
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        _absoluteTimeout + const Duration(minutes: 1),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );

      heartbeatTimer.cancel();
      watchdog.cancel();

      // Wait for any output still queued after the process exited so the
      // buffer (checked for login/update failures and the workshop id) is
      // complete.
      await drainer.awaitDrained();
    } finally {
      // Re-run the cleanup unconditionally (all three calls are idempotent):
      // if anything above throws, leaked periodic timers or live stream
      // subscriptions could otherwise fire callbacks into a finished run —
      // or kill a later publish's process.
      heartbeatTimer.cancel();
      watchdog.cancel();
      await drainer.cancel();
    }

    return (
      exitCode: exitCode,
      output: stdout.toString(),
      workshopId: detectedWorkshopId,
      wasUpdate: wasUpdate,
      timeoutException: watchdog.toTimeoutException(),
    );
  }

  /// Check whether steamcmd has cached credentials for [username].
  ///
  /// Looks for config/config.vdf (with ConnectCache) and ssfn* sentry files
  /// in the steamcmd installation directory. This is instant and avoids the
  /// false-positive from running `steamcmd +login user +quit` (which exits 0
  /// regardless of login success due to +quit).
  /// Deletes steamcmd's cached-session files (config/config.vdf and ssfn*
  /// sentry files) so the next publish re-authenticates from scratch.
  ///
  /// Called when a cached login fails, which otherwise dead-ends on a
  /// non-retryable auth error that never prompts for a Steam Guard code.
  /// Best-effort: failures are logged, never thrown.
  Future<void> _invalidateCachedCredentials(String steamCmdPath) async {
    try {
      final steamCmdDir = path.dirname(steamCmdPath);

      final configFile = File(path.join(steamCmdDir, 'config', 'config.vdf'));
      if (await configFile.exists()) {
        await configFile.delete();
        _logger.info('Deleted stale config.vdf to force re-authentication');
      }

      // Remove ssfn* sentry files alongside steamcmd.
      final dir = Directory(steamCmdDir);
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File &&
              path.basename(entity.path).toLowerCase().startsWith('ssfn')) {
            try {
              await entity.delete();
            } catch (_) {
              // Best-effort per file.
            }
          }
        }
      }
    } catch (e) {
      _logger.warning('Failed to invalidate cached credentials: $e');
    }
  }

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

      // Check that this specific username has a cached entry.
      //
      // Previously this did a naive `lowerConfig.contains(lowerUsername)`
      // substring test, which false-positives when the username happens to be
      // a substring of another account name, a path, or a token field. Match
      // the username as a properly quoted VDF key instead — steamcmd writes
      // accounts as a quoted key (e.g. `"username"` under the Accounts /
      // ConnectCache sections). We require the quoted token to appear, and
      // that it is delimited by a non-word boundary so e.g. "sam" does not
      // match "samuel". This stays best-effort (an optimization, not a
      // security boundary): on failure we fall back to a full login.
      final lowerConfig = configContent.toLowerCase();
      // RegExp.escape the username so usernames with regex-special characters
      // are matched literally.
      final quotedUser = RegExp.escape('"${username.toLowerCase()}"');
      // The quoted name must be followed by whitespace/brace (a VDF key is
      // followed by either a nested object `{` or an inline value), not more
      // word characters — guarding against partial matches inside a longer
      // quoted string.
      final userKeyPattern = RegExp('$quotedUser(?![\\w"])');
      if (!userKeyPattern.hasMatch(lowerConfig)) {
        _logger.info(
            'config.vdf has no quoted entry for $username — no cached credentials');
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

  /// Matches the parenthesized EResult reason in steamcmd's
  /// `ERROR! Failed to update workshop item (<reason>).` error line.
  static final RegExp _updateFailureReasonPattern =
      RegExp(r'Failed to update workshop item\s*\(([^)]+)\)');

  /// Extracts the parenthesized reason from a steamcmd
  /// `Failed to update workshop item (<reason>)` line, or null when the
  /// output carries no parenthesized reason.
  static String? _extractUpdateFailureReason(String output) =>
      _updateFailureReasonPattern.firstMatch(output)?.group(1)?.trim();

  /// Whether the steamcmd update-failure [reason] means the Workshop item
  /// was deleted from Steam. steamcmd reports this as '(File Not Found)';
  /// every other reason is an ordinary upload failure.
  static bool _isItemDeletedReason(String? reason) =>
      reason != null && reason.toLowerCase() == 'file not found';

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

  /// Dispose resources held by this service.
  ///
  /// Closes the broadcast [_progressController]/[_outputController] and kills
  /// any in-flight process. This service is a lazy app-lifetime singleton, so
  /// in normal operation this is effectively never called and the controllers
  /// live for the process lifetime (the per-operation subscribers cancel their
  /// own subscriptions, so there is no growing leak). This method exists for
  /// teardown/tests and for locator resets / hot restart, where the old
  /// controllers would otherwise leak.
  ///
  /// To wire this up, register the service with a dispose callback, e.g.:
  /// ```
  /// registerLazySingleton<IWorkshopPublishService>(
  ///   ...,
  ///   dispose: (s) => (s as WorkshopPublishServiceImpl).dispose(),
  /// );
  /// ```
  /// (Not declared on [IWorkshopPublishService]; the interface does not expose
  /// a dispose contract, so callers must downcast or the interface should add
  /// one if disposal becomes part of the contract.)
  void dispose() {
    // Guard against double-close (e.g. dispose called twice in tests).
    if (!_progressController.isClosed) _progressController.close();
    if (!_outputController.isClosed) _outputController.close();
    _currentProcess?.kill();
  }
}

/// Activity-aware watchdog for a running steamcmd process.
///
/// Replaces the old fixed wall-clock `.timeout()` on `exitCode`, which
/// killed healthy uploads: a large pack on a slow uplink can legitimately
/// take longer than any per-item budget while still emitting steady progress
/// output. The watchdog only declares a timeout when either:
///  - the process has been completely silent for [inactivityTimeout]
///    (regardless of elapsed time), or
///  - the [absoluteTimeout] ceiling is reached even though the process is
///    still producing output (guards against an endless heartbeat loop).
/// Output activity therefore extends the effective deadline up to the
/// absolute ceiling.
///
/// [onTimeout] is invoked at most once, with a human-readable reason; the
/// call site is expected to kill the process there. After the process exits,
/// read [timeoutReason] to distinguish a watchdog kill from a natural exit.
class _SteamCmdWatchdog {
  _SteamCmdWatchdog({
    required Duration inactivityTimeout,
    required Duration absoluteTimeout,
    required DateTime Function() lastOutputAt,
    required void Function(String reason) onTimeout,
  }) : _startedAt = DateTime.now() {
    _timer = Timer.periodic(
      _checkInterval(inactivityTimeout, absoluteTimeout),
      (_) {
        if (timeoutReason != null) return; // already fired
        final now = DateTime.now();
        final silence = now.difference(lastOutputAt());
        final elapsed = now.difference(_startedAt);
        if (silence >= inactivityTimeout) {
          timedOutAfter = inactivityTimeout;
          timeoutReason =
              'after ${_format(inactivityTimeout)} without output';
        } else if (elapsed >= absoluteTimeout) {
          timedOutAfter = absoluteTimeout;
          timeoutReason = 'after ${_format(absoluteTimeout)} (absolute time '
              'ceiling reached while still producing output)';
        }
        if (timeoutReason != null) {
          onTimeout(timeoutReason!);
        }
      },
    );
  }

  final DateTime _startedAt;
  late final Timer _timer;

  /// Human-readable reason set when the watchdog declared a timeout; null
  /// when the process exited on its own.
  String? timeoutReason;

  /// The limit that was exceeded, for exception metadata.
  Duration? timedOutAfter;

  /// The recorded timeout as a [SteamCmdTimeoutException], or null when the
  /// watchdog never fired. Centralizes the exception construction so call
  /// sites don't rebuild it from the raw fields — [timedOutAfter] is always
  /// set together with [timeoutReason], so no fallback is needed.
  SteamCmdTimeoutException? toTimeoutException() {
    final reason = timeoutReason;
    if (reason == null) return null;
    return SteamCmdTimeoutException(
      'steamcmd timed out $reason',
      timeoutSeconds: timedOutAfter!.inSeconds,
    );
  }

  void cancel() => _timer.cancel();

  /// Polls every 10 s in production; scales down for short (test-injected)
  /// windows so they are still detected promptly.
  static Duration _checkInterval(Duration inactivity, Duration ceiling) {
    var interval = const Duration(seconds: 10);
    final shortest = inactivity < ceiling ? inactivity : ceiling;
    final half = shortest ~/ 2;
    if (half < interval) interval = half;
    const floor = Duration(milliseconds: 20);
    return interval < floor ? floor : interval;
  }

  static String _format(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';
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
