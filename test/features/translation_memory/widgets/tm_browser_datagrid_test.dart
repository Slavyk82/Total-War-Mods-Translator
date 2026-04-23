// Unit test for [TmBrowserDataGrid]'s data-source reuse.
//
// Task 6 (Plan 5a) code-review follow-up: the widget used to allocate a
// brand new `_TmDataSource` on every build, re-mapping every entry into a
// fresh `DataGridRow`. The refactor keeps one data source per State and
// calls `updateEntries` each build, which must be a no-op when the upstream
// list reference is unchanged. This test locks the behaviour in: we pump
// the widget, capture `SfDataGrid.source`, force the parent to rebuild,
// and assert the source is identical across frames.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, UncontrolledProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/widgets/tm_browser_datagrid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

const int _baseEpoch = 1_700_000_000;

TranslationMemoryEntry _entry(String id, String src, String tgt) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: src,
      sourceHash: id,
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: tgt,
      usageCount: 1,
      createdAt: _baseEpoch,
      lastUsedAt: _baseEpoch,
      updatedAt: _baseEpoch,
    );

/// Minimal fake TM service returning the list it was constructed with.
///
/// The identity of the returned list matters: [tmEntriesProvider] hands the
/// same Dart List reference back to the widget on every rebuild that
/// doesn't invalidate the provider, so [_TmDataSource.updateEntries] should
/// short-circuit via its [identical] guard.
class _FakeTmService implements ITranslationMemoryService {
  _FakeTmService(List<TranslationMemoryEntry> entries)
      : _entries = List.of(entries);

  /// Live backing store. Each call to [getEntries] returns a FRESH copy so
  /// Riverpod sees a new list reference after [deleteEntry] mutates this.
  final List<TranslationMemoryEntry> _entries;

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async =>
      Ok(List.of(_entries));

  @override
  Future<Result<int, TmServiceException>> countEntries({
    String? targetLanguageCode,
  }) async =>
      Ok(_entries.length);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = 50,
  }) async =>
      Ok(List.of(_entries));

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) async =>
      Ok(TmStatistics(
        totalEntries: _entries.length,
        entriesByLanguagePair: const {'en → fr': 0},
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
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) async {
    _entries.removeWhere((e) => e.id == entryId);
    return const Ok(null);
  }

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

List<Override> _overrides(List<TranslationMemoryEntry> entries) => [
      clockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
            .add(const Duration(days: 1)),
      ),
      translationMemoryServiceProvider
          .overrideWithValue(_FakeTmService(entries)),
    ];

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  testWidgets(
      'TmBrowserDataGrid reuses the same _TmDataSource across rebuilds '
      'when upstream entries are unchanged (updateEntries is a no-op)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final entries = [
      _entry('tm1', 'Hello', 'Bonjour'),
      _entry('tm2', 'World', 'Monde'),
    ];

    // Wrap the grid in a StatefulBuilder so we can force a rebuild of the
    // parent without invalidating the TM provider — this simulates the
    // hover/tick rebuilds that used to allocate a fresh data source each
    // frame.
    late StateSetter forceRebuild;
    int tick = 0;

    await t.pumpWidget(createThemedTestableWidget(
      StatefulBuilder(
        builder: (context, setState) {
          forceRebuild = setState;
          return Column(
            children: [
              Text('tick=$tick'),
              const Expanded(child: TmBrowserDataGrid()),
            ],
          );
        },
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(entries),
    ));
    await t.pumpAndSettle();

    final firstSource =
        t.widget<SfDataGrid>(find.byType(SfDataGrid)).source;

    // Trigger several parent rebuilds. Each one re-enters build() on the
    // grid, which calls `_dataSource.updateEntries(entries)`. With the
    // identical-list guard in place, the data source instance must not be
    // replaced.
    for (var i = 0; i < 3; i++) {
      forceRebuild(() => tick++);
      await t.pump();
    }

    final laterSource =
        t.widget<SfDataGrid>(find.byType(SfDataGrid)).source;

    expect(identical(firstSource, laterSource), isTrue,
        reason:
            '_TmDataSource should be reused when the entries list is unchanged');
  });

  testWidgets(
      'TmBrowserDataGrid refreshes rendered rows after a TM entry is deleted '
      '(invalidate-driven rebuild must reach SfDataGrid._effectiveRows)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final service = _FakeTmService([
      _entry('tm1', 'Hello', 'Bonjour'),
      _entry('tm2', 'World', 'Monde'),
    ]);

    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
              .add(const Duration(days: 1)),
        ),
        translationMemoryServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: const Scaffold(body: TmBrowserDataGrid()),
        ),
      ),
    );
    await t.pumpAndSettle();

    // Both rows are visible initially.
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('World'), findsOneWidget);

    // Simulate what `TmDeleteState.deleteEntry` does after a successful
    // database delete: mutate the backing store, then invalidate the entries
    // provider so the widget re-fetches.
    await container.read(tmDeleteStateProvider.notifier).deleteEntry('tm1');
    await t.pumpAndSettle();

    // The deleted row must disappear from the displayed grid.
    expect(find.text('Hello'), findsNothing,
        reason: 'Deleted TM entry must be removed from the grid immediately');
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets(
      'TmBrowserDataGrid refreshes rendered rows after delete when a search '
      'filter is active (search provider branch)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final service = _FakeTmService([
      _entry('tm1', 'Hello', 'Bonjour'),
      _entry('tm2', 'World', 'Monde'),
    ]);

    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
              .add(const Duration(days: 1)),
        ),
        translationMemoryServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: const Scaffold(body: TmBrowserDataGrid()),
        ),
      ),
    );
    await t.pumpAndSettle();

    // Activate a search filter that still matches both rows. This pushes the
    // widget onto the `tmSearchResultsProvider` branch.
    container.read(tmFilterStateProvider.notifier).setSearchText('o');
    await t.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('World'), findsOneWidget);

    await container.read(tmDeleteStateProvider.notifier).deleteEntry('tm1');
    await t.pumpAndSettle();

    expect(find.text('Hello'), findsNothing,
        reason: 'Deleted TM entry must vanish even with a search filter on');
    expect(find.text('World'), findsOneWidget);
  });

  testWidgets(
      'Deleting via the trash icon + confirm dialog removes the row from '
      'the grid immediately (full UI flow)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final service = _FakeTmService([
      _entry('tm1', 'Hello', 'Bonjour'),
      _entry('tm2', 'World', 'Monde'),
    ]);

    await t.pumpWidget(createThemedTestableWidget(
      const TmBrowserDataGrid(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
              .add(const Duration(days: 1)),
        ),
        translationMemoryServiceProvider.overrideWithValue(service),
      ],
    ));
    await t.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('World'), findsOneWidget);

    // Tap the trash icon in the first row's actions cell.
    final deleteIcons = find.byTooltip('Delete entry');
    expect(deleteIcons, findsAtLeast(1));
    await t.tap(deleteIcons.first);
    await t.pumpAndSettle();

    // Confirm the deletion. The confirm button label in TokenConfirmDialog
    // matches the action's text; tap the (single) visible "Delete" text.
    expect(find.text('Delete'), findsOneWidget);
    await t.tap(find.text('Delete'));
    // Pump only a bounded number of frames (the success toast schedules a
    // 4 s dismiss timer we do not want to wait for).
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    // The first row must be gone from the grid.
    expect(find.text('Hello'), findsNothing,
        reason: 'Deleted TM entry must vanish from the grid immediately');
    expect(find.text('World'), findsOneWidget);

    // Drain the toast timer to satisfy the framework's "no dangling timers"
    // invariant.
    await t.pump(const Duration(seconds: 5));
  });
}
