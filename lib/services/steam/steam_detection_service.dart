import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for auto-detecting Steam and Total War game installations on Windows
class SteamDetectionService {
  final LoggingService _logger = LoggingService.instance;

  /// Total War games with their Steam App IDs and expected folder names
  static const Map<String, GameInfo> supportedGames = {
    'wh3': GameInfo(
      code: 'wh3',
      name: 'Total War: WARHAMMER III',
      steamAppId: '1142710',
      folderName: 'Total War WARHAMMER III',
    ),
    'wh2': GameInfo(
      code: 'wh2',
      name: 'Total War: WARHAMMER II',
      steamAppId: '594570',
      folderName: 'Total War WARHAMMER II',
    ),
    'wh': GameInfo(
      code: 'wh',
      name: 'Total War: WARHAMMER',
      steamAppId: '364360',
      folderName: 'Total War WARHAMMER',
    ),
    'rome2': GameInfo(
      code: 'rome2',
      name: 'Total War: Rome II',
      steamAppId: '214950',
      folderName: 'Total War Rome II',
    ),
    'attila': GameInfo(
      code: 'attila',
      name: 'Total War: Attila',
      steamAppId: '325610',
      folderName: 'Total War Attila',
    ),
    'troy': GameInfo(
      code: 'troy',
      name: 'Total War: Troy',
      steamAppId: '1099410',
      folderName: 'Troy',
    ),
    '3k': GameInfo(
      code: '3k',
      name: 'Total War: Three Kingdoms',
      steamAppId: '779340',
      folderName: 'Total War THREE KINGDOMS',
    ),
    'pharaoh': GameInfo(
      code: 'pharaoh',
      name: 'Total War: Pharaoh',
      steamAppId: '1937780',
      folderName: 'Total War PHARAOH',
    ),
    'pharaoh_dynasties': GameInfo(
      code: 'pharaoh_dynasties',
      name: 'Total War: Pharaoh Dynasties',
      steamAppId: '2951630',
      folderName: 'Total War PHARAOH DYNASTIES',
    ),
  };

  /// Detect all installed Total War games
  Future<Result<Map<String, String>, SteamServiceException>> detectAllGames() async {
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

      _logger.info('Auto-detection complete. Found ${detectedGames.length} games.');
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
  Future<Result<String?, SteamServiceException>> detectGame(String gameCode) async {
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
        final workshopPath = path.join(libraryPath, 'steamapps', 'workshop', 'content');
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

  /// Detect Steam library folders from Windows registry and config files
  Future<List<String>> _detectSteamLibraries() async {
    final libraries = <String>{};

    // Method 1: Check common installation paths
    final commonPaths = [
      'C:\\Program Files (x86)\\Steam',
      'C:\\Program Files\\Steam',
      'D:\\Steam',
      'E:\\Steam',
      'D:\\SteamLibrary',
      'E:\\SteamLibrary',
    ];

    for (final steamPath in commonPaths) {
      if (await Directory(steamPath).exists()) {
        libraries.add(steamPath);
        _logger.debug('Found Steam at: $steamPath');
      }
    }

    // Method 2: Try to read Steam config for additional libraries
    if (libraries.isNotEmpty) {
      final mainSteamPath = libraries.first;
      await _readLibraryFoldersVdf(mainSteamPath, libraries);
    }

    // Method 3: Try Windows registry (requires process execution)
    await _checkWindowsRegistry(libraries);

    return libraries.toList();
  }

  /// Read Steam's libraryfolders.vdf to find additional library locations
  Future<void> _readLibraryFoldersVdf(String steamPath, Set<String> libraries) async {
    try {
      final vdfPath = path.join(steamPath, 'steamapps', 'libraryfolders.vdf');
      final vdfFile = File(vdfPath);

      if (!await vdfFile.exists()) {
        return;
      }

      final content = await vdfFile.readAsString();
      
      // Parse VDF format to extract library paths
      // Format: "path"		"D:\\SteamLibrary"
      final pathRegex = RegExp(r'"path"\s+"([^"]+)"');
      final matches = pathRegex.allMatches(content);

      for (final match in matches) {
        final libraryPath = match.group(1);
        if (libraryPath != null) {
          // Replace double backslashes
          final normalizedPath = libraryPath.replaceAll('\\\\', '\\');
          if (await Directory(normalizedPath).exists()) {
            libraries.add(normalizedPath);
            _logger.debug('Found additional library: $normalizedPath');
          }
        }
      }
    } catch (e) {
      _logger.warning('Failed to read libraryfolders.vdf: $e');
    }
  }

  /// Check Windows registry for Steam installation path
  Future<void> _checkWindowsRegistry(Set<String> libraries) async {
    if (!Platform.isWindows) return;

    try {
      // Query registry for Steam installation path
      // HKEY_CURRENT_USER\Software\Valve\Steam\SteamPath
      final result = await Process.run(
        'reg',
        [
          'query',
          'HKCU\\Software\\Valve\\Steam',
          '/v',
          'SteamPath',
        ],
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Parse output: "SteamPath    REG_SZ    C:\Program Files (x86)\Steam"
        final pathMatch = RegExp(r'SteamPath\s+REG_SZ\s+(.+)').firstMatch(output);
        if (pathMatch != null) {
          final steamPath = pathMatch.group(1)?.trim();
          if (steamPath != null && await Directory(steamPath).exists()) {
            libraries.add(steamPath);
            _logger.debug('Found Steam via registry: $steamPath');
          }
        }
      }
    } catch (e) {
      _logger.debug('Failed to query Windows registry: $e');
    }
  }

  /// Find a game in the detected Steam libraries
  Future<String?> _findGameInLibraries(
    List<String> libraries,
    GameInfo gameInfo,
  ) async {
    for (final libraryPath in libraries) {
      // Check steamapps/common/[GAME_FOLDER]
      final gamePath = path.join(
        libraryPath,
        'steamapps',
        'common',
        gameInfo.folderName,
      );

      if (await Directory(gamePath).exists()) {
        // Verify it's a valid installation by checking for .exe
        final exeFiles = await Directory(gamePath)
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.exe'))
            .toList();

        if (exeFiles.isNotEmpty) {
          return gamePath;
        }
      }
    }

    return null;
  }
}

/// Information about a Total War game
class GameInfo {
  final String code;
  final String name;
  final String steamAppId;
  final String folderName;

  const GameInfo({
    required this.code,
    required this.name,
    required this.steamAppId,
    required this.folderName,
  });
}

