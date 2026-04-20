import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'editor_row_models.dart';

part 'editor_filter_notifier.g.dart';

/// Filter state for the translation editor
class EditorFilterState {
  final Set<TranslationVersionStatus> statusFilters;
  final Set<TmSourceType> tmSourceFilters;
  final Set<ValidationSeverity> severityFilters;
  final String searchQuery;
  final bool showOnlyWithIssues;

  const EditorFilterState({
    this.statusFilters = const {},
    this.tmSourceFilters = const {},
    this.severityFilters = const {},
    this.searchQuery = '',
    this.showOnlyWithIssues = false,
  });

  bool get hasActiveFilters =>
    statusFilters.isNotEmpty ||
    tmSourceFilters.isNotEmpty ||
    severityFilters.isNotEmpty ||
    searchQuery.isNotEmpty ||
    showOnlyWithIssues;

  EditorFilterState copyWith({
    Set<TranslationVersionStatus>? statusFilters,
    Set<TmSourceType>? tmSourceFilters,
    Set<ValidationSeverity>? severityFilters,
    String? searchQuery,
    bool? showOnlyWithIssues,
  }) {
    return EditorFilterState(
      statusFilters: statusFilters ?? this.statusFilters,
      tmSourceFilters: tmSourceFilters ?? this.tmSourceFilters,
      severityFilters: severityFilters ?? this.severityFilters,
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyWithIssues: showOnlyWithIssues ?? this.showOnlyWithIssues,
    );
  }
}

/// Provider for filter state
@riverpod
class EditorFilter extends _$EditorFilter {
  @override
  EditorFilterState build() {
    return const EditorFilterState();
  }

  void setStatusFilters(Set<TranslationVersionStatus> filters) {
    // Dropping needsReview from the status set also wipes the severity
    // sub-filter — severity is only meaningful under needsReview.
    final droppingNeedsReview = state.statusFilters
            .contains(TranslationVersionStatus.needsReview) &&
        !filters.contains(TranslationVersionStatus.needsReview);
    state = state.copyWith(
      statusFilters: filters,
      severityFilters: droppingNeedsReview ? const {} : state.severityFilters,
    );
  }

  void setTmSourceFilters(Set<TmSourceType> filters) {
    state = state.copyWith(tmSourceFilters: filters);
  }

  void setSeverityFilters(Set<ValidationSeverity> filters) {
    state = state.copyWith(severityFilters: filters);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setShowOnlyWithIssues(bool show) {
    state = state.copyWith(showOnlyWithIssues: show);
  }

  void clearFilters() {
    state = const EditorFilterState();
  }
}
