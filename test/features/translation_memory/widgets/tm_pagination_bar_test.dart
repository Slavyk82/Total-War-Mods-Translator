// Widget tests for [TmPaginationBar].
//
// The bar reads three providers:
//   * [tmEntriesCountProvider] — total unfiltered entry count (drives the
//     "Showing X–Y of Z" label and the number of pages),
//   * [tmPageStateProvider]    — the 1-based current page,
//   * [tmFilterStateProvider]  — when a search filter is active the whole bar
//     collapses to a [SizedBox.shrink].
//
// `_itemsPerPage` is fixed at 1000 (there is NO page-size selector in this
// widget), so multiple pages require a total count > 1000 and the ellipsis
// branches require > 7000. We drive the count via a fake
// [ITranslationMemoryService.countEntries] and the page via
// [TmPageState.setPage]. Navigation taps are asserted by reading back the
// resulting [tmPageStateProvider] value.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, UncontrolledProviderScope;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/widgets/tm_pagination_bar.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/app_theme.dart';

/// Minimal fake TM service whose only meaningful method is [countEntries],
/// which returns the fixed count supplied at construction.
class _CountOnlyTmService implements ITranslationMemoryService {
  _CountOnlyTmService(this._count);

  final int _count;

  @override
  Future<Result<int, TmServiceException>> countEntries({
    String? targetLanguageCode,
  }) async =>
      Ok(_count);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async =>
      const Ok([]);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = 50,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) async =>
      Ok(const TmStatistics(
        totalEntries: 0,
        entriesByLanguagePair: {},
        totalReuseCount: 0,
        tokensSaved: 0,
        averageFuzzyScore: 0,
        reuseRate: 0,
      ));

  // ---------------- Unused by the widget under test ----------------
  @override
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  }) async =>
      Err(const TmAddException('not implemented'));

  @override
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  }) async =>
      const Ok(0);

  @override
  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
  }) async =>
      const Ok(null);

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    String? category,
  }) async =>
      const Ok(null);

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatchesIsolate({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({
    required String entryId,
  }) async =>
      Err(const TmServiceException('not implemented'));

  @override
  Future<Result<int, TmServiceException>> incrementUsageCountBatch(
    Map<String, int> usageCounts,
  ) async =>
      const Ok(0);

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>> updateTargetText({
    required String entryId,
    required String newTargetText,
  }) async =>
      Err(const TmServiceException('not implemented'));

  @override
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) async =>
      const Ok(null);

  @override
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = 365,
  }) async =>
      const Ok(0);

  @override
  Future<Result<int, TmImportException>> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async =>
      const Ok(0);

  @override
  Future<Result<int, TmExportException>> exportToTmx({
    required String outputPath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
    int? minUsageCount,
    bool includeMetadata = true,
    bool includeStats = true,
  }) async =>
      const Ok(0);

  @override
  Future<void> clearCache() async {}

  @override
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = 10000,
  }) async =>
      const Ok(null);

  @override
  Future<Result<({int added, int existing}), TmServiceException>>
      rebuildFromTranslations({
    String? projectId,
    void Function(int processed, int total, int added)? onProgress,
  }) async =>
      const Ok((added: 0, existing: 0));

  @override
  Future<Result<int, TmServiceException>> migrateLegacyHashes({
    void Function(int processed, int total)? onProgress,
  }) async =>
      const Ok(0);
}

/// Builds a container wired with a [_CountOnlyTmService] returning [count].
ProviderContainer _container(int count) {
  final container = ProviderContainer(
    overrides: [
      translationMemoryServiceProvider
          .overrideWithValue(_CountOnlyTmService(count)),
    ],
  );
  return container;
}

/// Pumps the bar inside the tokenised dark theme with a wide surface so the
/// horizontal page-number row never overflows.
Future<ProviderContainer> _pumpBar(
  WidgetTester tester, {
  required int count,
  int? page,
  String search = '',
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = _container(count);
  addTearDown(container.dispose);

  if (page != null) {
    container.read(tmPageStateProvider.notifier).setPage(page);
  }
  if (search.isNotEmpty) {
    container.read(tmFilterStateProvider.notifier).setSearchText(search);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(body: TmPaginationBar()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('TmPaginationBar - count / label rendering', () {
    testWidgets('zero entries shows the zeroEntries label and no nav',
        (t) async {
      await _pumpBar(t, count: 0);

      expect(find.text('0 entries'), findsOneWidget);
      // No pages -> no first/prev/next/last nav icons.
      expect(find.byTooltip('First page'), findsNothing);
      expect(find.byTooltip('Last page'), findsNothing);
    });

    testWidgets('single page (count <= 1000) shows range but hides nav',
        (t) async {
      await _pumpBar(t, count: 500);

      expect(find.text('Showing 1–500 of 500'), findsOneWidget);
      // totalPages == 1 -> _buildPageNavigation returns SizedBox.shrink.
      expect(find.byTooltip('First page'), findsNothing);
      expect(find.byTooltip('Next page'), findsNothing);
    });

    testWidgets('count exactly 1000 is still a single page', (t) async {
      await _pumpBar(t, count: 1000);

      expect(find.text('Showing 1–1000 of 1000'), findsOneWidget);
      expect(find.byTooltip('Next page'), findsNothing);
    });

    testWidgets('middle page label clamps endItem to the page window',
        (t) async {
      // 3500 entries => 4 pages. Page 2 covers items 1001–2000.
      await _pumpBar(t, count: 3500, page: 2);

      expect(find.text('Showing 1001–2000 of 3500'), findsOneWidget);
    });

    testWidgets('last partial page clamps endItem to the total', (t) async {
      // 3500 entries => 4 pages. Page 4 covers items 3001–3500 (clamped).
      await _pumpBar(t, count: 3500, page: 4);

      expect(find.text('Showing 3001–3500 of 3500'), findsOneWidget);
    });
  });

  group('TmPaginationBar - search hides the bar', () {
    testWidgets('active search filter collapses the whole bar', (t) async {
      await _pumpBar(t, count: 3500, search: 'hello');

      // The entire bar is a SizedBox.shrink: no label, no nav.
      expect(find.textContaining('Showing'), findsNothing);
      expect(find.byTooltip('First page'), findsNothing);
      // Container with the panel decoration should not be present either.
      expect(find.byType(Row), findsNothing);
    });
  });

  group('TmPaginationBar - navigation enabled/disabled at boundaries', () {
    testWidgets('first page: prev/first disabled, next/last enabled',
        (t) async {
      // 3500 entries => 4 pages, start on page 1.
      final container = await _pumpBar(t, count: 3500, page: 1);

      expect(container.read(tmPageStateProvider), 1);

      // Disabled _NavIcons render without a Tooltip wrapper (onTap == null),
      // so First/Previous are NOT findable by tooltip on the first page.
      expect(find.byTooltip('First page'), findsNothing);
      expect(find.byTooltip('Previous page'), findsNothing);

      // Next/Last are enabled and therefore present.
      expect(find.byTooltip('Next page'), findsOneWidget);
      expect(find.byTooltip('Last page'), findsOneWidget);

      // Next advances to page 2.
      await t.tap(find.byTooltip('Next page'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 2);
    });

    testWidgets('last page: next/last disabled, prev/first enabled',
        (t) async {
      // 3500 entries => 4 pages, start on page 4 (last).
      final container = await _pumpBar(t, count: 3500, page: 4);

      expect(container.read(tmPageStateProvider), 4);

      // Disabled Next/Last have no tooltip wrapper on the last page.
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.byTooltip('Last page'), findsNothing);

      // Prev/First are enabled.
      expect(find.byTooltip('Previous page'), findsOneWidget);
      expect(find.byTooltip('First page'), findsOneWidget);

      // First jumps back to page 1.
      await t.tap(find.byTooltip('First page'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 1);
    });

    testWidgets('middle page: all four nav buttons fire', (t) async {
      // 3500 entries => 4 pages, start on page 2.
      final container = await _pumpBar(t, count: 3500, page: 2);

      // First -> page 1.
      await t.tap(find.byTooltip('First page'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 1);

      // Reset to page 2 and exercise Last.
      container.read(tmPageStateProvider.notifier).setPage(2);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Last page'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 4);

      // Reset to page 2 and exercise Previous / Next.
      container.read(tmPageStateProvider.notifier).setPage(2);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Previous page'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 1);

      container.read(tmPageStateProvider.notifier).setPage(2);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Next page'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 3);
    });
  });

  group('TmPaginationBar - page-number buttons', () {
    testWidgets('few pages (<=7) render every page number and tapping one '
        'sets the page', (t) async {
      // 4000 entries => 4 pages, all shown (no ellipsis).
      final container = await _pumpBar(t, count: 4000, page: 1);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // No ellipsis for <= 7 pages.
      expect(find.text('…'), findsNothing);

      // Tap page 3.
      await t.tap(find.text('3'));
      await t.pumpAndSettle();
      expect(container.read(tmPageStateProvider), 3);
    });

    testWidgets('many pages from page 1 show a trailing ellipsis', (t) async {
      // 15000 entries => 15 pages. From page 1 the visible set is
      // [1, 2, 3, 4, 5, …, 15] -> one ellipsis after the range.
      await _pumpBar(t, count: 15000, page: 1);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('many pages on a middle page show two ellipses', (t) async {
      // 15000 entries => 15 pages. From page 8 the visible set is
      // [1, …, 6, 7, 8, 9, 10, …, 15] -> two ellipses.
      await _pumpBar(t, count: 15000, page: 8);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('…'), findsNWidgets(2));
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('many pages near the end show a leading ellipsis', (t) async {
      // 15000 entries => 15 pages. From the last page the visible set is
      // [1, …, 11, 12, 13, 14, 15] -> one leading ellipsis.
      await _pumpBar(t, count: 15000, page: 15);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
    });
  });
}
