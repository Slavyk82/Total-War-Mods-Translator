import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/i_steamcmd_service.dart';
import 'package:twmt/services/steam/steamcmd_manager.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/steamcmd_download_result.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of SteamCMD service
class SteamCmdServiceImpl implements ISteamCmdService {
  final SteamCmdManager _manager = SteamCmdManager();
  final LoggingService _logger = LoggingService.instance;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  Process? _currentProcess;
  bool _isCancelled = false;

  @override
  Stream<double> get progressStream => _progressController.stream;

  @override
  Future<Result<SteamCmdDownloadResult, SteamServiceException>> downloadMod({
    required String workshopId,
    required int appId,
    String? outputDirectory,
    bool forceUpdate = false,
  }) async {
    final startTime = DateTime.now();

    try {
      // Validate Workshop ID
      if (!_isValidWorkshopId(workshopId)) {
        return Err(InvalidWorkshopIdException(
          'Invalid Workshop ID format',
          invalidId: workshopId,
        ));
      }

      // Ensure SteamCMD is available
      final steamCmdPathResult = await _manager.getSteamCmdPath();
      if (steamCmdPathResult is Err) {
        return Err(steamCmdPathResult.error);
      }
      final steamCmdPath = (steamCmdPathResult as Ok).value as String;

      // Initialize if needed
      final initResult = await _manager.initialize();
      if (initResult is Err) {
        return Err(initResult.error);
      }

      // Determine download path
      final downloadPath = outputDirectory ??
          await _manager.getWorkshopCacheDir(appId);

      // Check if already downloaded
      final modPath = path.join(downloadPath, workshopId);
      final isUpdate = await Directory(modPath).exists();
      DateTime? previousTimestamp;

      if (isUpdate && !forceUpdate) {
        final stat = await Directory(modPath).stat();
        previousTimestamp = stat.modified;
      }

      _logger.info('Downloading Workshop mod: $workshopId (App: $appId)');
      _logger.info('Download path: $downloadPath');

      // Build SteamCMD command
      // +login anonymous +workshop_download_item <appId> <workshopId> +quit
      final command = [
        '+login',
        'anonymous',
        '+force_install_dir',
        downloadPath,
        '+workshop_download_item',
        appId.toString(),
        workshopId,
        if (forceUpdate) 'validate',
        '+quit',
      ];

      _logger.info('Executing: $steamCmdPath ${command.join(" ")}');

      // Execute SteamCMD (runInShell: false for security - prevents command injection)
      _currentProcess = await Process.start(
        steamCmdPath,
        command,
        runInShell: false,
      );

      // Capture output
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final warnings = <String>[];

      _currentProcess!.stdout.listen((data) {
        final output = String.fromCharCodes(data);
        stdout.write(output);

        // Try to extract progress (SteamCMD progress format varies)
        _tryExtractProgress(output);

        // Collect warnings
        if (output.toLowerCase().contains('warning')) {
          warnings.add(output.trim());
        }
      });

      _currentProcess!.stderr.listen((data) {
        stderr.write(String.fromCharCodes(data));
      });

      // Wait for completion with timeout (10 minutes)
      final exitCode = await _currentProcess!.exitCode.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          _currentProcess?.kill();
          return -1;
        },
      );

      if (exitCode == -1) {
        return Err(const SteamCmdTimeoutException(
          'Download timed out',
          timeoutSeconds: 600,
        ));
      }

      if (_isCancelled) {
        return Err(const SteamServiceException(
          'Download cancelled by user',
          code: 'DOWNLOAD_CANCELLED',
        ));
      }

      // Check for success
      // SteamCMD can exit with 0, 6, or 7 and still be successful
      if (exitCode != 0 && exitCode != 6 && exitCode != 7) {
        final errorMsg = _parseErrorMessage(stderr.toString());
        return Err(WorkshopDownloadException(
          errorMsg,
          workshopId: workshopId,
        ));
      }

      // Verify download succeeded
      if (!await Directory(modPath).exists()) {
        return Err(WorkshopDownloadException(
          'Mod directory not found after download',
          workshopId: workshopId,
        ));
      }

      // Calculate download size
      final sizeBytes = await _calculateDirectorySize(modPath);

      // List downloaded files
      final downloadedFiles = await _listRelativeFiles(modPath);

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      _logger.info(
          'Download complete: $workshopId (${sizeBytes ~/ 1024}KB, ${duration}ms)');

      _progressController.add(1.0);

      return Ok(SteamCmdDownloadResult(
        workshopId: workshopId,
        appId: appId,
        downloadPath: modPath,
        sizeBytes: sizeBytes,
        durationMs: duration,
        timestamp: DateTime.now(),
        wasUpdate: isUpdate,
        previousVersionTimestamp: previousTimestamp,
        downloadedFiles: downloadedFiles,
        warnings: warnings.isNotEmpty ? warnings : null,
      ));
    } catch (e, stackTrace) {
      return Err(WorkshopDownloadException(
        'Download failed: $e',
        workshopId: workshopId,
        stackTrace: stackTrace,
      ));
    } finally {
      _currentProcess = null;
      _isCancelled = false;
      _progressController.add(1.0);
    }
  }

  @override
  Future<Result<bool, SteamServiceException>> checkForUpdate({
    required String workshopId,
    required int appId,
    required String localPath,
  }) async {
    try {
      // Check if local mod exists
      if (!await Directory(localPath).exists()) {
        return const Ok(true); // Needs download
      }

      // Get local timestamp
      final stat = await Directory(localPath).stat();
      final localTimestamp = stat.modified;

      _logger.info('Local mod timestamp: $localTimestamp');

      // Note: To properly check for updates, we would need to:
      // 1. Query Workshop API for remote timestamp
      // 2. Compare with local timestamp
      // For now, return false (assuming up-to-date)
      // This will be enhanced when Workshop API service is implemented

      return const Ok(false);
    } catch (e, stackTrace) {
      return Err(SteamServiceException(
        'Update check failed: $e',
        code: 'UPDATE_CHECK_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<String> getModPath({
    required String workshopId,
    required int appId,
  }) async {
    final cacheDir = await _manager.getWorkshopCacheDir(appId);
    return path.join(cacheDir, workshopId);
  }

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    _currentProcess?.kill();
    _currentProcess = null;
  }

  @override
  Future<bool> isSteamCmdAvailable() async {
    return await _manager.isAvailable();
  }

  @override
  Future<Result<String, SteamServiceException>> getSteamCmdVersion() async {
    return await _manager.getVersion();
  }

  /// Validate Workshop ID format
  ///
  /// Steam Workshop IDs must be:
  /// - Numeric only (digits 0-9)
  /// - Between 7 and 20 digits (typical range for Steam IDs)
  /// - No special characters (prevents command injection)
  bool _isValidWorkshopId(String workshopId) {
    // Check format: digits only, length 7-20
    if (!RegExp(r'^\d{7,20}$').hasMatch(workshopId)) {
      return false;
    }

    // Validate range (must fit in uint64: max 2^64 - 1)
    try {
      final id = BigInt.parse(workshopId);
      final maxUint64 = BigInt.parse('18446744073709551615');
      return id > BigInt.zero && id <= maxUint64;
    } catch (e) {
      return false;
    }
  }

  /// Try to extract progress from SteamCMD output
  void _tryExtractProgress(String output) {
    // SteamCMD progress format: "Downloading item 123 ... X%"
    final progressRegex = RegExp(r'(\d+)%');
    final match = progressRegex.firstMatch(output);

    if (match != null) {
      final percentage = int.parse(match.group(1)!);
      _progressController.add(percentage / 100.0);
    }
  }

  /// Parse error message from SteamCMD stderr
  String _parseErrorMessage(String stderr) {
    if (stderr.trim().isEmpty) return 'Unknown error';

    // Extract first meaningful line
    final lines = stderr
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return lines.isNotEmpty ? lines.first : 'Unknown error';
  }

  /// Calculate total size of directory
  Future<int> _calculateDirectorySize(String dirPath) async {
    int totalSize = 0;
    final dir = Directory(dirPath);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        totalSize += stat.size;
      }
    }

    return totalSize;
  }

  /// List files in directory with relative paths
  Future<List<String>> _listRelativeFiles(String dirPath) async {
    final files = <String>[];
    final dir = Directory(dirPath);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: dirPath);
        files.add(relativePath);
      }
    }

    return files;
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
    _currentProcess?.kill();
  }
}
