import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'batch_selection_provider.g.dart';

/// State for batch selection of translation units
class BatchSelectionState {
  final Set<String> selectedUnitIds;
  final bool isSelectionMode;

  const BatchSelectionState({
    this.selectedUnitIds = const {},
    this.isSelectionMode = false,
  });

  BatchSelectionState copyWith({
    Set<String>? selectedUnitIds,
    bool? isSelectionMode,
  }) {
    return BatchSelectionState(
      selectedUnitIds: selectedUnitIds ?? this.selectedUnitIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }

  bool get hasSelection => selectedUnitIds.isNotEmpty;
  int get selectionCount => selectedUnitIds.length;
  bool isSelected(String unitId) => selectedUnitIds.contains(unitId);
}

/// Provider for managing selected translation units
@riverpod
class BatchSelection extends _$BatchSelection {
  @override
  BatchSelectionState build() {
    return const BatchSelectionState();
  }

  /// Toggle selection of a single unit
  void toggleSelection(String unitId) {
    final newSelection = Set<String>.from(state.selectedUnitIds);
    if (newSelection.contains(unitId)) {
      newSelection.remove(unitId);
    } else {
      newSelection.add(unitId);
    }
    state = state.copyWith(
      selectedUnitIds: newSelection,
      isSelectionMode: newSelection.isNotEmpty,
    );
  }

  /// Select a single unit
  void select(String unitId) {
    final newSelection = Set<String>.from(state.selectedUnitIds)..add(unitId);
    state = state.copyWith(
      selectedUnitIds: newSelection,
      isSelectionMode: true,
    );
  }

  /// Deselect a single unit
  void deselect(String unitId) {
    final newSelection = Set<String>.from(state.selectedUnitIds)..remove(unitId);
    state = state.copyWith(
      selectedUnitIds: newSelection,
      isSelectionMode: newSelection.isNotEmpty,
    );
  }

  /// Select multiple units
  void selectMultiple(List<String> unitIds) {
    final newSelection = Set<String>.from(state.selectedUnitIds)..addAll(unitIds);
    state = state.copyWith(
      selectedUnitIds: newSelection,
      isSelectionMode: newSelection.isNotEmpty,
    );
  }

  /// Select all units
  void selectAll(List<String> allUnitIds) {
    state = state.copyWith(
      selectedUnitIds: Set<String>.from(allUnitIds),
      isSelectionMode: true,
    );
  }

  /// Clear all selections
  void clearSelection() {
    state = const BatchSelectionState();
  }

  /// Select range of units (for shift-click)
  void selectRange(List<String> allUnitIds, String fromId, String toId) {
    final fromIndex = allUnitIds.indexOf(fromId);
    final toIndex = allUnitIds.indexOf(toId);

    if (fromIndex == -1 || toIndex == -1) return;

    final startIndex = fromIndex < toIndex ? fromIndex : toIndex;
    final endIndex = fromIndex < toIndex ? toIndex : fromIndex;

    final rangeIds = allUnitIds.sublist(startIndex, endIndex + 1);
    final newSelection = Set<String>.from(state.selectedUnitIds)..addAll(rangeIds);

    state = state.copyWith(
      selectedUnitIds: newSelection,
      isSelectionMode: true,
    );
  }

  /// Invert selection
  void invertSelection(List<String> allUnitIds) {
    final newSelection = Set<String>.from(allUnitIds)
      ..removeAll(state.selectedUnitIds);
    state = state.copyWith(
      selectedUnitIds: newSelection,
      isSelectionMode: newSelection.isNotEmpty,
    );
  }
}
