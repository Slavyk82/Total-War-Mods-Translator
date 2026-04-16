// Widget tests for the migrated Translation Memory screen (Plan 5a · Task 6).
//
// The screen was refactored from the FluentScaffold header/toolbar layout to
// the §7.1 filterable-list archetype: [FilterToolbar] on top of a tokenised
// [SfDataGrid] with the preserved 280px [TmStatisticsPanel] and
// [TmPaginationBar]. These tests exercise the new chrome and verify the
// screen renders without touching the legacy header widgets.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/features/translation_memory/screens/translation_memory_screen.dart';
import 'package:twmt/features/translation_memory/widgets/tm_pagination_bar.dart';
import 'package:twmt/features/translation_memory/widgets/tm_statistics_panel.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';

import '../../../helpers/test_helpers.dart';

const int _baseEpoch = 1_700_000_000;

TranslationMemoryEntry _entry({
  required String id,
  required String sourceText,
  required String translatedText,
  int usageCount = 1,
  int? lastUsedAt,
}) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: sourceText,
      sourceHash: id,
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: translatedText,
      usageCount: usageCount,
      createdAt: _baseEpoch,
      lastUsedAt: lastUsedAt ?? _baseEpoch,
      updatedAt: lastUsedAt ?? _baseEpoch,
    );

List<TranslationMemoryEntry> _populatedEntries() => [
      _entry(
        id: 'tm1',
        sourceText: 'Hello, world',
        translatedText: 'Bonjour le monde',
        usageCount: 42,
        lastUsedAt: _baseEpoch,
      ),
      _entry(
        id: 'tm2',
        sourceText: 'Victory or death',
        translatedText: 'Victoire ou mort',
        usageCount: 7,
        lastUsedAt: _baseEpoch - 86400 * 3,
      ),
      _entry(
        id: 'tm3',
        sourceText: 'For the Empire!',
        translatedText: 'Pour l\'Empire !',
        usageCount: 1,
        lastUsedAt: _baseEpoch - 86400 * 30,
      ),
    ];

/// Fake [ITranslationMemoryService] that returns a fixed in-memory set of
/// entries so the screen can render a populated [SfDataGrid] under test.
class _PopulatedTmService implements ITranslationMemoryService {
  _PopulatedTmService(this._entries);

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
      Ok(_entries
          .where((e) =>
              e.sourceText.toLowerCase().contains(searchText.toLowerCase()) ||
              e.translatedText
                  .toLowerCase()
                  .contains(searchText.toLowerCase()))
          .toList());

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) async =>
      Ok(TmStatistics(
        totalEntries: _entries.length,
        entriesByLanguagePair: const {'en → fr': 3},
        totalReuseCount: 50,
        tokensSaved: 1200,
        averageFuzzyScore: 0.92,
        reuseRate: 0.34,
      ));

  // ---------------- Unused by the screen under test ----------------
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

List<Override> _populatedOverrides() => [
      // Pin the clock so the "LAST USED" cells render deterministically.
      clockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
            .add(const Duration(days: 1)),
      ),
      translationMemoryServiceProvider
          .overrideWithValue(_PopulatedTmService(_populatedEntries())),
    ];

List<Override> _emptyOverrides() => [
      clockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
            .add(const Duration(days: 1)),
      ),
      translationMemoryServiceProvider
          .overrideWithValue(_PopulatedTmService(const [])),
    ];

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  testWidgets(
      'TranslationMemoryScreen renders FilterToolbar + SfDataGrid + stats panel',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const TranslationMemoryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await t.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.byType(TmStatisticsPanel), findsOneWidget);
    expect(find.byType(TmPaginationBar), findsOneWidget);
  });

  testWidgets('Toolbar shows Import/Export/Cleanup action buttons',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const TranslationMemoryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await t.pumpAndSettle();

    expect(find.text('Import TMX'), findsOneWidget);
    expect(find.text('Export TMX'), findsOneWidget);
    expect(find.text('Cleanup'), findsOneWidget);
  });

  testWidgets('Populated grid renders source and target text cells',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const TranslationMemoryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await t.pumpAndSettle();

    expect(find.text('Hello, world'), findsOneWidget);
    expect(find.text('Bonjour le monde'), findsOneWidget);
    expect(find.text('Victory or death'), findsOneWidget);
  });

  testWidgets('Search field filters the grid via the TM filter provider',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const TranslationMemoryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await t.pumpAndSettle();

    expect(find.text('Hello, world'), findsOneWidget);
    expect(find.text('Victory or death'), findsOneWidget);

    await t.enterText(find.byType(ListSearchField), 'victory');
    await t.pumpAndSettle();

    expect(find.text('Hello, world'), findsNothing);
    expect(find.text('Victory or death'), findsOneWidget);
  });

  testWidgets('Empty TM surfaces the tokenised empty state', (t) async {
    await t.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const TranslationMemoryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _emptyOverrides(),
    ));
    await t.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsNothing);
    expect(find.text('No translation memory entries'), findsOneWidget);
  });
}
