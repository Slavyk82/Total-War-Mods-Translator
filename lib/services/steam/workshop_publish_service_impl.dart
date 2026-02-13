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
        'isNew': params.isNewItem,
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

      _currentProcess = await Process.start(
        steamCmdPath,
        command,
        runInShell: false,
      );

      // Close stdin so steamcmd cannot hang waiting for interactive input
      // (e.g. if the Steam Guard code is wrong/expired). It will fail and
      // exit instead of blocking forever.
      _currentProcess!.stdin.close();

      final stdout = StringBuffer();
      String? detectedWorkshopId;
      bool wasUpdate = !params.isNewItem;
      var lastRealOutputTime = DateTime.now();

      _currentProcess!.stdout.listen((data) {
        lastRealOutputTime = DateTime.now();
        final output = String.fromCharCodes(data);
        stdout.write(output);

        // Split on \n and \r to handle steamcmd's carriage-return progress
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

      // Heartbeat timer (steamcmd on Windows buffers stdout when piped)
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

      // Wait for completion with 5 min timeout
      final exitCode = await _currentProcess!.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          _currentProcess?.kill();
          return -1;
        },
      );

      heartbeatTimer.cancel();

      // Clean up VDF file
      try {
        await File(vdfPath).delete();
      } catch (_) {}

      if (exitCode == -1) {
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
      final outputStr = stdout.toString();
      if (outputStr.contains('Login Failure') ||
          outputStr.contains('Invalid Password') ||
          outputStr.contains('FAILED login')) {
        return Err(const SteamAuthenticationException(
          'Steam login failed. Check your credentials.',
        ));
      }

      // Check for success
      // steamcmd can exit with 0, 6, or 7 and still be successful
      if (exitCode != 0 && exitCode != 6 && exitCode != 7) {
        return Err(WorkshopPublishException(
          'steamcmd exited with code $exitCode',
          workshopId: detectedWorkshopId,
        ));
      }

      // Determine workshop ID
      final workshopId = detectedWorkshopId ??
          (params.isNewItem ? null : params.publishedFileId);

      if (workshopId == null || workshopId == '0') {
        return Err(const WorkshopPublishException(
          'Could not determine Workshop ID from steamcmd output',
        ));
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      _progressController.add(1.0);
      _outputController.add('Upload complete! Workshop ID: $workshopId');

      _logger.info('Workshop publish complete', {
        'workshopId': workshopId,
        'wasUpdate': wasUpdate,
        'durationMs': duration,
      });

      return Ok(WorkshopPublishResult(
        workshopId: workshopId,
        wasUpdate: wasUpdate,
        durationMs: duration,
        timestamp: DateTime.now(),
        rawOutput: stdout.toString(),
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

      // Check for ssfn sentry files
      final steamCmdDirEntries =
          await Directory(steamCmdDir).list().toList();
      final hasSsfn = steamCmdDirEntries.any(
        (e) => e is File && path.basename(e.path).startsWith('ssfn'),
      );

      _logger.info('Cached credentials check', {
        'hasConnectCache': true,
        'hasSsfn': hasSsfn,
        'username': username,
      });

      // Require both ConnectCache entry and ssfn sentry files
      return hasSsfn;
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
