import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/game_definitions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for auto-detecting Steam and Total War game installations on Windows
/// Supports installations on any drive letter, not just C:
class SteamDetectionService {
  final LoggingService _logger = LoggingService.instance;

  /// Cache for detected Steam libraries to avoid repeated scans
  List<String>? _cachedLibraries;

  /// Clear the cached libraries (useful when user changes Steam configuration)
  void clearCache() {
    _cachedLibraries = null;
  }

  /// Detect all installed Total War games
  Future<Result<Map<String, String>, SteamServiceException>>
      detectAllGames() async {
    try {
      _logger.info('Starting auto-detection of Total War games...');

      final steamLibraries = await _detectSteamLibraries();
      if (steamLibraries.isEmpty) {
        _logger.warning('No Steam libraries found');
        return const Ok({});
      }

      final detectedGames = <String, String>{};

      for (final gameCode in supportedGames.keys) {
        final gameInfo = supportedGames[gameCode]!;
        final gamePath = await _findGameInLibraries(steamLibraries, gameInfo);

        if (gamePath != null) {
          detectedGames[gameCode] = gamePath;
          _logger.info('Detected ${gameInfo.name} at: $gamePath');
        }
      }

      _logger.info(
          'Auto-detection complete. Found ${detectedGames.length} games.');
      return Ok(detectedGames);
    } catch (e, stackTrace) {
      return Err(SteamServiceException(
        'Failed to detect games: $e',
        code: 'DETECTION_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Detect a specific game installation
  Future<Result<String?, SteamServiceException>> detectGame(
      String gameCode) async {
    try {
      final gameInfo = supportedGames[gameCode];
      if (gameInfo == null) {
        return Err(SteamServiceException(
          'Unknown game code: $gameCode',
          code: 'INVALID_GAME_CODE',
        ));
      }

      _logger.info('Detecting ${gameInfo.name}...');

      final steamLibraries = await _detectSteamLibraries();
      if (steamLibraries.isEmpty) {
        _logger.warning('No Steam libraries found');
        return const Ok(null);
      }

      final gamePath = await _findGameInLibraries(steamLibraries, gameInfo);

      if (gamePath != null) {
        _logger.info('Found ${gameInfo.name} at: $gamePath');
      } else {
        _logger.info('${gameInfo.name} not found');
      }

      return Ok(gamePath);
    } catch (e, stackTrace) {
      return Err(SteamServiceException(
        'Failed to detect game: $e',
        code: 'DETECTION_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Detect Steam Workshop content folder
  Future<Result<String?, SteamServiceException>> detectWorkshopFolder() async {
    try {
      _logger.info('Detecting Steam Workshop folder...');

      final steamLibraries = await _detectSteamLibraries();
      if (steamLibraries.isEmpty) {
        return const Ok(null);
      }

      // Workshop content is in steamapps/workshop/content
      for (final libraryPath in steamLibraries) {
        final workshopPath =
            path.join(libraryPath, 'steamapps', 'workshop', 'content');
        if (await Directory(workshopPath).exists()) {
          _logger.info('Found Workshop folder at: $workshopPath');
          return Ok(workshopPath);
        }
      }

      _logger.info('Workshop folder not found');
      return const Ok(null);
    } catch (e, stackTrace) {
      return Err(SteamServiceException(
        'Failed to detect Workshop folder: $e',
        code: 'DETECTION_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Detect Steam library folders using multiple methods
  Future<List<String>> _detectSteamLibraries() async {
    // Return cached libraries if available
    if (_cachedLibraries != null) {
      return _cachedLibraries!;
    }

    final libraries = <String>{};

    // Method 1: Check Windows registry (most reliable)
    final registryPath = await _getPathFromRegistry();
    if (registryPath != null) {
      libraries.add(registryPath);
      _logger.debug('Found Steam via registry: $registryPath');

      // Read additional libraries from VDF
      await _readLibraryFoldersVdf(registryPath, libraries);
    }

    // Method 2: Scan all drives for Steam installations
    if (libraries.isEmpty) {
      _logger.debug('Registry lookup failed, scanning drives...');
      await _scanAllDrivesForSteam(libraries);
    }

    // Read VDF from each found Steam installation to get all libraries
    for (final steamPath in libraries.toList()) {
      await _readLibraryFoldersVdf(steamPath, libraries);
    }

    _cachedLibraries = libraries.toList();
    _logger.info('Detected ${_cachedLibraries!.length} Steam libraries');

    return _cachedLibraries!;
  }

  /// Get Steam installation path from Windows registry
  /// Checks both HKCU and HKLM
  Future<String?> _getPathFromRegistry() async {
    if (!Platform.isWindows) return null;

    // Try HKCU first (current user installation)
    var steamPath = await _queryRegistry('HKCU\\Software\\Valve\\Steam');
    if (steamPath != null) return steamPath;

    // Try HKLM for system-wide installation
    steamPath = await _queryRegistry('HKLM\\Software\\Valve\\Steam');
    if (steamPath != null) return steamPath;

    // Try HKLM WOW64 node (32-bit Steam on 64-bit Windows)
    steamPath =
        await _queryRegistry('HKLM\\Software\\WOW6432Node\\Valve\\Steam');

    return steamPath;
  }

  /// Query Windows registry for Steam path
  Future<String?> _queryRegistry(String keyPath) async {
    try {
      final result = await Process.run(
        'reg',
        ['query', keyPath, '/v', 'SteamPath'],
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Parse output: "SteamPath    REG_SZ    C:\Program Files (x86)\Steam"
        final pathMatch =
            RegExp(r'SteamPath\s+REG_SZ\s+(.+)').firstMatch(output);
        if (pathMatch != null) {
          final steamPath = pathMatch.group(1)?.trim();
          if (steamPath != null && await Directory(steamPath).exists()) {
            return steamPath;
          }
        }
      }

      // Also try InstallPath as fallback
      final result2 = await Process.run(
        'reg',
        ['query', keyPath, '/v', 'InstallPath'],
      );

      if (result2.exitCode == 0) {
        final output = result2.stdout as String;
        final pathMatch =
            RegExp(r'InstallPath\s+REG_SZ\s+(.+)').firstMatch(output);
        if (pathMatch != null) {
          final steamPath = pathMatch.group(1)?.trim();
          if (steamPath != null && await Directory(steamPath).exists()) {
            return steamPath;
          }
        }
      }
    } catch (e) {
      _logger.debug('Failed to query registry $keyPath: $e');
    }

    return null;
  }

  /// Scan all available drives for Steam installations
  Future<void> _scanAllDrivesForSteam(Set<String> libraries) async {
    try {
      // Get list of all drive letters on Windows
      final drives = await _getWindowsDrives();

      for (final drive in drives) {
        // Common Steam installation patterns
        final patterns = [
          '$drive\\Program Files (x86)\\Steam',
          '$drive\\Program Files\\Steam',
          '$drive\\Steam',
          '$drive\\SteamLibrary',
          '$drive\\Games\\Steam',
          '$drive\\Games\\SteamLibrary',
        ];

        for (final steamPath in patterns) {
          if (await Directory(steamPath).exists()) {
            // Verify it's a real Steam installation by checking for steamapps
            final steamappsPath = path.join(steamPath, 'steamapps');
            if (await Directory(steamappsPath).exists()) {
              libraries.add(steamPath);
              _logger.debug('Found Steam at: $steamPath');
            }
          }
        }
      }
    } catch (e) {
      _logger.warning('Failed to scan drives for Steam: $e');
    }
  }

  /// Get list of all Windows drive letters
  Future<List<String>> _getWindowsDrives() async {
    final drives = <String>[];

    try {
      final result = await Process.run(
        'wmic',
        ['logicaldisk', 'get', 'name'],
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Parse output: "Name\nC:\nD:\nE:\n"
        final driveRegex = RegExp(r'([A-Z]:)');
        final matches = driveRegex.allMatches(output);

        for (final match in matches) {
          final drive = match.group(1);
          if (drive != null) {
            drives.add(drive);
          }
        }
      }
    } catch (e) {
      _logger.debug('WMIC failed, using fallback drive detection: $e');
    }

    // Fallback: check common drive letters if WMIC fails
    if (drives.isEmpty) {
      for (var letter = 'A'.codeUnitAt(0);
          letter <= 'Z'.codeUnitAt(0);
          letter++) {
        final drive = '${String.fromCharCode(letter)}:';
        if (await Directory(drive).exists()) {
          drives.add(drive);
        }
      }
    }

    return drives;
  }

  /// Read Steam's libraryfolders.vdf to find additional library locations
  Future<void> _readLibraryFoldersVdf(
      String steamPath, Set<String> libraries) async {
    try {
      final vdfPath = path.join(steamPath, 'steamapps', 'libraryfolders.vdf');
      final vdfFile = File(vdfPath);

      if (!await vdfFile.exists()) {
        _logger.debug('libraryfolders.vdf not found at: $vdfPath');
        return;
      }

      final content = await vdfFile.readAsString();

      // Parse VDF format to extract library paths
      // Supports both old and new VDF formats:
      // Old: "1"  "D:\\SteamLibrary"
      // New: "path"  "D:\\SteamLibrary"
      final pathPatterns = [
        RegExp(r'"path"\s*"([^"]+)"'), // New format
        RegExp(r'"\d+"\s*"([A-Z]:\\[^"]+)"'), // Old format (numeric keys with paths)
      ];

      for (final regex in pathPatterns) {
        final matches = regex.allMatches(content);
        for (final match in matches) {
          var libraryPath = match.group(1);
          if (libraryPath != null) {
            // Handle escaped backslashes in VDF files
            libraryPath = libraryPath.replaceAll('\\\\', '\\');

            // Verify the directory exists
            if (await Directory(libraryPath).exists()) {
              libraries.add(libraryPath);
              _logger.debug('Found library from VDF: $libraryPath');
            }
          }
        }
      }
    } catch (e) {
      _logger.warning('Failed to read libraryfolders.vdf from $steamPath: $e');
    }
  }

  /// Find a game in the detected Steam libraries
  /// Uses ACF manifest files for accurate detection, with folder name as fallback
  Future<String?> _findGameInLibraries(
    List<String> libraries,
    GameInfo gameInfo,
  ) async {
    for (final libraryPath in libraries) {
      // Method 1: Check ACF manifest file (most accurate)
      final acfPath = await _findGameViaAcf(libraryPath, gameInfo.steamAppId);
      if (acfPath != null) {
        return acfPath;
      }

      // Method 2: Check standard folder name
      final gamePath = path.join(
        libraryPath,
        'steamapps',
        'common',
        gameInfo.folderName,
      );

      if (await _validateGameInstallation(gamePath)) {
        return gamePath;
      }
    }

    return null;
  }

  /// Find game installation path via Steam ACF manifest file
  /// This is the most reliable method as it contains the actual install directory
  Future<String?> _findGameViaAcf(String libraryPath, String appId) async {
    try {
      final acfPath =
          path.join(libraryPath, 'steamapps', 'appmanifest_$appId.acf');
      final acfFile = File(acfPath);

      if (!await acfFile.exists()) {
        return null;
      }

      final content = await acfFile.readAsString();

      // Parse ACF file to get installdir
      // Format: "installdir"  "Total War WARHAMMER III"
      final installDirMatch =
          RegExp(r'"installdir"\s*"([^"]+)"').firstMatch(content);

      if (installDirMatch != null) {
        final installDir = installDirMatch.group(1);
        if (installDir != null) {
          final gamePath =
              path.join(libraryPath, 'steamapps', 'common', installDir);

          if (await _validateGameInstallation(gamePath)) {
            _logger.debug('Found game via ACF: $gamePath');
            return gamePath;
          }
        }
      }
    } catch (e) {
      _logger.debug('Failed to read ACF for app $appId: $e');
    }

    return null;
  }

  /// Validate that a game installation exists and contains valid game files
  Future<bool> _validateGameInstallation(String gamePath) async {
    try {
      final gameDir = Directory(gamePath);
      if (!await gameDir.exists()) {
        return false;
      }

      // Check for .exe files (basic validation)
      final entities = await gameDir.list().toList();
      final hasExe =
          entities.any((e) => e is File && e.path.toLowerCase().endsWith('.exe'));

      return hasExe;
    } catch (e) {
      return false;
    }
  }
}
