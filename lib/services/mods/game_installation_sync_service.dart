import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/steam/models/game_definitions.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';

/// Service to sync game settings with game_installations table
class GameInstallationSyncService {
  final GameInstallationRepository _gameInstallationRepository;
  final SettingsService _settingsService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  GameInstallationSyncService({
    required GameInstallationRepository gameInstallationRepository,
    required SettingsService settingsService,
  })  : _gameInstallationRepository = gameInstallationRepository,
        _settingsService = settingsService;

  /// Sync all configured games from settings to database
  Future<Result<void, ServiceException>> syncAllGames() async {
    try {
      for (final entry in supportedGames.entries) {
        final gameCode = entry.key;
        final gameInfo = entry.value;

        await _syncGame(gameCode, gameInfo);
      }

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
    final gameInfo = supportedGames[gameCode];
    if (gameInfo == null) {
      return Err(ServiceException('Unknown game code: $gameCode'));
    }

    return await _syncGame(gameCode, gameInfo);
  }

  Future<Result<void, ServiceException>> _syncGame(
    String gameCode,
    GameInfo gameInfo,
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
        
        // Also check if steamAppId is missing (from older database versions)
        final steamAppIdMissing = existing.steamAppId == null ||
                                  existing.steamAppId!.isEmpty;

        if (installPathChanged || workshopPathMissing || steamAppIdMissing) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

          // Only detect Workshop path if it's missing
          // If installation path changes, keep existing Workshop path
          String? workshopPath = existing.steamWorkshopPath;
          if (workshopPathMissing) {
            workshopPath = await _detectWorkshopPath(gamePath, gameInfo.steamAppId);
          }

          final updated = existing.copyWith(
            installationPath: gamePath,
            steamWorkshopPath: workshopPath,
            steamAppId: gameInfo.steamAppId,
            updatedAt: now,
          );

          final updateResult = await _gameInstallationRepository.update(updated);
          if (updateResult is Err) {
            return Err(ServiceException(
              'Failed to update game installation: ${updateResult.error.message}',
              error: updateResult.error,
            ));
          }
        }
      } else {
        // Game installation doesn't exist, create it
        
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
          return workshopPath;
        }
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
        return workshopPath;
      }
      
      return null;
    } catch (e) {
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
      case 'pharaoh_dynasties':
        return SettingsKeys.gamePathPharaohDynasties;
      default:
        throw ArgumentError('Unknown game code: $gameCode');
    }
  }
}

