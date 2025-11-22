import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/service_locator.dart';

/// Manager for RPFM-CLI installation and configuration
class RpfmCliManager {
  /// Minimum required RPFM-CLI version
  static const String minRequiredVersion = '4.0.0';

  /// GitHub repository for RPFM-CLI releases
  static const String githubRepo = 'Frodo45127/rpfm';

  /// GitHub API URL for latest release
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  /// RPFM-CLI executable name
  static const String exeName = 'rpfm_cli.exe';

  /// Singleton instance
  static final RpfmCliManager _instance = RpfmCliManager._internal();

  /// Dio client for downloads
  final Dio _dio = Dio();

  /// Logger
  final LoggingService _logger = LoggingService.instance;

  /// Cached RPFM path
  String? _cachedRpfmPath;

  factory RpfmCliManager() => _instance;

  RpfmCliManager._internal();

  /// Get Total War game setting for RPFM operations
  ///
  /// Returns the configured game from settings or 'warhammer_3' as default
  Future<Result<String, RpfmServiceException>> getGameSetting() async {
    try {
      final settingsService = ServiceLocator.get<SettingsService>();
      final game = await settingsService.getTotalWarGame();
      return Ok(game);
    } catch (e) {
      _logger.warning('Could not get game setting, using default: $e');
      // Return default game if settings service is not available
      return const Ok('warhammer_3');
    }
  }

  /// Get RPFM schema path from settings
  ///
  /// Returns the configured schema path from settings or null if not set
  Future<String?> getSchemaPath() async {
    try {
      final settingsService = ServiceLocator.get<SettingsService>();
      final schemaPath = await settingsService.getString('rpfm_schema_path');

      if (schemaPath.isEmpty) {
        _logger.warning('RPFM schema path not configured in settings');
        return null;
      }

      _logger.info('Using RPFM schema path: $schemaPath');
      return schemaPath;
    } catch (e) {
      _logger.warning('Could not get schema path from settings: $e');
      return null;
    }
  }

  /// Get RPFM-CLI executable path
  ///
  /// Searches in order:
  /// 1. User-configured path in settings
  /// 2. Bundled with app (tools/rpfm-cli/)
  /// 3. System PATH
  /// 4. AppData/Local/TWMT/tools/rpfm-cli/
  ///
  /// Returns path if found, throws [RpfmNotFoundException] if not found
  Future<Result<String, RpfmServiceException>> getRpfmPath() async {
    // Return cached path if available
    if (_cachedRpfmPath != null && await File(_cachedRpfmPath!).exists()) {
      return Ok(_cachedRpfmPath!);
    }

    final searchPaths = <String>[];

    try {
      // 0. Check user-configured path from settings (highest priority)
      try {
        final settingsService = ServiceLocator.get<SettingsService>();
        final customPath = await settingsService.getRpfmPath();

        if (customPath != null && customPath.isNotEmpty) {
          searchPaths.add(customPath);

          if (await File(customPath).exists()) {
            _cachedRpfmPath = customPath;
            _logger.info('Using user-configured RPFM path: $customPath');
            return Ok(customPath);
          } else {
            _logger.warning('User-configured RPFM path not found: $customPath');
          }
        }
      } catch (e) {
        // If settings service is not available or fails, continue with other search methods
        _logger.warning('Could not check settings for RPFM path: $e');
      }

      // 1. Check bundled location (next to executable)
      final executableDir = path.dirname(Platform.resolvedExecutable);
      final bundledPath = path.join(executableDir, 'tools', 'rpfm-cli', exeName);
      searchPaths.add(bundledPath);

      if (await File(bundledPath).exists()) {
        _cachedRpfmPath = bundledPath;
        return Ok(bundledPath);
      }

      // 2. Check AppData location
      final appDataDir = await getApplicationSupportDirectory();
      final appDataPath =
          path.join(appDataDir.path, 'tools', 'rpfm-cli', exeName);
      searchPaths.add(appDataPath);

      if (await File(appDataPath).exists()) {
        _cachedRpfmPath = appDataPath;
        return Ok(appDataPath);
      }

      // 3. Check system PATH
      final pathEnv = Platform.environment['PATH'] ?? '';
      final pathDirs = pathEnv.split(';');

      for (final dir in pathDirs) {
        final systemPath = path.join(dir, exeName);
        searchPaths.add(systemPath);

        if (await File(systemPath).exists()) {
          _cachedRpfmPath = systemPath;
          return Ok(systemPath);
        }
      }

      // Not found anywhere
      return Err(RpfmNotFoundException(
        'RPFM-CLI not found. Please configure the path in Settings or download it.',
        searchedPaths: searchPaths.join('; '),
      ));
    } catch (e, stackTrace) {
      return Err(RpfmServiceException(
        'Error searching for RPFM-CLI: $e',
        code: 'RPFM_SEARCH_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get RPFM-CLI version
  ///
  /// Executes `rpfm_cli --version` and parses output
  Future<Result<String, RpfmServiceException>> getVersion() async {
    final rpfmPathResult = await getRpfmPath();
    if (rpfmPathResult is Err) {
      return Err(rpfmPathResult.error);
    }

    final rpfmPath = (rpfmPathResult as Ok<String, RpfmServiceException>).value;

    try {
      final result = await Process.run(rpfmPath, ['--version']);

      if (result.exitCode != 0) {
        return Err(RpfmServiceException(
          'Failed to get RPFM version: ${result.stderr}',
          code: 'RPFM_VERSION_ERROR',
        ));
      }

      // Parse version from output (format: "rpfm_cli 4.0.0")
      final output = result.stdout.toString().trim();
      final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output);

      if (versionMatch == null) {
        return Err(RpfmServiceException(
          'Could not parse RPFM version from: $output',
          code: 'RPFM_VERSION_PARSE_ERROR',
        ));
      }

      final version = versionMatch.group(1)!;
      return Ok(version);
    } catch (e, stackTrace) {
      return Err(RpfmServiceException(
        'Error getting RPFM version: $e',
        code: 'RPFM_VERSION_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Check if RPFM version is compatible
  ///
  /// Requires version >= 4.0.0
  Future<Result<bool, RpfmServiceException>> checkVersion() async {
    final versionResult = await getVersion();
    if (versionResult is Err) {
      return Err(versionResult.error);
    }

    final version = (versionResult as Ok<String, RpfmServiceException>).value;

    if (_compareVersions(version, minRequiredVersion) < 0) {
      return Err(RpfmVersionException(
        'RPFM version too old',
        currentVersion: version,
        requiredVersion: minRequiredVersion,
      ));
    }

    return const Ok(true);
  }

  /// Download and install RPFM-CLI
  ///
  /// Downloads latest release from GitHub and extracts to AppData
  Future<Result<String, RpfmServiceException>> downloadAndInstall({
    void Function(double progress)? onProgress,
  }) async {
    try {
      _logger.info('Downloading RPFM-CLI from GitHub...');

      // Get latest release info
      final releaseInfo = await _getLatestReleaseInfo();
      if (releaseInfo is Err) {
        return Err(releaseInfo.error);
      }

      final releaseData =
          (releaseInfo as Ok<Map<String, dynamic>, RpfmServiceException>)
              .value;

      // Find Windows asset
      final assets = releaseData['assets'] as List;
      final windowsAsset = assets.firstWhere(
        (asset) => (asset['name'] as String).contains('windows'),
        orElse: () => null,
      );

      if (windowsAsset == null) {
        return Err(RpfmDownloadException(
          'No Windows release found',
        ));
      }

      final downloadUrl = windowsAsset['browser_download_url'] as String;
      final assetName = windowsAsset['name'] as String;

      // Download to temp directory
      final tempDir = await Directory.systemTemp.createTemp('rpfm_download_');
      final downloadPath = path.join(tempDir.path, assetName);

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
      final appDataDir = await getApplicationSupportDirectory();
      final installDir = path.join(appDataDir.path, 'tools', 'rpfm-cli');
      await Directory(installDir).create(recursive: true);

      _logger.info('Extracting to: $installDir');

      // Extract ZIP
      await _extractZip(downloadPath, installDir);

      // Find extracted executable
      final exePath = path.join(installDir, exeName);

      if (!await File(exePath).exists()) {
        return Err(RpfmDownloadException(
          'Executable not found after extraction',
        ));
      }

      // Cleanup temp files
      await tempDir.delete(recursive: true);

      // Cache path
      _cachedRpfmPath = exePath;

      _logger.info('RPFM-CLI installed successfully: $exePath');

      return Ok(exePath);
    } catch (e, stackTrace) {
      return Err(RpfmDownloadException(
        'Download failed: $e',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get latest release info from GitHub API
  Future<Result<Map<String, dynamic>, RpfmServiceException>>
      _getLatestReleaseInfo() async {
    try {
      final response = await _dio.get(latestReleaseUrl);

      if (response.statusCode != 200) {
        return Err(RpfmDownloadException(
          'GitHub API request failed: ${response.statusCode}',
        ));
      }

      return Ok(response.data as Map<String, dynamic>);
    } catch (e, stackTrace) {
      return Err(RpfmDownloadException(
        'Failed to get release info: $e',
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

  /// Compare version strings
  ///
  /// Returns:
  /// - negative if v1 < v2
  /// - 0 if v1 == v2
  /// - positive if v1 > v2
  int _compareVersions(String v1, String v2) {
    final v1Parts = v1.split('.').map(int.parse).toList();
    final v2Parts = v2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final part1 = i < v1Parts.length ? v1Parts[i] : 0;
      final part2 = i < v2Parts.length ? v2Parts[i] : 0;

      if (part1 != part2) {
        return part1 - part2;
      }
    }

    return 0;
  }

  /// Check if RPFM is available and compatible
  Future<bool> isAvailable() async {
    final pathResult = await getRpfmPath();
    if (pathResult is Err) return false;

    final versionResult = await checkVersion();
    if (versionResult is Err) return false;

    return true;
  }

  /// Clear cached path (force re-detection)
  void clearCache() {
    _cachedRpfmPath = null;
  }

  /// Validate a custom RPFM-CLI executable path
  ///
  /// Tests if the provided path is a valid RPFM-CLI executable by:
  /// 1. Checking if file exists
  /// 2. Running --version command
  /// 3. Verifying version compatibility
  ///
  /// [customPath] - Path to RPFM-CLI executable to validate
  ///
  /// Returns [Ok(version)] if valid, [Err(RpfmServiceException)] if invalid
  static Future<Result<String, RpfmServiceException>> validateRpfmPath(
    String customPath,
  ) async {
    try {
      // Check if file exists
      final file = File(customPath);
      if (!await file.exists()) {
        return Err(RpfmNotFoundException(
          'File not found at specified path',
          searchedPaths: customPath,
        ));
      }

      // Check if it's an executable (.exe)
      if (!customPath.toLowerCase().endsWith('.exe')) {
        return Err(RpfmServiceException(
          'File must be an executable (.exe)',
          code: 'RPFM_INVALID_FILE',
        ));
      }

      // Try to execute --version command
      final result = await Process.run(customPath, ['--version']);

      if (result.exitCode != 0) {
        return Err(RpfmServiceException(
          'Failed to execute RPFM: ${result.stderr}',
          code: 'RPFM_EXECUTION_ERROR',
        ));
      }

      // Parse version from output (format: "rpfm_cli 4.0.0")
      final output = result.stdout.toString().trim();
      final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output);

      if (versionMatch == null) {
        return Err(RpfmServiceException(
          'Could not parse RPFM version. Make sure this is a valid RPFM-CLI executable.',
          code: 'RPFM_VERSION_PARSE_ERROR',
        ));
      }

      final version = versionMatch.group(1)!;

      // Check version compatibility
      final manager = RpfmCliManager();
      if (manager._compareVersions(version, minRequiredVersion) < 0) {
        return Err(RpfmVersionException(
          'RPFM version too old',
          currentVersion: version,
          requiredVersion: minRequiredVersion,
        ));
      }

      return Ok(version);
    } catch (e, stackTrace) {
      return Err(RpfmServiceException(
        'Error validating RPFM path: $e',
        code: 'RPFM_VALIDATION_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }
}
