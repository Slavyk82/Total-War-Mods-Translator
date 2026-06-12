import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/search/i_search_service.dart';
import 'package:twmt/services/search/models/search_result.dart';
import 'package:twmt/services/search/models/search_exceptions.dart';
import '../../../providers/shared/service_providers.dart';
import '../models/search_query_model.dart';

part 'search_providers.g.dart';

/// Current search query state
@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  SearchQueryModel build() => SearchQueryModel.empty();

  /// Update search text
  void updateText(String text) {
    state = state.copyWith(text: text);
  }

  /// Update search scope
  void updateScope(SearchScope scope) {
    state = state.copyWith(scope: scope);
  }

  /// Update search operator
  void updateOperator(SearchOperator operator) {
    state = state.copyWith(operator: operator);
  }

  /// Update search filter
  void updateFilter(SearchFilter? filter) {
    state = state.copyWith(filter: filter);
  }

  /// Update search options
  void updateOptions(SearchOptions options) {
    state = state.copyWith(options: options);
  }

  /// Clear query
  void clear() {
    state = SearchQueryModel.empty();
  }
}

/// Execute search and get results
@riverpod
Future<SearchResultsModel> searchResults(
  Ref ref, {
  int page = 1,
}) async {
  final query = ref.watch(searchQueryProvider);

  // Return empty if query is invalid
  if (!query.isValid) {
    return SearchResultsModel.empty();
  }

  final service = ref.watch(searchServiceProvider);
  final pageSize = query.options.resultsPerPage;
  final offset = (page - 1) * pageSize;

  try {
    // Choose search method based on scope and options
    final result = await _executeSearch(
      service: service,
      query: query,
      limit: pageSize,
      offset: offset,
    );

    return result.when(
      ok: (windowResults) {
        // `_executeSearch` returns the rows of the CURRENT page plus at most
        // ONE sentinel row (it requests pageSize + 1). The sentinel makes the
        // next-page signal exact for every scope without a COUNT(*) API:
        //   - sentinel present -> at least one more page exists; encode that
        //     as totalCount = offset + pageSize + 1 so `hasNextPage` is true
        //     (the exact total is unknown, only "there is more");
        //   - sentinel absent  -> this is the last page and
        //     offset + results.length is the EXACT total, so `totalPages`,
        //     `hasNextPage` and `rangeText` are all correct.
        final hasMore = windowResults.length > pageSize;
        final results =
            hasMore ? windowResults.sublist(0, pageSize) : windowResults;
        final totalCount = offset + results.length + (hasMore ? 1 : 0);

        return SearchResultsModel(
          results: results,
          totalCount: totalCount,
          currentPage: page,
          pageSize: pageSize,
          query: query,
        );
      },
      err: (error) => throw error,
    );
  } catch (e) {
    // Return empty results on error
    return SearchResultsModel(
      results: const [],
      totalCount: 0,
      currentPage: page,
      pageSize: pageSize,
      query: query,
    );
  }
}

/// Helper to execute appropriate search method.
///
/// Contract: returns the rows of the page window starting at [offset], PLUS
/// at most one sentinel row beyond it (it requests `limit + 1` rows). The
/// caller uses the sentinel to decide `hasNextPage` exactly, then trims the
/// list back to [limit] rows for display.
///
/// `searchAll` accepts no `offset` on `ISearchService`, so for that scope the
/// whole window `offset + limit + 1` is fetched from the start and sliced
/// here. This is correct because the service's merged ordering is
/// deterministic (stable tiebreakers), so a fetch is always a stable prefix
/// of a deeper fetch.
Future<Result<List<SearchResult>, SearchServiceException>> _executeSearch({
  required ISearchService service,
  required SearchQueryModel query,
  required int limit,
  required int offset,
}) async {
  // One extra row beyond the page: its presence proves a next page exists.
  final sentinelLimit = limit + 1;

  // Build FTS5 query
  String ftsQuery = query.text;
  if (query.options.phraseSearch) {
    ftsQuery = '"$ftsQuery"';
  }
  if (query.options.prefixSearch) {
    ftsQuery = '$ftsQuery*';
  }

  // Choose search method based on scope
  switch (query.scope) {
    case SearchScope.source:
    case SearchScope.key:
      return service.searchTranslationUnits(
        ftsQuery,
        filter: query.filter,
        limit: sentinelLimit,
        offset: offset,
      );

    case SearchScope.target:
      return service.searchTranslationVersions(
        ftsQuery,
        filter: query.filter,
        limit: sentinelLimit,
        offset: offset,
      );

    case SearchScope.both:
    case SearchScope.all:
      final result = await service.searchAll(
        ftsQuery,
        filter: query.filter,
        limit: offset + sentinelLimit,
      );
      if (result.isErr) return result;
      return Ok(result.value.skip(offset).toList());
  }
}
