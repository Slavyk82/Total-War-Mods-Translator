import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for batch project selection mode
class BatchProjectSelectionState {
  final bool isSelectionMode;
  final Set<String> selectedProjectIds;
  final String? selectedLanguageId;

  const BatchProjectSelectionState({
    this.isSelectionMode = false,
    this.selectedProjectIds = const {},
    this.selectedLanguageId,
  });

  BatchProjectSelectionState copyWith({
    bool? isSelectionMode,
    Set<String>? selectedProjectIds,
    String? selectedLanguageId,
    bool clearLanguageId = false,
  }) {
    return BatchProjectSelectionState(
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedProjectIds: selectedProjectIds ?? this.selectedProjectIds,
      selectedLanguageId: clearLanguageId ? null : (selectedLanguageId ?? this.selectedLanguageId),
    );
  }

  /// Check if export can be started
  bool get canExport => selectedProjectIds.isNotEmpty && selectedLanguageId != null;

  /// Number of selected projects
  int get selectedCount => selectedProjectIds.length;
}

/// Notifier for batch project selection
class BatchProjectSelectionNotifier extends Notifier<BatchProjectSelectionState> {
  @override
  BatchProjectSelectionState build() => const BatchProjectSelectionState();

  /// Enter selection mode
  void enterSelectionMode() {
    state = state.copyWith(isSelectionMode: true);
  }

  /// Exit selection mode and clear selections
  void exitSelectionMode() {
    state = const BatchProjectSelectionState();
  }

  /// Toggle a project's selection state
  void toggleProject(String projectId) {
    final newSet = Set<String>.from(state.selectedProjectIds);
    if (newSet.contains(projectId)) {
      newSet.remove(projectId);
    } else {
      newSet.add(projectId);
    }
    state = state.copyWith(selectedProjectIds: newSet);
  }

  /// Select all projects from a list
  void selectAll(List<String> projectIds) {
    state = state.copyWith(
      selectedProjectIds: Set<String>.from(projectIds),
    );
  }

  /// Deselect all projects
  void deselectAll() {
    state = state.copyWith(selectedProjectIds: const {});
  }

  /// Set the target language for export
  void setLanguage(String? languageId) {
    if (languageId == null) {
      state = state.copyWith(clearLanguageId: true);
    } else {
      state = state.copyWith(selectedLanguageId: languageId);
    }
  }
}

/// Provider for batch project selection state
final batchProjectSelectionProvider =
    NotifierProvider<BatchProjectSelectionNotifier, BatchProjectSelectionState>(
  BatchProjectSelectionNotifier.new,
);
