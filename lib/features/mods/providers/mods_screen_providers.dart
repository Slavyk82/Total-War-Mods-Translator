import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/mods/workshop_scanner_service.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/services/shared/logging_service.dart';

part 'mods_screen_providers.g.dart';

/// Provider for the scan log stream from WorkshopScannerService
final scanLogStreamProvider = Provider<Stream<ScanLogMessage>>((ref) {
  final scannerService = ServiceLocator.get<WorkshopScannerService>();
  return scannerService.scanLogStream;
});

/// Session-level cache for scanned mods per game.
/// This cache persists for the lifetime of the app session,
/// preventing automatic rescans when returning to the Mods screen.
@Riverpod(keepAlive: true)
class ModsSessionCache extends _$ModsSessionCache {
  @override
  Map<String, List<DetectedMod>> build() => {};

  /// Check if mods are cached for a specific game
  bool hasCachedMods(String gameCode) => state.containsKey(gameCode);

  /// Get cached mods for a specific game
  List<DetectedMod>? getCachedMods(String gameCode) => state[gameCode];

  /// Cache mods for a specific game
  void cacheMods(String gameCode, List<DetectedMod> mods) {
    state = {...state, gameCode: mods};
  }

  /// Clear cache for a specific game (used when manual refresh is triggered)
  void clearCache(String gameCode) {
    final newState = Map<String, List<DetectedMod>>.from(state);
    newState.remove(gameCode);
    state = newState;
  }

  /// Clear all cache
  void clearAllCache() {
    state = {};
  }

  /// Update a single mod in the cache (used for hide/unhide operations)
  void updateModInCache(String workshopId, bool isHidden) {
    final newState = <String, List<DetectedMod>>{};
    for (final entry in state.entries) {
      final updatedMods = entry.value.map((mod) {
        if (mod.workshopId == workshopId) {
          return mod.copyWith(isHidden: isHidden);
        }
        return mod;
      }).toList();
      newState[entry.key] = updatedMods;
    }
    state = newState;
  }

  /// Mark a mod as imported in the cache (used after project creation)
  void updateModImportedInCache(String workshopId, String projectId) {
    final newState = <String, List<DetectedMod>>{};
    for (final entry in state.entries) {
      final updatedMods = entry.value.map((mod) {
        if (mod.workshopId == workshopId) {
          return mod.copyWith(
            isAlreadyImported: true,
            existingProjectId: projectId,
          );
        }
        return mod;
      }).toList();
      newState[entry.key] = updatedMods;
    }
    state = newState;
  }
}

/// Filter options for mods list
enum ModsFilter {
  all,
  notImported,
  needsUpdate,
}

/// Filter state for mods screen
@riverpod
class ModsFilterState extends _$ModsFilterState {
  @override
  ModsFilter build() => ModsFilter.all;

  void setFilter(ModsFilter filter) {
    state = filter;
  }
}

/// Search query state for mods screen
@riverpod
class ModsSearchQuery extends _$ModsSearchQuery {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

/// Show hidden mods filter state
@riverpod
class ShowHiddenMods extends _$ShowHiddenMods {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
  }

  void set(bool value) {
    state = value;
  }
}

/// Filtered mods based on search query, filter, and hidden state
/// Uses cached data for instant filtering without waiting for async resolution
@riverpod
List<DetectedMod> filteredMods(Ref ref) {
  LoggingService.instance.debug('filteredMods provider computing');
  // Watch the async state - use cached value for instant filtering
  final detectedModsAsync = ref.watch(detectedModsProvider);
  final searchQuery = ref.watch(modsSearchQueryProvider).toLowerCase();
  final filter = ref.watch(modsFilterStateProvider);
  final showHidden = ref.watch(showHiddenModsProvider);
  LoggingService.instance.debug('showHidden value: $showHidden');

  // Use cached data or empty list if not yet loaded
  final detectedModsList = detectedModsAsync.value ?? <DetectedMod>[];
  LoggingService.instance.debug('detectedModsList count: ${detectedModsList.length}, hasValue: ${detectedModsAsync.hasValue}');
  var result = detectedModsList;

  // Apply hidden filter first
  // If showHidden is true, show only hidden mods
  // If showHidden is false, show only non-hidden mods
  result = result.where((mod) => mod.isHidden == showHidden).toList();

  // Apply status filter
  switch (filter) {
    case ModsFilter.all:
      // No filtering
      break;
    case ModsFilter.notImported:
      result = result.where((mod) => !mod.isAlreadyImported).toList();
      break;
    case ModsFilter.needsUpdate:
      result = result.where((mod) => 
        mod.updateStatus == ModUpdateStatus.needsDownload ||
        mod.updateStatus == ModUpdateStatus.hasChanges
      ).toList();
      break;
  }

  // Apply search
  if (searchQuery.isNotEmpty) {
    result = result.where((mod) {
      // Search by name
      if (mod.name.toLowerCase().contains(searchQuery)) {
        return true;
      }

      // Search by Steam Workshop ID
      if (mod.workshopId.toLowerCase().contains(searchQuery)) {
        return true;
      }

      return false;
    }).toList();
  }

  return result;
}

/// Provider to check if mods are still loading (for UI feedback)
@riverpod
bool modsIsLoading(Ref ref) {
  final detectedModsAsync = ref.watch(detectedModsProvider);
  return detectedModsAsync.isLoading && !detectedModsAsync.hasValue;
}

/// Provider to check if mods have error (for UI feedback)
@riverpod
Object? modsError(Ref ref) {
  final detectedModsAsync = ref.watch(detectedModsProvider);
  return detectedModsAsync.hasError && !detectedModsAsync.hasValue
      ? detectedModsAsync.error
      : null;
}

/// Provider for total mods count (excluding hidden)
@riverpod
Future<int> totalModsCount(Ref ref) async {
  final detectedModsList = await ref.watch(detectedModsProvider.future);
  final showHidden = ref.watch(showHiddenModsProvider);
  return detectedModsList.where((mod) => mod.isHidden == showHidden).length;
}

/// Provider for hidden mods count
@riverpod
Future<int> hiddenModsCount(Ref ref) async {
  final detectedModsList = await ref.watch(detectedModsProvider.future);
  return detectedModsList.where((mod) => mod.isHidden).length;
}

/// Provider for not imported mods count (respects hidden filter)
@riverpod
Future<int> notImportedModsCount(Ref ref) async {
  final detectedModsList = await ref.watch(detectedModsProvider.future);
  final showHidden = ref.watch(showHiddenModsProvider);
  return detectedModsList
      .where((mod) => mod.isHidden == showHidden && !mod.isAlreadyImported)
      .length;
}

/// Provider for mods needing update count (respects hidden filter)
@riverpod
Future<int> needsUpdateModsCount(Ref ref) async {
  final detectedModsList = await ref.watch(detectedModsProvider.future);
  final showHidden = ref.watch(showHiddenModsProvider);
  return detectedModsList.where((mod) =>
    mod.isHidden == showHidden &&
    (mod.updateStatus == ModUpdateStatus.needsDownload ||
     mod.updateStatus == ModUpdateStatus.hasChanges)
  ).length;
}

/// Provider for count of projects with pending changes OR mod update impact.
/// Counts projects that either:
/// 1. Have the hasModUpdateImpact flag set (mod update was applied)
/// 2. Have pending analysis changes (for backwards compatibility)
@riverpod
Future<int> projectsWithPendingChangesCount(Ref ref) async {
  // Watch the detected mods to refresh when mods are scanned
  ref.watch(detectedModsProvider);

  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final workshopModRepo = ServiceLocator.get<WorkshopModRepository>();
  final cacheRepo = ServiceLocator.get<ModUpdateAnalysisCacheRepository>();

  final projectsResult = await projectRepo.getAll();
  if (projectsResult.isErr) return 0;

  final projects = projectsResult.unwrap();
  int pendingCount = 0;

  for (final project in projects) {
    // Count projects with mod update impact flag first
    if (project.hasModUpdateImpact) {
      pendingCount++;
      continue;  // Don't double-count
    }

    // Also check for pending analysis changes (backwards compatibility)
    if (project.sourceFilePath == null || project.modSteamId == null) continue;

    // Get Steam Workshop timestamp from cache
    int? steamTimestamp;
    final workshopModResult = await workshopModRepo.getByWorkshopId(project.modSteamId!);
    if (workshopModResult.isOk) {
      steamTimestamp = workshopModResult.unwrap().timeUpdated;
    }

    // Get local file timestamp
    int? localTimestamp;
    final sourceFile = File(project.sourceFilePath!);
    if (await sourceFile.exists()) {
      final stat = await sourceFile.stat();
      localTimestamp = stat.modified.millisecondsSinceEpoch ~/ 1000;
    }

    // Only count if Steam version is newer than local file (same logic as Projects screen)
    if (steamTimestamp != null && localTimestamp != null && steamTimestamp > localTimestamp) {
      // Check cache for pending changes (excludes auto-applied removals)
      final cacheResult = await cacheRepo.getByProjectAndPath(project.id, project.sourceFilePath!);
      if (cacheResult.isOk) {
        final cache = cacheResult.unwrap();
        if (cache != null && cache.hasPendingChanges) {
          pendingCount++;
        }
      }
    }
  }

  return pendingCount;
}

/// Refresh trigger for mods list
@riverpod
class ModsRefreshTrigger extends _$ModsRefreshTrigger {
  @override
  int build() => 0;

  Future<void> refresh() async {
    state++;
    // Clear the session cache for the current game to force a rescan
    final selectedGame = await ref.read(selectedGameProvider.future);
    if (selectedGame != null) {
      ref.read(modsSessionCacheProvider.notifier).clearCache(selectedGame.code);
    }
    // Invalidate the detected mods provider to force a refresh
    ref.invalidate(detectedModsProvider);
  }
}

/// Loading state for mods screen
@riverpod
class ModsLoadingState extends _$ModsLoadingState {
  @override
  bool build() => false;

  void setLoading(bool loading) {
    state = loading;
  }
}

/// Toggle mod hidden status
@Riverpod(keepAlive: true)
class ModHiddenToggle extends _$ModHiddenToggle {
  @override
  Future<void> build() async {}

  /// Toggle the hidden status of a mod
  Future<void> toggleHidden(String workshopId, bool isHidden) async {
    LoggingService.instance.debug('toggleHidden called: workshopId=$workshopId, isHidden=$isHidden');
    final workshopModRepo = ServiceLocator.get<WorkshopModRepository>();
    await workshopModRepo.setHidden(workshopId, isHidden);
    LoggingService.instance.debug('DB updated');

    // Update the mod list locally without rescanning
    // Use try-catch to handle potential provider disposal during async operation
    try {
      LoggingService.instance.debug('Calling updateModHidden');
      ref.read(detectedModsProvider.notifier).updateModHidden(workshopId, isHidden);
      LoggingService.instance.debug('updateModHidden completed');
    } catch (e) {
      LoggingService.instance.error('ERROR in updateModHidden', e);
      // Provider was disposed during async operation - state will refresh on next access
    }
  }
}
