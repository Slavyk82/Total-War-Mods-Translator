import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'editor_selection_notifier.g.dart';

/// Selection state for multi-select operations
class EditorSelectionState {
  final Set<String> selectedUnitIds;

  const EditorSelectionState({
    this.selectedUnitIds = const {},
  });

  bool get hasSelection => selectedUnitIds.isNotEmpty;
  int get selectedCount => selectedUnitIds.length;

  bool isSelected(String unitId) => selectedUnitIds.contains(unitId);

  EditorSelectionState copyWith({
    Set<String>? selectedUnitIds,
  }) {
    return EditorSelectionState(
      selectedUnitIds: selectedUnitIds ?? this.selectedUnitIds,
    );
  }
}

/// Provider for selection state
@riverpod
class EditorSelection extends _$EditorSelection {
  @override
  EditorSelectionState build() {
    return const EditorSelectionState();
  }

  void toggleSelection(String unitId) {
    final selected = Set<String>.from(state.selectedUnitIds);
    if (selected.contains(unitId)) {
      selected.remove(unitId);
    } else {
      selected.add(unitId);
    }
    state = EditorSelectionState(selectedUnitIds: selected);
  }

  void selectAll(List<String> unitIds) {
    state = EditorSelectionState(selectedUnitIds: unitIds.toSet());
  }

  void clearSelection() {
    state = const EditorSelectionState();
  }

  void selectRange(String startId, String endId, List<String> allIds) {
    final startIndex = allIds.indexOf(startId);
    final endIndex = allIds.indexOf(endId);

    if (startIndex == -1 || endIndex == -1) return;

    final start = startIndex < endIndex ? startIndex : endIndex;
    final end = startIndex < endIndex ? endIndex : startIndex;

    final rangeIds = allIds.sublist(start, end + 1).toSet();
    state = EditorSelectionState(selectedUnitIds: rangeIds);
  }
}
