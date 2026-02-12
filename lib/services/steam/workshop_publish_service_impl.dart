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

/// Implementation of Workshop publish service using steamcmd
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

      _outputController.add('Preparing content for upload...');
      _progressController.add(0.0);

      // Create isolated temp content folder with only the .pack file
      tempContentDir = await Directory.systemTemp.createTemp('twmt_publish_');
      final contentDir = Directory(params.contentFolder);
      await for (final entity in contentDir.list()) {
        if (entity is File && entity.path.endsWith('.pack')) {
          final destPath = path.join(tempContentDir.path, path.basename(entity.path));
          await entity.copy(destPath);
        }
      }

      // Update params with temp content folder
      final publishParams = params.copyWith(
        contentFolder: tempContentDir.path,
      );

      // Generate VDF file
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

      // Build steamcmd command
      final command = <String>[
        '+login',
        username,
        password,
        if (steamGuardCode != null) steamGuardCode,
        '+workshop_build_item',
        vdfPath,
        '+quit',
      ];

      _outputController.add('Starting steamcmd...');
      _progressController.add(0.05);

      // Execute steamcmd
      _currentProcess = await Process.start(
        steamCmdPath,
        command,
        runInShell: false,
      );

      final stdout = StringBuffer();
      String? detectedWorkshopId;
      bool wasUpdate = !params.isNewItem;
      bool steamGuardRequired = false;

      _currentProcess!.stdout.listen((data) {
        final output = String.fromCharCodes(data);
        stdout.write(output);

        // Emit each line to output stream (redact credentials)
        for (final line in output.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            _outputController.add(trimmed);
          }
        }

        // Parse progress
        _tryExtractProgress(output);

        // Detect published file ID
        final publishIdMatch =
            RegExp(r'PublishFileID\s*[:=]\s*(\d+)').firstMatch(output);
        if (publishIdMatch != null) {
          detectedWorkshopId = publishIdMatch.group(1);
        }

        // Detect successful update
        if (output.contains('Item Updated')) {
          wasUpdate = true;
        }

        // Detect Steam Guard requirement
        if (output.contains('Steam Guard') ||
            output.contains('Two-factor') ||
            output.contains('two factor') ||
            output.contains('Enter the current code')) {
          steamGuardRequired = true;
        }
      });

      _currentProcess!.stderr.listen((data) {
        final output = String.fromCharCodes(data);
        stdout.write(output);
        for (final line in output.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            _outputController.add('[stderr] $trimmed');
          }
        }
      });

      // Wait for completion with 30 min timeout
      final exitCode = await _currentProcess!.exitCode.timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          _currentProcess?.kill();
          return -1;
        },
      );

      // Clean up VDF file
      try {
        await File(vdfPath).delete();
      } catch (_) {}

      if (exitCode == -1) {
        return Err(const SteamCmdTimeoutException(
          'Publish operation timed out after 30 minutes',
          timeoutSeconds: 1800,
        ));
      }

      if (_isCancelled) {
        return Err(const SteamServiceException(
          'Publish cancelled by user',
          code: 'PUBLISH_CANCELLED',
        ));
      }

      // Check for Steam Guard requirement
      if (steamGuardRequired && steamGuardCode == null) {
        return Err(const SteamGuardRequiredException(
          'Steam Guard code is required to authenticate',
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
      // Clean up temp content directory
      if (tempContentDir != null) {
        try {
          await tempContentDir.delete(recursive: true);
        } catch (_) {}
      }
    }
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
