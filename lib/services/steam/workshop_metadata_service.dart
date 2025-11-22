import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:uuid/uuid.dart';

/// Service for managing Workshop mod metadata
///
/// Integrates Steam Workshop API with local database storage
class WorkshopMetadataService {
  final IWorkshopApiService _apiService;
  final WorkshopModRepository _repository;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  WorkshopMetadataService({
    required IWorkshopApiService apiService,
    required WorkshopModRepository repository,
  })  : _apiService = apiService,
        _repository = repository;

  /// Fetch and store single mod metadata
  ///
  /// Retrieves mod info from Steam API and saves to database.
  /// Updates existing record if found.
  Future<Result<WorkshopMod, ServiceException>> fetchAndStore({
    required String workshopId,
    required int appId,
  }) async {
    try {
      _logger.info('Fetching metadata for workshop mod: $workshopId');

      // Fetch from API
      final apiResult = await _apiService.getModInfo(
        workshopId: workshopId,
        appId: appId,
      );

      if (apiResult is Err) {
        return Err(ServiceException(
          'Failed to fetch mod info from API',
          error: apiResult.error,
        ));
      }

      final modInfo = apiResult.value;

      // Convert to domain model
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // Check if exists
      final existsResult = await _repository.existsByWorkshopId(workshopId);
      String entityId;

      if (existsResult.isOk && existsResult.value) {
        // Get existing ID
        final existingResult = await _repository.getByWorkshopId(workshopId);
        if (existingResult is Ok) {
          entityId = existingResult.value.id;
        } else {
          entityId = _uuid.v4();
        }
      } else {
        entityId = _uuid.v4();
      }

      final workshopMod = WorkshopMod(
        id: entityId,
        workshopId: modInfo.workshopId,
        title: modInfo.title,
        appId: modInfo.appId,
        workshopUrl: modInfo.workshopUrl,
        fileSize: modInfo.fileSize,
        timeCreated: modInfo.timeCreated,
        timeUpdated: modInfo.timeUpdated,
        subscriptions: modInfo.subscriptions,
        tags: modInfo.tags,
        createdAt: existsResult.isOk && existsResult.value 
            ? (await _repository.getByWorkshopId(workshopId))
                .when(ok: (m) => m.createdAt, err: (_) => now)
            : now,
        updatedAt: now,
        lastCheckedAt: now,
      );

      // Upsert to database
      final upsertResult = await _repository.upsert(workshopMod);

      if (upsertResult is Err) {
        return Err(ServiceException(
          'Failed to save mod metadata to database',
          error: upsertResult.error,
        ));
      }

      _logger.info('Stored metadata for: ${modInfo.title}');
      return Ok(workshopMod);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to fetch and store mod metadata: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Fetch and store multiple mod metadata in batch
  ///
  /// Retrieves info for up to 100 mods and saves to database.
  Future<Result<List<WorkshopMod>, ServiceException>> fetchAndStoreBatch({
    required List<String> workshopIds,
    required int appId,
  }) async {
    try {
      if (workshopIds.isEmpty) {
        return const Ok([]);
      }

      // Enforce API limit
      if (workshopIds.length > 100) {
        return Err(ServiceException(
          'Cannot fetch more than 100 mods at once (got ${workshopIds.length})',
        ));
      }

      _logger.info('Fetching metadata for ${workshopIds.length} mods in batch');

      // Fetch from API
      final apiResult = await _apiService.getMultipleModInfo(
        workshopIds: workshopIds,
        appId: appId,
      );

      if (apiResult is Err) {
        return Err(ServiceException(
          'Failed to fetch batch mod info from API',
          error: apiResult.error,
        ));
      }

      final modInfoList = apiResult.value;
      
      if (modInfoList.isEmpty) {
        return const Ok([]);
      }

      // Check existing mods
      final existingResult = await _repository.getByWorkshopIds(
        modInfoList.map((m) => m.workshopId).toList(),
      );
      
      final existingMap = <String, WorkshopMod>{};
      if (existingResult is Ok) {
        for (final mod in existingResult.value) {
          existingMap[mod.workshopId] = mod;
        }
      }

      // Convert to domain models
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final workshopMods = <WorkshopMod>[];

      for (final modInfo in modInfoList) {
        final existing = existingMap[modInfo.workshopId];
        
        final workshopMod = WorkshopMod(
          id: existing?.id ?? _uuid.v4(),
          workshopId: modInfo.workshopId,
          title: modInfo.title,
          appId: modInfo.appId,
          workshopUrl: modInfo.workshopUrl,
          fileSize: modInfo.fileSize,
          timeCreated: modInfo.timeCreated,
          timeUpdated: modInfo.timeUpdated,
          subscriptions: modInfo.subscriptions,
          tags: modInfo.tags,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          lastCheckedAt: now,
        );

        workshopMods.add(workshopMod);
      }

      // Batch upsert to database
      final upsertResult = await _repository.upsertBatch(workshopMods);

      if (upsertResult is Err) {
        return Err(ServiceException(
          'Failed to save batch mod metadata to database',
          error: upsertResult.error,
        ));
      }

      _logger.info('Stored metadata for ${workshopMods.length} mods');
      return Ok(workshopMods);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to fetch and store batch mod metadata: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Check for updates and update database
  ///
  /// Compares local timestamps with Steam API and updates records.
  /// Returns list of workshop IDs that have updates.
  Future<Result<List<String>, ServiceException>> checkAndUpdateMods({
    required List<String> workshopIds,
    required int appId,
  }) async {
    try {
      if (workshopIds.isEmpty) {
        return const Ok([]);
      }

      _logger.info('Checking updates for ${workshopIds.length} mods');

      // Get local mods
      final localResult = await _repository.getByWorkshopIds(workshopIds);
      
      if (localResult is Err) {
        return Err(ServiceException(
          'Failed to fetch local mod data',
          error: localResult.error,
        ));
      }

      final localMods = localResult.value;
      final timestampMap = <String, int>{};

      for (final mod in localMods) {
        if (mod.timeUpdated != null) {
          timestampMap[mod.workshopId] = mod.timeUpdated!;
        }
      }

      // Check for updates via API
      final updateResult = await _apiService.checkForUpdates(
        modsWithTimestamps: timestampMap,
        appId: appId,
      );

      if (updateResult is Err) {
        return Err(ServiceException(
          'Failed to check for updates',
          error: updateResult.error,
        ));
      }

      final updateMap = updateResult.value;
      final updatedIds = <String>[];

      for (final entry in updateMap.entries) {
        if (entry.value) {
          updatedIds.add(entry.key);
        }
      }

      // Fetch and update mods that have updates
      if (updatedIds.isNotEmpty) {
        _logger.info('Fetching updated metadata for ${updatedIds.length} mods');
        
        final fetchResult = await fetchAndStoreBatch(
          workshopIds: updatedIds,
          appId: appId,
        );

        if (fetchResult is Err) {
          return Err(ServiceException(
            'Failed to fetch updated mod metadata',
            error: fetchResult.error,
          ));
        }
      }

      _logger.info('Found ${updatedIds.length} mods with updates');
      return Ok(updatedIds);
    } catch (e, stackTrace) {
      return Err(ServiceException(
        'Failed to check and update mods: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get mod metadata from database
  Future<Result<WorkshopMod, ServiceException>> getModMetadata({
    required String workshopId,
  }) async {
    final result = await _repository.getByWorkshopId(workshopId);
    
    if (result is Err) {
      return Err(ServiceException(
        'Failed to get mod metadata',
        error: result.error,
      ));
    }

    return Ok(result.value);
  }

  /// Get multiple mods metadata from database
  Future<Result<List<WorkshopMod>, ServiceException>> getMultipleModMetadata({
    required List<String> workshopIds,
  }) async {
    final result = await _repository.getByWorkshopIds(workshopIds);
    
    if (result is Err) {
      return Err(ServiceException(
        'Failed to get multiple mod metadata',
        error: result.error,
      ));
    }

    return Ok(result.value);
  }

  /// Check if mod exists in Steam Workshop
  Future<Result<bool, ServiceException>> modExistsOnSteam({
    required String workshopId,
    required int appId,
  }) async {
    final result = await _apiService.modExists(
      workshopId: workshopId,
      appId: appId,
    );

    if (result is Err) {
      return Err(ServiceException(
        'Failed to check mod existence',
        error: result.error,
      ));
    }

    return Ok(result.value);
  }

  /// Get all mods for specific app from database
  Future<Result<List<WorkshopMod>, ServiceException>> getModsByApp({
    required int appId,
  }) async {
    final result = await _repository.getByAppId(appId);
    
    if (result is Err) {
      return Err(ServiceException(
        'Failed to get mods by app',
        error: result.error,
      ));
    }

    return Ok(result.value);
  }
}

