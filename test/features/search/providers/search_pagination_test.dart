import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/search/models/search_query_model.dart';
import 'package:twmt/features/search/providers/search_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/search/i_search_service.dart';
import 'package:twmt/services/search/models/search_exceptions.dart';
import 'package:twmt/services/search/models/search_result.dart';

/// Regression tests for search pagination in the provider layer (audit
/// finding F4).
///
/// The provider used `results.length >= pageSize` on a plain page-sized
/// fetch to guess whether a next page exists. That heuristic is wrong in
/// both directions:
///   - exactly pageSize total matches => claimed a phantom next page;
///   - `searchAll` accepts no offset, so page 2 simply re-fetched (a subset
///     of) page 1 — duplicated results, and with the old `limit ~/ 3` split
///     a full page could never even be reached.
///
/// The fixed provider requests one sentinel row beyond the page window
/// (pageSize + 1) and slices the window itself for the offset-less
/// interface methods, so `hasNextPage` is exact for every scope.
void main() {
  SearchResult result(int i, int total) => SearchResult(
        id: 'r-$i',
        type: SearchResultType.translationUnit,
        matchedField: 'source_text',
        highlightedText: 'match $i',
        // Strictly decreasing so r-0 is globally the most relevant.
        relevanceScore: (total - i).toDouble(),
      );

  ProviderContainer makeContainer(ISearchService fake) {
    final container = ProviderContainer(overrides: [
      searchServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<SearchResultsModel> runSearch(
    ProviderContainer container, {
    required int page,
  }) async {
    final notifier = container.read(searchQueryProvider.notifier);
    notifier.updateText('alpha');
    notifier.updateScope(SearchScope.all);
    return container.read(searchResultsProvider(page: page).future);
  }

  group('all scope (searchAll has no offset parameter on the interface)', () {
    test('full first page with more matches available -> hasNextPage true',
        () async {
      final fake = _FakeSearchService(totalMatches: 120, factory: result);
      final container = makeContainer(fake);

      final model = await runSearch(container, page: 1);

      expect(model.results, hasLength(50));
      expect(model.results.first.id, 'r-0');
      expect(model.hasNextPage, isTrue);
    });

    test('exactly pageSize matches -> hasNextPage false (no phantom page)',
        () async {
      final fake = _FakeSearchService(totalMatches: 50, factory: result);
      final container = makeContainer(fake);

      final model = await runSearch(container, page: 1);

      expect(model.results, hasLength(50));
      expect(
        model.hasNextPage,
        isFalse,
        reason: 'with exactly 50 matches there is no second page; the old '
            'full-page heuristic invented one',
      );
    });

    test('page 2 returns the NEXT distinct slice, not a copy of page 1',
        () async {
      final fake = _FakeSearchService(totalMatches: 120, factory: result);
      final container = makeContainer(fake);

      final model = await runSearch(container, page: 2);

      expect(model.results, hasLength(50));
      expect(
        model.results.first.id,
        'r-50',
        reason: 'page 2 must start where page 1 ended (searchAll has no '
            'offset, so the provider must window the over-fetched results)',
      );
      expect(model.results.last.id, 'r-99');
      expect(model.hasNextPage, isTrue);
    });

    test('last partial page -> correct slice, hasNextPage false', () async {
      final fake = _FakeSearchService(totalMatches: 120, factory: result);
      final container = makeContainer(fake);

      final model = await runSearch(container, page: 3);

      expect(model.results, hasLength(20));
      expect(model.results.first.id, 'r-100');
      expect(model.hasNextPage, isFalse);
      expect(model.totalCount, 120);
    });
  });
}

/// Fake search service returning a deterministic, relevance-ordered global
/// result list truncated to the requested limit (mirrors the real service:
/// it always returns the most relevant prefix of the full match set).
class _FakeSearchService implements ISearchService {
  _FakeSearchService({required this.totalMatches, required this.factory});

  final int totalMatches;
  final SearchResult Function(int index, int total) factory;

  List<SearchResult> _prefix(int limit) {
    final count = limit < totalMatches ? limit : totalMatches;
    return List.generate(count, (i) => factory(i, totalMatches));
  }

  @override
  Future<Result<List<SearchResult>, SearchServiceException>> searchAll(
    String query, {
    SearchFilter? filter,
    int limit = 100,
  }) async {
    return Ok(_prefix(limit));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'Unexpected call to ${invocation.memberName} in _FakeSearchService',
      );
}
