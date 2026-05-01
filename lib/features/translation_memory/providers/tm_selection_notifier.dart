import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tm_selection_notifier.g.dart';

/// Selection state for the Translation Memory browser grid.
///
/// Mirrors the editor's selection notifier but stays purposefully simpler:
/// no shift/ctrl range semantics — a TM selection is just the set of entry
/// ids whose checkbox is currently ticked.
@riverpod
class TmSelection extends _$TmSelection {
  @override
  Set<String> build() => const <String>{};

  bool isSelected(String entryId) => state.contains(entryId);

  void toggle(String entryId) {
    final next = Set<String>.from(state);
    if (next.contains(entryId)) {
      next.remove(entryId);
    } else {
      next.add(entryId);
    }
    state = next;
  }

  void selectAll(Iterable<String> ids) {
    state = ids.toSet();
  }

  void clear() {
    if (state.isEmpty) return;
    state = const <String>{};
  }

  /// Drop any ids that are no longer present in [visibleIds]. Called after a
  /// fetch lands so deleted entries don't keep haunting the selection.
  void retain(Iterable<String> visibleIds) {
    final visible = visibleIds.toSet();
    final next = state.where(visible.contains).toSet();
    if (next.length == state.length) return;
    state = next;
  }
}
