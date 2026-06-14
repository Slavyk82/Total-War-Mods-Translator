// Line-coverage test for lib/features/translation_memory/providers/tm_providers.dart.
//
// Exercises every provider/notifier in the file: the manual sort notifier,
// the async data providers (entries / count / statistics / search) on both the
// Ok and Err paths, the simple state notifiers (selected entry, filters, page),
// and the async-state CRUD notifiers (import / export / cleanup / update /
// delete) across loading -> data and loading -> error transitions.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockTmService extends Mock implements ITranslationMemoryService {}

TranslationMemoryEntry _entry(String id) => TranslationMemoryEntry(
      id: id,
      sourceText: 'src-$id',
      sourceHash: 'hash-$id',
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: 'tgt-$id',
      usageCount: 1,
      createdAt: 1000,
      lastUsedAt: 1000,
      updatedAt: 1000,
    );

const _stats = TmStatistics(
  totalEntries: 7,
  entriesByLanguagePair: {'en->fr': 7},
  totalReuseCount: 3,
  tokensSaved: 42,
  averageFuzzyScore: 0.9,
  reuseRate: 0.5,
);

ProviderContainer _makeContainer(_MockTmService service) {
  final container = ProviderContainer(overrides: [
    loggingServiceProvider.overrideWithValue(FakeLogger()),
    translationMemoryServiceProvider.overrideWithValue(service),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(TmSearchScope.both);
  });

  late _MockTmService service;
  late ProviderContainer container;

  setUp(() {
    service = _MockTmService();
    container = _makeContainer(service);
  });

  // --------------------------------------------------------------------------
  // TmSort + TmSortStateNotifier (manual provider)
  // --------------------------------------------------------------------------
  group('TmSort.toOrderBy', () {
    test('maps known columns and direction', () {
      expect(const TmSort(column: 'source', ascending: true).toOrderBy(),
          'source_text ASC');
      expect(const TmSort(column: 'target', ascending: false).toOrderBy(),
          'translated_text DESC');
      expect(const TmSort(column: 'usage', ascending: true).toOrderBy(),
          'usage_count ASC');
      expect(const TmSort(column: 'lastUsed', ascending: false).toOrderBy(),
          'last_used_at DESC');
    });

    test('falls back to usage_count for unknown column', () {
      expect(const TmSort(column: 'mystery', ascending: true).toOrderBy(),
          'usage_count ASC');
    });
  });

  group('TmSortStateNotifier', () {
    test('default state is usage descending', () {
      final sort = container.read(tmSortStateProvider);
      expect(sort.column, 'usage');
      expect(sort.ascending, isFalse);
    });

    test('setSort replaces state', () {
      container.read(tmSortStateProvider.notifier).setSort('source', true);
      final sort = container.read(tmSortStateProvider);
      expect(sort.column, 'source');
      expect(sort.ascending, isTrue);
    });

    test('toggleSort flips direction on same column', () {
      final notifier = container.read(tmSortStateProvider.notifier);
      notifier.setSort('target', true);
      notifier.toggleSort('target');
      expect(container.read(tmSortStateProvider).ascending, isFalse);
    });

    test('toggleSort on a new column resets to descending', () {
      final notifier = container.read(tmSortStateProvider.notifier);
      notifier.setSort('source', true);
      notifier.toggleSort('usage');
      final sort = container.read(tmSortStateProvider);
      expect(sort.column, 'usage');
      expect(sort.ascending, isFalse);
    });
  });

  // --------------------------------------------------------------------------
  // tmEntries provider
  // --------------------------------------------------------------------------
  group('tmEntries', () {
    test('returns entries on Ok and forwards sort/pagination', () async {
      when(() => service.getEntries(
            targetLanguageCode: any(named: 'targetLanguageCode'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => Ok([_entry('a'), _entry('b')]));

      final result = await container.read(
        tmEntriesProvider(targetLang: 'fr', page: 2, pageSize: 100).future,
      );

      expect(result, hasLength(2));
      verify(() => service.getEntries(
            targetLanguageCode: 'fr',
            limit: 100,
            offset: 100, // (page 2 - 1) * 100
            orderBy: 'usage_count DESC',
          )).called(1);
    });

    test('rethrows on Err', () async {
      when(() => service.getEntries(
            targetLanguageCode: any(named: 'targetLanguageCode'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer(
          (_) async => const Err(TmServiceException('boom')));

      final sub = container.listen(tmEntriesProvider(), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(sub.read().hasError, isTrue);
      expect(sub.read().error, isA<TmServiceException>());
    });

    test('rethrows when the service throws', () async {
      when(() => service.getEntries(
            targetLanguageCode: any(named: 'targetLanguageCode'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenThrow(StateError('exploded'));

      final sub = container.listen(tmEntriesProvider(), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(sub.read().hasError, isTrue);
      expect(sub.read().error, isA<StateError>());
    });
  });

  // --------------------------------------------------------------------------
  // tmEntriesCount provider
  // --------------------------------------------------------------------------
  group('tmEntriesCount', () {
    test('returns count on Ok', () async {
      when(() => service.countEntries(
              targetLanguageCode: any(named: 'targetLanguageCode')))
          .thenAnswer((_) async => const Ok(11));

      final count =
          await container.read(tmEntriesCountProvider(targetLang: 'fr').future);
      expect(count, 11);
    });

    test('returns 0 on Err', () async {
      when(() => service.countEntries(
              targetLanguageCode: any(named: 'targetLanguageCode')))
          .thenAnswer((_) async => const Err(TmServiceException('nope')));

      final count = await container.read(tmEntriesCountProvider().future);
      expect(count, 0);
    });
  });

  // --------------------------------------------------------------------------
  // tmStatistics provider
  // --------------------------------------------------------------------------
  group('tmStatistics', () {
    test('returns stats on Ok', () async {
      when(() => service.getStatistics(
              targetLanguageCode: any(named: 'targetLanguageCode')))
          .thenAnswer((_) async => const Ok(_stats));

      final stats =
          await container.read(tmStatisticsProvider(targetLang: 'fr').future);
      expect(stats.totalEntries, 7);
    });

    test('rethrows on Err', () async {
      when(() => service.getStatistics(
              targetLanguageCode: any(named: 'targetLanguageCode')))
          .thenAnswer((_) async => const Err(TmServiceException('stat-err')));

      final sub = container.listen(tmStatisticsProvider(), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(sub.read().hasError, isTrue);
      expect(sub.read().error, isA<TmServiceException>());
    });
  });

  // --------------------------------------------------------------------------
  // tmSearchResults provider
  // --------------------------------------------------------------------------
  group('tmSearchResults', () {
    test('returns empty list immediately for empty search text', () async {
      final results = await container
          .read(tmSearchResultsProvider(searchText: '').future);
      expect(results, isEmpty);
      // No service call should have been made for empty search text.
      verifyZeroInteractions(service);
    });

    test('returns entries on Ok and forwards parameters', () async {
      when(() => service.searchEntries(
            searchText: any(named: 'searchText'),
            searchIn: any(named: 'searchIn'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Ok([_entry('s')]));

      final results = await container.read(tmSearchResultsProvider(
        searchText: 'hello',
        searchIn: TmSearchScope.source,
        targetLang: 'fr',
        limit: 25,
      ).future);

      expect(results, hasLength(1));
      verify(() => service.searchEntries(
            searchText: 'hello',
            searchIn: TmSearchScope.source,
            targetLanguageCode: 'fr',
            limit: 25,
          )).called(1);
    });

    test('rethrows on Err', () async {
      when(() => service.searchEntries(
            searchText: any(named: 'searchText'),
            searchIn: any(named: 'searchIn'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            limit: any(named: 'limit'),
          )).thenAnswer(
          (_) async => const Err(TmServiceException('search-err')));

      final sub =
          container.listen(tmSearchResultsProvider(searchText: 'x'), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(sub.read().hasError, isTrue);
      expect(sub.read().error, isA<TmServiceException>());
    });
  });

  // --------------------------------------------------------------------------
  // SelectedTmEntry notifier
  // --------------------------------------------------------------------------
  group('SelectedTmEntry', () {
    test('build defaults to null, select then clear', () {
      expect(container.read(selectedTmEntryProvider), isNull);

      final entry = _entry('sel');
      container.read(selectedTmEntryProvider.notifier).select(entry);
      expect(container.read(selectedTmEntryProvider), entry);

      container.read(selectedTmEntryProvider.notifier).clear();
      expect(container.read(selectedTmEntryProvider), isNull);
    });
  });

  // --------------------------------------------------------------------------
  // TmFilterState notifier
  // --------------------------------------------------------------------------
  group('TmFilterState', () {
    test('default, setters, and reset', () {
      expect(container.read(tmFilterStateProvider).targetLanguage, isNull);
      expect(container.read(tmFilterStateProvider).searchText, '');

      final notifier = container.read(tmFilterStateProvider.notifier);
      notifier.setTargetLanguage('de');
      notifier.setSearchText('orc');
      expect(container.read(tmFilterStateProvider).targetLanguage, 'de');
      expect(container.read(tmFilterStateProvider).searchText, 'orc');

      notifier.reset();
      expect(container.read(tmFilterStateProvider).targetLanguage, isNull);
      expect(container.read(tmFilterStateProvider).searchText, '');
    });
  });

  // --------------------------------------------------------------------------
  // TmPageState notifier
  // --------------------------------------------------------------------------
  group('TmPageState', () {
    test('default, setPage, next/previous, clamp at 1, reset', () {
      final notifier = container.read(tmPageStateProvider.notifier);
      expect(container.read(tmPageStateProvider), 1);

      notifier.setPage(5);
      expect(container.read(tmPageStateProvider), 5);

      notifier.nextPage();
      expect(container.read(tmPageStateProvider), 6);

      notifier.previousPage();
      expect(container.read(tmPageStateProvider), 5);

      notifier.setPage(1);
      notifier.previousPage(); // should not go below 1
      expect(container.read(tmPageStateProvider), 1);

      notifier.setPage(9);
      notifier.reset();
      expect(container.read(tmPageStateProvider), 1);
    });
  });

  // --------------------------------------------------------------------------
  // Result value objects (summary getters)
  // --------------------------------------------------------------------------
  group('result value objects', () {
    test('TmImportResult.summary formats the counts', () {
      const r = TmImportResult(
        totalEntries: 10,
        importedEntries: 8,
        skippedEntries: 1,
        failedEntries: 1,
      );
      expect(r.summary,
          'Total: 10 | Imported: 8 | Skipped: 1 | Failed: 1');
    });

    test('TmExportResult.summary formats the path and count', () {
      const r = TmExportResult(entriesExported: 5, filePath: 'out.tmx');
      expect(r.summary, 'Exported 5 entries to out.tmx');
    });
  });

  // --------------------------------------------------------------------------
  // TmImportState notifier
  // --------------------------------------------------------------------------
  group('TmImportState', () {
    test('build is data(null); reset returns to data(null)', () {
      expect(container.read(tmImportStateProvider).value, isNull);
      container.read(tmImportStateProvider.notifier).reset();
      expect(container.read(tmImportStateProvider).hasValue, isTrue);
    });

    test('importFromTmx success sets result and forwards args', () async {
      when(() => service.importFromTmx(
            filePath: any(named: 'filePath'),
            overwriteExisting: any(named: 'overwriteExisting'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(5));

      await container.read(tmImportStateProvider.notifier).importFromTmx(
            filePath: r'C:\tmp\in.tmx',
            overwriteExisting: true,
          );

      final state = container.read(tmImportStateProvider);
      expect(state.value?.importedEntries, 5);
      expect(state.value?.totalEntries, 5);
      verify(() => service.importFromTmx(
            filePath: r'C:\tmp\in.tmx',
            overwriteExisting: true,
            onProgress: null,
          )).called(1);
    });

    test('importFromTmx Err puts notifier into error state', () async {
      when(() => service.importFromTmx(
            filePath: any(named: 'filePath'),
            overwriteExisting: any(named: 'overwriteExisting'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
          (_) async => const Err(TmImportException('import-fail')));

      await container.read(tmImportStateProvider.notifier).importFromTmx(
            filePath: r'C:\tmp\in.tmx',
          );

      expect(container.read(tmImportStateProvider).hasError, isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // TmExportState notifier
  // --------------------------------------------------------------------------
  group('TmExportState', () {
    test('build is data(null); reset returns to data(null)', () {
      expect(container.read(tmExportStateProvider).value, isNull);
      container.read(tmExportStateProvider.notifier).reset();
      expect(container.read(tmExportStateProvider).hasValue, isTrue);
    });

    test('exportToTmx Err puts notifier into error state', () async {
      when(() => service.exportToTmx(
            outputPath: any(named: 'outputPath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minUsageCount: any(named: 'minUsageCount'),
            includeMetadata: any(named: 'includeMetadata'),
            includeStats: any(named: 'includeStats'),
          )).thenAnswer(
          (_) async => const Err(TmExportException('export-fail')));

      await container.read(tmExportStateProvider.notifier).exportToTmx(
            outputPath: r'C:\tmp\out.tmx',
          );

      expect(container.read(tmExportStateProvider).hasError, isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // TmCleanupState notifier
  // --------------------------------------------------------------------------
  group('TmCleanupState', () {
    test('build is data(null); reset returns to data(null)', () {
      expect(container.read(tmCleanupStateProvider).value, isNull);
      container.read(tmCleanupStateProvider.notifier).reset();
      expect(container.read(tmCleanupStateProvider).hasValue, isTrue);
    });

    test('cleanup success sets deleted count and resets page', () async {
      when(() => service.cleanupUnusedEntries(
              unusedDays: any(named: 'unusedDays')))
          .thenAnswer((_) async => const Ok(4));

      // Move page off 1 to observe reset side-effect.
      container.read(tmPageStateProvider.notifier).setPage(3);

      await container
          .read(tmCleanupStateProvider.notifier)
          .cleanup(unusedDays: 30);

      expect(container.read(tmCleanupStateProvider).value, 4);
      expect(container.read(tmPageStateProvider), 1);
      verify(() => service.cleanupUnusedEntries(unusedDays: 30)).called(1);
    });

    test('cleanup Err puts notifier into error state', () async {
      when(() => service.cleanupUnusedEntries(
              unusedDays: any(named: 'unusedDays')))
          .thenAnswer(
          (_) async => const Err(TmServiceException('cleanup-fail')));

      await container.read(tmCleanupStateProvider.notifier).cleanup();

      expect(container.read(tmCleanupStateProvider).hasError, isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // TmUpdateState notifier
  // --------------------------------------------------------------------------
  group('TmUpdateState', () {
    test('build is data(null); reset returns to data(null)', () {
      expect(container.read(tmUpdateStateProvider).value, isNull);
      container.read(tmUpdateStateProvider.notifier).reset();
      expect(container.read(tmUpdateStateProvider).hasValue, isTrue);
    });

    test('updateTargetText success returns true and sets state', () async {
      when(() => service.updateTargetText(
            entryId: any(named: 'entryId'),
            newTargetText: any(named: 'newTargetText'),
          )).thenAnswer((_) async => Ok(_entry('u')));

      final ok = await container
          .read(tmUpdateStateProvider.notifier)
          .updateTargetText(entryId: 'u', newTargetText: 'new');

      expect(ok, isTrue);
      expect(container.read(tmUpdateStateProvider).value, isTrue);
      verify(() => service.updateTargetText(
            entryId: 'u',
            newTargetText: 'new',
          )).called(1);
    });

    test('updateTargetText Err returns false and sets error', () async {
      when(() => service.updateTargetText(
            entryId: any(named: 'entryId'),
            newTargetText: any(named: 'newTargetText'),
          )).thenAnswer(
          (_) async => const Err(TmServiceException('update-fail')));

      final ok = await container
          .read(tmUpdateStateProvider.notifier)
          .updateTargetText(entryId: 'u', newTargetText: 'new');

      expect(ok, isFalse);
      expect(container.read(tmUpdateStateProvider).hasError, isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // TmDeleteState notifier
  // --------------------------------------------------------------------------
  group('TmDeleteState', () {
    test('build is data(null); reset returns to data(null)', () {
      expect(container.read(tmDeleteStateProvider).value, isNull);
      container.read(tmDeleteStateProvider.notifier).reset();
      expect(container.read(tmDeleteStateProvider).hasValue, isTrue);
    });

    test('deleteEntry success returns true and sets state', () async {
      when(() => service.deleteEntry(entryId: any(named: 'entryId')))
          .thenAnswer((_) async => const Ok<void, TmServiceException>(null));

      final ok = await container
          .read(tmDeleteStateProvider.notifier)
          .deleteEntry('d1');

      expect(ok, isTrue);
      expect(container.read(tmDeleteStateProvider).value, isTrue);
      verify(() => service.deleteEntry(entryId: 'd1')).called(1);
    });

    test('deleteEntry Err returns false and sets error', () async {
      when(() => service.deleteEntry(entryId: any(named: 'entryId')))
          .thenAnswer(
          (_) async => const Err(TmServiceException('delete-fail')));

      final ok = await container
          .read(tmDeleteStateProvider.notifier)
          .deleteEntry('d1');

      expect(ok, isFalse);
      expect(container.read(tmDeleteStateProvider).hasError, isTrue);
    });

    test('deleteEntries returns 0 immediately for empty input', () async {
      final deleted = await container
          .read(tmDeleteStateProvider.notifier)
          .deleteEntries(const <String>[]);

      expect(deleted, 0);
      verifyZeroInteractions(service);
    });

    test('deleteEntries counts only Ok results; all-ok => state true',
        () async {
      when(() => service.deleteEntry(entryId: any(named: 'entryId')))
          .thenAnswer((_) async => const Ok<void, TmServiceException>(null));

      final deleted = await container
          .read(tmDeleteStateProvider.notifier)
          .deleteEntries(['a', 'b', 'c']);

      expect(deleted, 3);
      expect(container.read(tmDeleteStateProvider).value, isTrue);
    });

    test('deleteEntries with partial failures => state false', () async {
      when(() => service.deleteEntry(entryId: 'ok'))
          .thenAnswer((_) async => const Ok<void, TmServiceException>(null));
      when(() => service.deleteEntry(entryId: 'bad'))
          .thenAnswer((_) async => const Err(TmServiceException('x')));

      final deleted = await container
          .read(tmDeleteStateProvider.notifier)
          .deleteEntries(['ok', 'bad']);

      expect(deleted, 1);
      expect(container.read(tmDeleteStateProvider).value, isFalse);
    });

    test('deleteEntries surfaces a thrown error into the notifier', () async {
      when(() => service.deleteEntry(entryId: any(named: 'entryId')))
          .thenThrow(StateError('explode'));

      final deleted = await container
          .read(tmDeleteStateProvider.notifier)
          .deleteEntries(['a']);

      expect(deleted, 0);
      expect(container.read(tmDeleteStateProvider).hasError, isTrue);
    });
  });
}
