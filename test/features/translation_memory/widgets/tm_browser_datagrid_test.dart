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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

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
  _FakeTmService(this._entries);

  final List<TranslationMemoryEntry> _entries;

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async =>
      Ok(_entries);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = 50,
  }) async =>
      Ok(_entries);

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
}
