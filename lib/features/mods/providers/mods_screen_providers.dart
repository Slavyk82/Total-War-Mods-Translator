import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';

part 'mods_screen_providers.g.dart';

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

/// Filtered mods based on search query
@riverpod
Future<List<DetectedMod>> filteredMods(Ref ref) async {
  final detectedModsList = await ref.watch(detectedModsProvider.future);
  final searchQuery = ref.watch(modsSearchQueryProvider).toLowerCase();

  if (searchQuery.isEmpty) {
    return detectedModsList;
  }

  return detectedModsList.where((mod) {
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
