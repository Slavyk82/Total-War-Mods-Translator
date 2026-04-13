import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'editor_row_models.dart';

part 'editor_filter_notifier.g.dart';

/// Filter state for the translation editor
class EditorFilterState {
  final Set<TranslationVersionStatus> statusFilters;
  final Set<TmSourceType> tmSourceFilters;
  final String searchQuery;
  final bool showOnlyWithIssues;

  const EditorFilterState({
    this.statusFilters = const {},
    this.tmSourceFilters = const {},
    this.searchQuery = '',
    this.showOnlyWithIssues = false,
  });

  bool get hasActiveFilters =>
    statusFilters.isNotEmpty ||
    tmSourceFilters.isNotEmpty ||
    searchQuery.isNotEmpty ||
    showOnlyWithIssues;

  EditorFilterState copyWith({
    Set<TranslationVersionStatus>? statusFilters,
    Set<TmSourceType>? tmSourceFilters,
    String? searchQuery,
    bool? showOnlyWithIssues,
  }) {
    return EditorFilterState(
      statusFilters: statusFilters ?? this.statusFilters,
      tmSourceFilters: tmSourceFilters ?? this.tmSourceFilters,
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
    state = state.copyWith(statusFilters: filters);
  }

  void setTmSourceFilters(Set<TmSourceType> filters) {
    state = state.copyWith(tmSourceFilters: filters);
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
