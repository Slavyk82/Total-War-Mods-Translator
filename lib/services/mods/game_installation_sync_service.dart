import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';

/// Service to sync game settings with game_installations table
class GameInstallationSyncService {
  final GameInstallationRepository _gameInstallationRepository;
  final SettingsService _settingsService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  /// Available games with their display names and Steam App IDs
  static const Map<String, _GameInfo> _availableGames = {
    'wh3': _GameInfo(
      code: 'wh3',
      name: 'Total War: WARHAMMER III',
      steamAppId: '1142710',
    ),
    'wh2': _GameInfo(
      code: 'wh2',
      name: 'Total War: WARHAMMER II',
      steamAppId: '594570',
    ),
    'wh': _GameInfo(
      code: 'wh',
      name: 'Total War: WARHAMMER',
      steamAppId: '364360',
    ),
    'rome2': _GameInfo(
      code: 'rome2',
      name: 'Total War: Rome II',
      steamAppId: '214950',
    ),
    'attila': _GameInfo(
      code: 'attila',
      name: 'Total War: Attila',
      steamAppId: '325610',
    ),
    'troy': _GameInfo(
      code: 'troy',
      name: 'Total War: Troy',
      steamAppId: '1099410',
    ),
    '3k': _GameInfo(
      code: '3k',
      name: 'Total War: Three Kingdoms',
      steamAppId: '779340',
    ),
    'pharaoh': _GameInfo(
      code: 'pharaoh',
      name: 'Total War: Pharaoh',
      steamAppId: '1937780',
    ),
  };

  GameInstallationSyncService({
    required GameInstallationRepository gameInstallationRepository,
    required SettingsService settingsService,
  })  : _gameInstallationRepository = gameInstallationRepository,
        _settingsService = settingsService;

  /// Sync all configured games from settings to database
  Future<Result<void, ServiceException>> syncAllGames() async {
    try {
      _logger.info('Syncing game installations from settings');

      for (final entry in _availableGames.entries) {
        final gameCode = entry.key;
        final gameInfo = entry.value;

        await _syncGame(gameCode, gameInfo);
      }

      _logger.info('Game installations sync completed');
      return const Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to sync game installations: $e', stackTrace);
      return Err(ServiceException(
        'Failed to sync game installations: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Sync a specific game from settings to database
  Future<Result<void, ServiceException>> syncGame(String gameCode) async {
    final gameInfo = _availableGames[gameCode];
    if (gameInfo == null) {
      return Err(ServiceException('Unknown game code: $gameCode'));
    }

    return await _syncGame(gameCode, gameInfo);
  }

  Future<Result<void, ServiceException>> _syncGame(
    String gameCode,
    _GameInfo gameInfo,
  ) async {
    try {
      // Get game path from settings
      final pathKey = _getGamePathKey(gameCode);
      final gamePath = await _settingsService.getString(pathKey);

      if (gamePath.isEmpty) {
        // No path configured in settings, skip
        return const Ok(null);
      }

      // Check if game installation already exists in database
      final existingResult =
          await _gameInstallationRepository.getByGameCode(gameCode);

      if (existingResult is Ok) {
        // Game installation exists, update if needed
        final existing = existingResult.value;
        
        // Check if paths have changed
        final installPathChanged = existing.installationPath != gamePath;
        final workshopPathMissing = existing.steamWorkshopPath == null || 
                                    existing.steamWorkshopPath!.isEmpty;
        
        if (installPathChanged || workshopPathMissing) {
          _logger.info('Updating game installation for $gameCode (install path changed: $installPathChanged, workshop missing: $workshopPathMissing)');
          
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          
          // Only detect Workshop path if it's missing
          // If installation path changes, keep existing Workshop path
          String? workshopPath = existing.steamWorkshopPath;
          if (workshopPathMissing) {
            workshopPath = await _detectWorkshopPath(gamePath, gameInfo.steamAppId);
            _logger.info('Detected Workshop path: $workshopPath');
          } else if (installPathChanged) {
            _logger.info('Installation path changed, keeping existing Workshop path: $workshopPath');
          }
          
          final updated = existing.copyWith(
            installationPath: gamePath,
            steamWorkshopPath: workshopPath,
            updatedAt: now,
          );

          final updateResult = await _gameInstallationRepository.update(updated);
          if (updateResult is Err) {
            return Err(ServiceException(
              'Failed to update game installation: ${updateResult.error.message}',
              error: updateResult.error,
            ));
          }
          
          _logger.info('Game installation updated successfully for $gameCode');
        }
      } else {
        // Game installation doesn't exist, create it
        _logger.info('Creating game installation for $gameCode');
        
        // Detect Workshop path
        final workshopPath = await _detectWorkshopPath(gamePath, gameInfo.steamAppId);
        
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final gameInstallation = GameInstallation(
          id: _uuid.v4(),
          gameCode: gameCode,
          gameName: gameInfo.name,
          installationPath: gamePath,
          steamWorkshopPath: workshopPath,
          steamAppId: gameInfo.steamAppId,
          isAutoDetected: false,
          isValid: await _validateGamePath(gamePath),
          lastValidatedAt: now,
          createdAt: now,
          updatedAt: now,
        );

        final insertResult = await _gameInstallationRepository.insert(gameInstallation);
        if (insertResult is Err) {
          return Err(ServiceException(
            'Failed to insert game installation: ${insertResult.error.message}',
            error: insertResult.error,
          ));
        }
        
        _logger.info('Game installation created successfully for $gameCode');
      }

      return const Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to sync game $gameCode: $e', stackTrace);
      return Err(ServiceException(
        'Failed to sync game $gameCode: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Detect Workshop path based on settings or game installation path
  Future<String?> _detectWorkshopPath(String gamePath, String steamAppId) async {
    try {
      // First, check if user has configured a base Workshop path in settings
      final baseWorkshopPath = await _settingsService.getString(SettingsKeys.workshopPath);
      
      if (baseWorkshopPath.isNotEmpty) {
        // User has configured a base path, append the Steam App ID
        final workshopPath = path.join(baseWorkshopPath, steamAppId);
        
        if (await Directory(workshopPath).exists()) {
          _logger.info('Found Workshop path (from settings): $workshopPath');
          return workshopPath;
        }
        
        _logger.warning('Workshop path from settings does not exist: $workshopPath');
        // Fall through to auto-detection
      }
      
      // Fallback: Auto-detect Workshop path from game installation path
      // Workshop path is typically: Steam/steamapps/workshop/content/[appId]
      // Game path is typically: Steam/steamapps/common/[GameFolder]
      
      // Navigate up from game path to find Steam root
      final gameDir = Directory(gamePath);
      var currentDir = gameDir.parent; // common
      currentDir = currentDir.parent; // steamapps
      final steamRoot = currentDir.parent; // Steam root
      
      final workshopPath = path.join(
        steamRoot.path,
        'steamapps',
        'workshop',
        'content',
        steamAppId,
      );
      
      if (await Directory(workshopPath).exists()) {
        _logger.info('Found Workshop path (auto-detected): $workshopPath');
        return workshopPath;
      }
      
      _logger.warning('Workshop path does not exist: $workshopPath');
      return null;
    } catch (e) {
      _logger.warning('Failed to detect Workshop path: $e');
      return null;
    }
  }

  /// Validate that a game path exists and contains valid game files
  Future<bool> _validateGamePath(String gamePath) async {
    try {
      final gameDir = Directory(gamePath);
      if (!await gameDir.exists()) {
        return false;
      }

      // Check for .exe files (basic validation)
      final exeFiles = await gameDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.exe'))
          .toList();

      return exeFiles.isNotEmpty;
    } catch (e) {
      _logger.warning('Failed to validate game path: $e');
      return false;
    }
  }

  String _getGamePathKey(String gameCode) {
    switch (gameCode) {
      case 'wh3':
        return SettingsKeys.gamePathWh3;
      case 'wh2':
        return SettingsKeys.gamePathWh2;
      case 'wh':
        return SettingsKeys.gamePathWh;
      case 'rome2':
        return SettingsKeys.gamePathRome2;
      case 'attila':
        return SettingsKeys.gamePathAttila;
      case 'troy':
        return SettingsKeys.gamePathTroy;
      case '3k':
        return SettingsKeys.gamePath3k;
      case 'pharaoh':
        return SettingsKeys.gamePathPharaoh;
      default:
        throw ArgumentError('Unknown game code: $gameCode');
    }
  }
}

class _GameInfo {
  final String code;
  final String name;
  final String steamAppId;

  const _GameInfo({
    required this.code,
    required this.name,
    required this.steamAppId,
  });
}

