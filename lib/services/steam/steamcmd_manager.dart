import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:twmt/config/database_config.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Manager for SteamCMD installation and configuration
///
/// Handles auto-download, installation, and version management of SteamCMD
class SteamCmdManager {
  /// SteamCMD download URL (Windows)
  static const String downloadUrl =
      'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip';

  /// SteamCMD executable name
  static const String exeName = 'steamcmd.exe';

  /// Singleton instance
  static final SteamCmdManager _instance = SteamCmdManager._internal();

  /// Dio client for downloads
  final Dio _dio = Dio();

  /// Logger
  final LoggingService _logger = LoggingService.instance;

  /// Cached SteamCMD path
  String? _cachedSteamCmdPath;

  /// Whether SteamCMD is initialized
  bool _isInitialized = false;

  factory SteamCmdManager() => _instance;

  SteamCmdManager._internal();

  /// Get SteamCMD executable path
  ///
  /// Searches in order:
  /// 1. Bundled with app (tools/steamcmd/)
  /// 2. AppData/Local/TWMT/tools/steamcmd/
  /// 3. System PATH
  ///
  /// Returns path if found, throws [SteamCmdNotFoundException] if not found
  Future<Result<String, SteamServiceException>> getSteamCmdPath() async {
    // Return cached path if available
    if (_cachedSteamCmdPath != null &&
        await File(_cachedSteamCmdPath!).exists()) {
      return Ok(_cachedSteamCmdPath!);
    }

    final searchPaths = <String>[];

    try {
      // 1. Check bundled location (next to executable)
      final executableDir = path.dirname(Platform.resolvedExecutable);
      final bundledPath =
          path.join(executableDir, 'tools', 'steamcmd', exeName);
      searchPaths.add(bundledPath);

      if (await File(bundledPath).exists()) {
        _cachedSteamCmdPath = bundledPath;
        return Ok(bundledPath);
      }

      // 2. Check AppData location
      final appDataDir = await DatabaseConfig.getAppSupportDirectory();
      final appDataPath =
          path.join(appDataDir, 'tools', 'steamcmd', exeName);
      searchPaths.add(appDataPath);

      if (await File(appDataPath).exists()) {
        _cachedSteamCmdPath = appDataPath;
        return Ok(appDataPath);
      }

      // 3. Check system PATH
      final pathEnv = Platform.environment['PATH'] ?? '';
      final pathDirs = pathEnv.split(';');

      for (final dir in pathDirs) {
        final systemPath = path.join(dir, exeName);
        searchPaths.add(systemPath);

        if (await File(systemPath).exists()) {
          _cachedSteamCmdPath = systemPath;
          return Ok(systemPath);
        }
      }

      // Not found anywhere
      return Err(SteamCmdNotFoundException(
        'SteamCMD not found. Please download it or install via app.',
        searchedPaths: searchPaths.join('; '),
      ));
    } catch (e, stackTrace) {
      return Err(SteamServiceException(
        'Error searching for SteamCMD: $e',
        code: 'STEAMCMD_SEARCH_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Download and install SteamCMD
  ///
  /// Downloads from Valve CDN and extracts to AppData
  Future<Result<String, SteamServiceException>> downloadAndInstall({
    void Function(double progress)? onProgress,
  }) async {
    try {
      _logger.info('Downloading SteamCMD from Valve CDN...');

      // Download to temp directory
      final tempDir = await Directory.systemTemp.createTemp('steamcmd_download_');
      final downloadPath = path.join(tempDir.path, 'steamcmd.zip');

      _logger.info('Downloading from: $downloadUrl');

      await _dio.download(
        downloadUrl,
        downloadPath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      // Extract to AppData
      final appDataDir = await DatabaseConfig.getAppSupportDirectory();
      final installDir = path.join(appDataDir, 'tools', 'steamcmd');
      await Directory(installDir).create(recursive: true);

      _logger.info('Extracting to: $installDir');

      // Extract ZIP
      await _extractZip(downloadPath, installDir);

      // Find extracted executable
      final exePath = path.join(installDir, exeName);

      if (!await File(exePath).exists()) {
        return Err(const SteamCmdDownloadException(
          'Executable not found after extraction',
        ));
      }

      // Cleanup temp files
      await tempDir.delete(recursive: true);

      // Cache path
      _cachedSteamCmdPath = exePath;

      _logger.info('SteamCMD installed successfully: $exePath');

      return Ok(exePath);
    } catch (e, stackTrace) {
      return Err(SteamCmdDownloadException(
        'Download failed: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Initialize SteamCMD (anonymous login)
  ///
  /// Runs initial setup and creates Steam directory structure
  Future<Result<void, SteamServiceException>> initialize() async {
    if (_isInitialized) {
      return const Ok(null);
    }

    final steamCmdPathResult = await getSteamCmdPath();
    if (steamCmdPathResult is Err) {
      return Err(steamCmdPathResult.error);
    }

    final steamCmdPath = (steamCmdPathResult as Ok).value as String;

    try {
      _logger.info('Initializing SteamCMD (anonymous login)...');

      // Run SteamCMD with +quit to initialize
      // This creates the Steam directory structure
      final result = await Process.run(
        steamCmdPath,
        ['+login', 'anonymous', '+quit'],
        runInShell: true,
      );

      // SteamCMD exits with 0 for success, 7 for "no connection" which is fine
      if (result.exitCode != 0 && result.exitCode != 7) {
        _logger.warning(
            'SteamCMD initialization exit code: ${result.exitCode}');
        _logger.warning('Stderr: ${result.stderr}');
      }

      _isInitialized = true;
      _logger.info('SteamCMD initialized successfully');

      return const Ok(null);
    } catch (e, stackTrace) {
      return Err(SteamCmdInitializationException(
        'Initialization failed: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Check if SteamCMD is available and ready
  Future<bool> isAvailable() async {
    final pathResult = await getSteamCmdPath();
    if (pathResult is Err) return false;

    return true;
  }

  /// Get SteamCMD version
  ///
  /// Note: SteamCMD doesn't have a traditional version command.
  /// This checks if it's installed and working.
  Future<Result<String, SteamServiceException>> getVersion() async {
    final steamCmdPathResult = await getSteamCmdPath();
    if (steamCmdPathResult is Err) {
      return Err(steamCmdPathResult.error);
    }

    final steamCmdPath = (steamCmdPathResult as Ok).value as String;

    try {
      // Check file modification date as version proxy
      final stat = await File(steamCmdPath).stat();
      final version =
          'SteamCMD (installed ${stat.modified.toIso8601String().split('T')[0]})';

      return Ok(version);
    } catch (e, stackTrace) {
      return Err(SteamServiceException(
        'Error getting version: $e',
        code: 'VERSION_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Extract ZIP archive
  Future<void> _extractZip(String zipPath, String outputDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      final filePath = path.join(outputDir, filename);

      if (file.isFile) {
        final data = file.content as List<int>;
        await File(filePath).create(recursive: true);
        await File(filePath).writeAsBytes(data);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }

  /// Get Workshop download cache directory
  ///
  /// Returns the directory where SteamCMD downloads Workshop content
  Future<String> getWorkshopCacheDir(int appId) async {
    final appDataDir = await DatabaseConfig.getAppSupportDirectory();
    final steamCmdDir = path.join(appDataDir, 'tools', 'steamcmd');

    // SteamCMD downloads to: steamcmd/steamapps/workshop/content/{appId}
    return path.join(steamCmdDir, 'steamapps', 'workshop', 'content',
        appId.toString());
  }

  /// Clear cached path (force re-detection)
  void clearCache() {
    _cachedSteamCmdPath = null;
    _isInitialized = false;
  }
}
