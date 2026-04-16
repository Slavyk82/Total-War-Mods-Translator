// Golden tests for the migrated Translation Memory screen (Plan 5a · Task 6).
//
// Fixtures cover three usage counts, three "LAST USED" deltas (same-day,
// "3 days", "1 month") and the populated statistics panel. The clock is
// pinned via [clockProvider] so relative-date cells stay byte-stable.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/translation_memory/screens/translation_memory_screen.dart';
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

/// Pinned `now` = baseEpoch + 1 day so the "LAST USED" column produces:
///   tm1 → "1 day", tm2 → "4 days", tm3 → "1 month".
final DateTime _pinnedNow =
    DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
        .add(const Duration(days: 1));

/// Fake [ITranslationMemoryService] that returns the populated fixture.
class _FixedTmService implements ITranslationMemoryService {
  _FixedTmService(this._entries);

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
        entriesByLanguagePair: const {'en → fr': 3},
        totalReuseCount: 50,
        tokensSaved: 1200,
        averageFuzzyScore: 0.92,
        reuseRate: 0.34,
      ));

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
      clockProvider.overrideWithValue(() => _pinnedNow),
      translationMemoryServiceProvider
          .overrideWithValue(_FixedTmService(_populatedEntries())),
    ];

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    List<Override> overrides,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const TranslationMemoryScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('translation memory atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(TranslationMemoryScreen),
      matchesGoldenFile('../goldens/tm_atelier_populated.png'),
    );
  });

  testWidgets('translation memory forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(TranslationMemoryScreen),
      matchesGoldenFile('../goldens/tm_forge_populated.png'),
    );
  });
}
