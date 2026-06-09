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

  /// Load query from saved search
  void loadFromSavedSearch(SavedSearch savedSearch) {
    state = SearchQueryModel(
      text: savedSearch.query,
      scope: SearchScope.all, // Default, would need to be stored in filter
      operator: SearchOperator.and, // Default
      filter: savedSearch.filter,
      options: SearchOptions.defaults(),
    );
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
      ok: (results) {
        // The underlying search service returns only the CURRENT page (it has
        // no separate COUNT(*) API, and `searchAll`/`searchWithRegex` do not
        // even accept an offset). Using `results.length` as the total made
        // `totalPages`/`hasNextPage` wrong: a full page of `pageSize` results
        // collapsed to `totalPages == 1` and `hasNextPage == false`, silently
        // killing pagination beyond page 1.
        //
        // Without a real total we use the standard "fetch a full page => assume
        // there is at least one more page" heuristic so navigation works:
        //   - rows already skipped on previous pages: `offset`
        //   - rows on this page: `results.length`
        //   - if this page is full, signal one more page exists (+1)
        // This keeps `hasNextPage`, `hasPreviousPage` and `rangeText` coherent.
        // (When a true COUNT API is added, pass that value here instead.)
        final pageIsFull = results.length >= pageSize;
        final totalCount = offset + results.length + (pageIsFull ? 1 : 0);

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

/// Helper to execute appropriate search method
Future<Result<List<SearchResult>, SearchServiceException>> _executeSearch({
  required ISearchService service,
  required SearchQueryModel query,
  required int limit,
  required int offset,
}) async {
  // Use regex if enabled.
  //
  // NOTE: `searchWithRegex` (and `searchAll` below) do not accept an `offset`,
  // so true pagination is not possible for these scopes — only the first
  // `limit` rows are ever returned. The provider's `totalCount` heuristic keeps
  // the UI coherent for page 1. Threading a real offset would require widening
  // the `ISearchService` interface (out of scope for this fix). Also note that
  // for a *true* regex (regex metacharacters), the service throws
  // `UnsupportedError`; the caller catches it and returns empty results.
  if (query.options.useRegex) {
    final searchIn = _getScopeForRegex(query.scope);
    return service.searchWithRegex(
      query.text,
      searchIn: searchIn,
      filter: query.filter,
      limit: limit,
    );
  }

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
        limit: limit,
        offset: offset,
      );

    case SearchScope.target:
      return service.searchTranslationVersions(
        ftsQuery,
        filter: query.filter,
        limit: limit,
        offset: offset,
      );

    case SearchScope.both:
    case SearchScope.all:
      return service.searchAll(
        ftsQuery,
        filter: query.filter,
        limit: limit,
      );
  }
}

/// Convert SearchScope to regex searchIn parameter
String _getScopeForRegex(SearchScope scope) {
  switch (scope) {
    case SearchScope.source:
    case SearchScope.key:
      return 'source';
    case SearchScope.target:
      return 'target';
    case SearchScope.both:
    case SearchScope.all:
      return 'both';
  }
}

/// Search history (last 50 searches)
@riverpod
Future<List<Map<String, dynamic>>> searchHistory(Ref ref) async {
  final service = ref.watch(searchServiceProvider);
  final result = await service.getSearchHistory(limit: 50);

  return result.when(
    ok: (history) => history,
    err: (error) => [],
  );
}

/// Saved searches list
@riverpod
Future<List<SavedSearch>> savedSearches(Ref ref) async {
  final service = ref.watch(searchServiceProvider);
  final result = await service.getSavedSearches();

  return result.when(
    ok: (searches) => searches,
    err: (error) => [],
  );
}

/// Save a search
@riverpod
class SaveSearchAction extends _$SaveSearchAction {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> save(String name, SearchQueryModel query) async {
    state = const AsyncValue.loading();

    try {
      final service = ref.read(searchServiceProvider);
      final result = await service.saveSearch(
        name,
        query.text,
        filter: query.filter,
      );

      result.when(
        ok: (_) {
          if (ref.mounted) {
            state = const AsyncValue.data(null);
            // Refresh saved searches list
            ref.invalidate(savedSearchesProvider);
          }
        },
        err: (error) {
          if (ref.mounted) {
            state = AsyncValue.error(error, StackTrace.current);
          }
        },
      );
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// Delete a saved search
@riverpod
class DeleteSearchAction extends _$DeleteSearchAction {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> delete(String searchId) async {
    state = const AsyncValue.loading();

    try {
      final service = ref.read(searchServiceProvider);
      final result = await service.deleteSavedSearch(searchId);

      result.when(
        ok: (_) {
          if (ref.mounted) {
            state = const AsyncValue.data(null);
            // Refresh saved searches list
            ref.invalidate(savedSearchesProvider);
          }
        },
        err: (error) {
          if (ref.mounted) {
            state = AsyncValue.error(error, StackTrace.current);
          }
        },
      );
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// Execute a saved search
@riverpod
class ExecuteSavedSearchAction extends _$ExecuteSavedSearchAction {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> execute(SavedSearch search) async {
    state = const AsyncValue.loading();

    try {
      final service = ref.read(searchServiceProvider);

      // Increment usage count
      await service.incrementSavedSearchUsage(search.id);

      if (ref.mounted) {
        // Load search query into search query provider
        final queryNotifier = ref.read(searchQueryProvider.notifier);
        queryNotifier.loadFromSavedSearch(search);

        // Refresh search results
        ref.invalidate(searchResultsProvider);

        // Refresh saved searches to update usage count
        ref.invalidate(savedSearchesProvider);

        state = const AsyncValue.data(null);
      }
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// Clear search history
@riverpod
class ClearHistoryAction extends _$ClearHistoryAction {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> clear() async {
    state = const AsyncValue.loading();

    try {
      final service = ref.read(searchServiceProvider);
      final result = await service.clearSearchHistory();

      result.when(
        ok: (_) {
          if (ref.mounted) {
            state = const AsyncValue.data(null);
            // Refresh search history
            ref.invalidate(searchHistoryProvider);
          }
        },
        err: (error) {
          if (ref.mounted) {
            state = AsyncValue.error(error, StackTrace.current);
          }
        },
      );
    } catch (e, st) {
      if (ref.mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}
