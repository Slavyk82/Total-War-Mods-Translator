import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'editor_row_models.dart';

part 'editor_filter_notifier.g.dart';

/// Filter state for the translation editor.
///
/// The STATUS and SEVERITY groups are each single-select (nullable): at most
/// one value active per group, independently of each other.
class EditorFilterState {
  final TranslationVersionStatus? statusFilter;
  final Set<TmSourceType> tmSourceFilters;
  final ValidationSeverity? severityFilter;
  final String searchQuery;
  final bool showOnlyWithIssues;

  const EditorFilterState({
    this.statusFilter,
    this.tmSourceFilters = const {},
    this.severityFilter,
    this.searchQuery = '',
    this.showOnlyWithIssues = false,
  });

  bool get hasActiveFilters =>
      statusFilter != null ||
      tmSourceFilters.isNotEmpty ||
      severityFilter != null ||
      searchQuery.isNotEmpty ||
      showOnlyWithIssues;

  EditorFilterState copyWith({
    TranslationVersionStatus? statusFilter,
    bool clearStatusFilter = false,
    Set<TmSourceType>? tmSourceFilters,
    ValidationSeverity? severityFilter,
    bool clearSeverityFilter = false,
    String? searchQuery,
    bool? showOnlyWithIssues,
  }) {
    return EditorFilterState(
      statusFilter:
          clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      tmSourceFilters: tmSourceFilters ?? this.tmSourceFilters,
      severityFilter: clearSeverityFilter
          ? null
          : (severityFilter ?? this.severityFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyWithIssues: showOnlyWithIssues ?? this.showOnlyWithIssues,
    );
  }
}

@riverpod
class EditorFilter extends _$EditorFilter {
  @override
  EditorFilterState build() {
    return const EditorFilterState();
  }

  /// Set the STATUS pill selection. Pass `null` to clear.
  ///
  /// Dropping `needsReview` from status also wipes the severity sub-filter —
  /// severity is only meaningful when status is `needsReview`.
  void setStatusFilter(TranslationVersionStatus? value) {
    final wasNeedsReview =
        state.statusFilter == TranslationVersionStatus.needsReview;
    final dropsNeedsReview =
        wasNeedsReview && value != TranslationVersionStatus.needsReview;
    state = state.copyWith(
      statusFilter: value,
      clearStatusFilter: value == null,
      clearSeverityFilter: dropsNeedsReview,
    );
  }

  void setTmSourceFilters(Set<TmSourceType> filters) {
    state = state.copyWith(tmSourceFilters: filters);
  }

  /// Set the SEVERITY pill selection. Pass `null` to clear.
  void setSeverityFilter(ValidationSeverity? value) {
    state = state.copyWith(
      severityFilter: value,
      clearSeverityFilter: value == null,
    );
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
