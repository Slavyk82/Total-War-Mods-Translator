import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';
import 'package:twmt/services/steam/models/workshop_mod_info.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Processes Steam Workshop mod data: fetching from API and persisting to database.
///
/// Handles batch fetching of mod information from Steam API with proper
/// deduplication and change detection before database updates.
class WorkshopModProcessor {
  final WorkshopModRepository _workshopModRepository;
  final IWorkshopApiService _workshopApiService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  /// Maximum number of mods to fetch in a single Steam API batch request.
  static const int steamApiBatchSize = 100;

  WorkshopModProcessor({
    required WorkshopModRepository workshopModRepository,
    required IWorkshopApiService workshopApiService,
  })  : _workshopModRepository = workshopModRepository,
        _workshopApiService = workshopApiService;

  /// Fetch and process mod data from Steam Workshop API.
  ///
  /// [workshopIds] - List of Workshop IDs to fetch
  /// [appId] - Steam App ID for the game
  ///
  /// Returns a map of workshopId -> WorkshopMod for successfully processed mods.
  Future<Map<String, WorkshopMod>> fetchAndProcessMods({
    required List<String> workshopIds,
    required int appId,
  }) async {
    final workshopModsMap = <String, WorkshopMod>{};

    if (workshopIds.isEmpty) {
      return workshopModsMap;
    }

    // Process in batches (Steam API limit)
    for (int i = 0; i < workshopIds.length; i += steamApiBatchSize) {
      final batchEnd = (i + steamApiBatchSize < workshopIds.length)
          ? i + steamApiBatchSize
          : workshopIds.length;
      final batch = workshopIds.sublist(i, batchEnd);

      final batchResult = await _processBatch(batch, appId);
      workshopModsMap.addAll(batchResult);
    }

    return workshopModsMap;
  }

  /// Process a single batch of workshop IDs.
  Future<Map<String, WorkshopMod>> _processBatch(
    List<String> workshopIds,
    int appId,
  ) async {
    final result = <String, WorkshopMod>{};

    final modInfosResult = await _workshopApiService.getMultipleModInfo(
      workshopIds: workshopIds,
      appId: appId,
    );

    if (modInfosResult is Err) {
      final error = modInfosResult.error;
      _logger.warning('Steam API batch failed: ${error.message}');
      return result;
    }

    final modInfos = modInfosResult.value;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final modInfo in modInfos) {
      final workshopMod = await _processModInfo(modInfo, appId, now);
      if (workshopMod != null) {
        result[modInfo.workshopId] = workshopMod;
      }
    }

    return result;
  }

  /// Process a single mod info and update database if needed.
  Future<WorkshopMod?> _processModInfo(
    WorkshopModInfo modInfo,
    int appId,
    int now,
  ) async {
    // Check if mod already exists
    final existingModResult =
        await _workshopModRepository.getByWorkshopId(modInfo.workshopId);

    final bool isNewMod;
    final String modId;
    final int createdAt;
    final bool hasChanges;

    WorkshopMod? existingMod;
    if (existingModResult is Ok) {
      // Mod exists, check if data has changed
      existingMod = existingModResult.value;
      modId = existingMod.id;
      createdAt = existingMod.createdAt;
      isNewMod = false;

      // Compare relevant fields (excluding internal timestamps)
      hasChanges = existingMod.title != modInfo.title ||
          existingMod.workshopUrl != modInfo.workshopUrl ||
          existingMod.fileSize != modInfo.fileSize ||
          existingMod.timeCreated != modInfo.timeCreated ||
          existingMod.timeUpdated != modInfo.timeUpdated ||
          existingMod.subscriptions != modInfo.subscriptions ||
          !_tagsEqual(existingMod.tags, modInfo.tags);
    } else {
      // New mod, generate new ID
      modId = _uuid.v4();
      createdAt = now;
      isNewMod = true;
      hasChanges = true;
    }

    final workshopMod = WorkshopMod(
      id: modId,
      workshopId: modInfo.workshopId,
      title: modInfo.title,
      appId: appId,
      workshopUrl: modInfo.workshopUrl,
      fileSize: modInfo.fileSize,
      timeCreated: modInfo.timeCreated,
      timeUpdated: modInfo.timeUpdated,
      subscriptions: modInfo.subscriptions,
      tags: modInfo.tags,
      createdAt: createdAt,
      updatedAt: hasChanges ? now : (existingMod?.updatedAt ?? now),
      lastCheckedAt: now,
      isHidden: existingMod?.isHidden ?? false,
    );

    // Only upsert if it's a new mod or if data has changed
    if (isNewMod || hasChanges) {
      final result = await _workshopModRepository.upsert(workshopMod);
      result.when(
        ok: (_) {},
        err: (error) =>
            _logger.error('Failed to save mod ${modInfo.workshopId}: ${error.message}'),
      );
    } else {
      // Only update lastCheckedAt without changing updatedAt
      final result = await _workshopModRepository.updateLastChecked(modInfo.workshopId, now);
      result.when(
        ok: (_) {},
        err: (error) => _logger.warning(
            'Failed to update lastCheckedAt for mod ${modInfo.workshopId}: ${error.message}'),
      );
    }

    return workshopMod;
  }

  /// Compare two tag lists for equality.
  bool _tagsEqual(List<String>? tags1, List<String>? tags2) {
    if (tags1 == null && tags2 == null) return true;
    if (tags1 == null || tags2 == null) return false;
    if (tags1.length != tags2.length) return false;

    final sorted1 = List<String>.from(tags1)..sort();
    final sorted2 = List<String>.from(tags2)..sort();
    return sorted1.join(',') == sorted2.join(',');
  }
}
