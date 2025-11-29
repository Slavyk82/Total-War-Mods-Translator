import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/service_locator.dart';

part 'mods_screen_providers.g.dart';

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
@riverpod
Future<List<DetectedMod>> filteredMods(Ref ref) async {
  final detectedModsList = await ref.watch(detectedModsProvider.future);
  final searchQuery = ref.watch(modsSearchQueryProvider).toLowerCase();
  final filter = ref.watch(modsFilterStateProvider);
  final showHidden = ref.watch(showHiddenModsProvider);

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

/// Refresh trigger for mods list
@riverpod
class ModsRefreshTrigger extends _$ModsRefreshTrigger {
  @override
  int build() => 0;

  void refresh() {
    state++;
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
@riverpod
class ModHiddenToggle extends _$ModHiddenToggle {
  @override
  Future<void> build() async {}

  /// Toggle the hidden status of a mod
  Future<void> toggleHidden(String workshopId, bool isHidden) async {
    final workshopModRepo = ServiceLocator.get<WorkshopModRepository>();
    await workshopModRepo.setHidden(workshopId, isHidden);
  }
}
