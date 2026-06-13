// Coverage tests for lib/features/glossary/providers/glossary_providers.dart.
//
// Complements glossary_entry_editor_delete_test.dart (which covers
// GlossaryEntryEditor.delete()). This file exercises the remaining providers
// and supporting model classes: the read-side family providers, the
// SelectedGlossaryLanguage / currentGlossary chain, the entry editor save
// branches, the filter/page state notifiers, and the import/export notifiers.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/activity/services/activity_logger.dart';
import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/events/activity_event.dart';
import 'package:twmt/providers/activity_providers.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart'
    hide settingsServiceProvider;
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockGlossaryService extends Mock implements IGlossaryService {}

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockActivityLogger extends Mock implements ActivityLogger {}

/// Fixed-language test double for the per-game language notifier.
class _FakeSelectedGlossaryLanguage extends SelectedGlossaryLanguage {
  _FakeSelectedGlossaryLanguage(this._value);

  final String? _value;

  @override
  Future<String?> build(String gameCode) async => _value;
}

/// Fixed-game test double for [SelectedGame].
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _glossaryId = 'glossary-1';
const _gameCode = 'wh3';
const _game = ConfiguredGame(code: _gameCode, name: 'WH3', path: 'C:/wh3');

const _err = GlossaryDatabaseException('boom');
final _dbErr = TWMTDatabaseException('boom');

GlossaryEntry _entry(String id) => GlossaryEntry(
      id: id,
      glossaryId: _glossaryId,
      targetLanguageCode: 'fr',
      sourceTerm: 'Sword',
      targetTerm: 'Épée',
      createdAt: 1700000000,
      updatedAt: 1700000000,
    );

Glossary _glossary(String id) => Glossary(
      id: id,
      name: 'Test',
      gameCode: _gameCode,
      targetLanguageId: 'lang-fr',
      createdAt: 1700000000,
      updatedAt: 1700000000,
    );

Language _lang(String id, String code) =>
    Language(id: id, code: code, name: code, nativeName: code);

void main() {
  setUpAll(() {
    registerFallbackValue(ActivityEventType.glossaryEnriched);
    registerFallbackValue(_entry('fallback'));
  });

  late _MockGlossaryService service;

  setUp(() {
    service = _MockGlossaryService();
  });

  ProviderContainer makeContainer({List<Override> overrides = const []}) {
    final container = ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        glossaryServiceProvider.overrideWithValue(service),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('supporting model classes', () {
    test('GlossaryStatistics.fromJson with full json', () {
      final stats = GlossaryStatistics.fromJson(const {
        'totalEntries': 5,
        'entriesByLanguagePair': {'en-fr': 3, 'en-de': 2},
        'usedInTranslations': 4,
        'unusedEntries': 1,
        'usageRate': 0.8,
        'consistencyScore': 0.95,
        'duplicatesDetected': 2,
        'missingTranslations': 1,
        'forbiddenTerms': 3,
        'caseSensitiveTerms': 4,
      });

      expect(stats.totalEntries, 5);
      expect(stats.entriesByLanguagePair, {'en-fr': 3, 'en-de': 2});
      expect(stats.usedInTranslations, 4);
      expect(stats.unusedEntries, 1);
      expect(stats.usageRate, 0.8);
      expect(stats.consistencyScore, 0.95);
      expect(stats.duplicatesDetected, 2);
      expect(stats.missingTranslations, 1);
      expect(stats.forbiddenTerms, 3);
      expect(stats.caseSensitiveTerms, 4);
    });

    test('GlossaryStatistics.fromJson with empty json applies defaults', () {
      final stats = GlossaryStatistics.fromJson(const {});

      expect(stats.totalEntries, 0);
      expect(stats.entriesByLanguagePair, isEmpty);
      expect(stats.usedInTranslations, 0);
      expect(stats.unusedEntries, 0);
      expect(stats.usageRate, 0.0);
      expect(stats.consistencyScore, 1.0);
      expect(stats.duplicatesDetected, 0);
      expect(stats.missingTranslations, 0);
      expect(stats.forbiddenTerms, 0);
      expect(stats.caseSensitiveTerms, 0);
    });

    test('ImportResult.summary', () {
      const r = ImportResult(total: 10, imported: 7, skipped: 2, failed: 1);
      expect(r.summary, 'Total: 10 | Imported: 7 | Skipped: 2 | Failed: 1');
    });

    test('ExportResult.summary', () {
      const r = ExportResult(entriesExported: 42, filePath: 'C:/out.csv');
      expect(r.summary, 'Exported 42 entries to C:/out.csv');
    });

    test('GlossaryFilters.copyWith', () {
      const base = GlossaryFilters();
      expect(base.targetLanguage, isNull);
      expect(base.searchText, '');

      final updated = base.copyWith(targetLanguage: 'fr', searchText: 'sword');
      expect(updated.targetLanguage, 'fr');
      expect(updated.searchText, 'sword');

      // copyWith with null keeps the previous values.
      final kept = updated.copyWith();
      expect(kept.targetLanguage, 'fr');
      expect(kept.searchText, 'sword');
    });
  });

  group('glossaries provider', () {
    test('Ok path returns list', () async {
      when(() => service.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => Ok([_glossary('g1')]));

      final container = makeContainer();
      final result =
          await container.read(glossariesProvider(gameCode: _gameCode).future);

      expect(result, hasLength(1));
      expect(result.first.id, 'g1');
    });

    test('Err path surfaces error state', () async {
      when(() => service.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      container.listen(glossariesProvider(), (_, _) {});
      await container.pump();

      expect(container.read(glossariesProvider()).hasError, isTrue);
    });
  });

  group('glossaryAvailableLanguages provider', () {
    late _MockProjectLanguageRepository repo;

    setUp(() => repo = _MockProjectLanguageRepository());

    test('Ok path returns languages', () async {
      when(() => repo.distinctLanguagesForGameCode(_gameCode))
          .thenAnswer((_) async => Ok([_lang('l1', 'fr')]));

      final container = makeContainer(overrides: [
        projectLanguageRepositoryProvider.overrideWithValue(repo),
      ]);

      final result = await container
          .read(glossaryAvailableLanguagesProvider(_gameCode).future);
      expect(result, hasLength(1));
      expect(result.first.code, 'fr');
    });

    test('Err path surfaces error state', () async {
      when(() => repo.distinctLanguagesForGameCode(_gameCode))
          .thenAnswer((_) async => Err(_dbErr));

      final container = makeContainer(overrides: [
        projectLanguageRepositoryProvider.overrideWithValue(repo),
      ]);
      container.listen(
          glossaryAvailableLanguagesProvider(_gameCode), (_, _) {});
      await container.pump();

      expect(
          container.read(glossaryAvailableLanguagesProvider(_gameCode)).hasError,
          isTrue);
    });
  });

  group('hasProjectsForGame provider', () {
    late _MockProjectRepository repo;

    setUp(() => repo = _MockProjectRepository());

    test('Ok path returns bool', () async {
      when(() => repo.hasProjectsForGameCode(_gameCode))
          .thenAnswer((_) async => const Ok(true));

      final container = makeContainer(overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
      ]);

      expect(
          await container.read(hasProjectsForGameProvider(_gameCode).future),
          isTrue);
    });

    test('Err path surfaces error state', () async {
      when(() => repo.hasProjectsForGameCode(_gameCode))
          .thenAnswer((_) async => Err(_dbErr));

      final container = makeContainer(overrides: [
        projectRepositoryProvider.overrideWithValue(repo),
      ]);
      container.listen(hasProjectsForGameProvider(_gameCode), (_, _) {});
      await container.pump();

      expect(container.read(hasProjectsForGameProvider(_gameCode)).hasError,
          isTrue);
    });
  });

  group('SelectedGlossaryLanguage notifier', () {
    late _MockSettingsService settings;

    setUp(() => settings = _MockSettingsService());

    test('build returns null when stored value is empty', () async {
      when(() => settings.getString(any())).thenAnswer((_) async => '');

      final container = makeContainer(overrides: [
        settingsServiceProvider.overrideWithValue(settings),
      ]);

      final value = await container
          .read(selectedGlossaryLanguageProvider(_gameCode).future);
      expect(value, isNull);
    });

    test('build returns stored language id', () async {
      when(() => settings.getString(any())).thenAnswer((_) async => 'lang-fr');

      final container = makeContainer(overrides: [
        settingsServiceProvider.overrideWithValue(settings),
      ]);

      final value = await container
          .read(selectedGlossaryLanguageProvider(_gameCode).future);
      expect(value, 'lang-fr');
    });

    test('setLanguageId writes and updates state', () async {
      when(() => settings.getString(any())).thenAnswer((_) async => '');
      when(() => settings.setString(any(), any()))
          .thenAnswer((_) async => const Ok(null));

      final container = makeContainer(overrides: [
        settingsServiceProvider.overrideWithValue(settings),
      ]);

      await container
          .read(selectedGlossaryLanguageProvider(_gameCode).future);
      final notifier = container
          .read(selectedGlossaryLanguageProvider(_gameCode).notifier);

      await notifier.setLanguageId(_gameCode, 'lang-de');
      expect(
        container.read(selectedGlossaryLanguageProvider(_gameCode)).value,
        'lang-de',
      );
      verify(() => settings.setString(
          'glossary_selected_language_$_gameCode', 'lang-de')).called(1);

      // null clears the persisted value (writes empty string).
      await notifier.setLanguageId(_gameCode, null);
      expect(
        container.read(selectedGlossaryLanguageProvider(_gameCode)).value,
        isNull,
      );
      verify(() => settings.setString(
          'glossary_selected_language_$_gameCode', '')).called(1);
    });
  });

  group('currentGlossary provider', () {
    test('returns null when no game is selected', () async {
      final container = makeContainer(overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
      ]);

      expect(await container.read(currentGlossaryProvider.future), isNull);
    });

    test('returns null when no language is chosen', () async {
      final container = makeContainer(overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(_game)),
        selectedGlossaryLanguageProvider(_gameCode)
            .overrideWith(() => _FakeSelectedGlossaryLanguage(null)),
      ]);

      expect(await container.read(currentGlossaryProvider.future), isNull);
    });

    test('resolves the glossary for (game, language)', () async {
      when(() => service.getGlossaryByGameAndLanguage(
            gameCode: any(named: 'gameCode'),
            targetLanguageId: any(named: 'targetLanguageId'),
          )).thenAnswer((_) async => Ok(_glossary('g1')));

      final container = makeContainer(overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(_game)),
        selectedGlossaryLanguageProvider(_gameCode)
            .overrideWith(() => _FakeSelectedGlossaryLanguage('lang-fr')),
      ]);

      final glossary = await container.read(currentGlossaryProvider.future);
      expect(glossary?.id, 'g1');
    });

    test('Err path surfaces error state', () async {
      when(() => service.getGlossaryByGameAndLanguage(
            gameCode: any(named: 'gameCode'),
            targetLanguageId: any(named: 'targetLanguageId'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer(overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(_game)),
        selectedGlossaryLanguageProvider(_gameCode)
            .overrideWith(() => _FakeSelectedGlossaryLanguage('lang-fr')),
      ]);
      container.listen(currentGlossaryProvider, (_, _) {});
      await pumpEventQueue();

      expect(container.read(currentGlossaryProvider).hasError, isTrue);
    });
  });

  group('glossaryEntries provider', () {
    test('Ok path returns entries', () async {
      when(() => service.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => Ok([_entry('e1')]));

      final container = makeContainer();
      final result = await container
          .read(glossaryEntriesProvider(glossaryId: _glossaryId).future);
      expect(result, hasLength(1));
    });

    test('Err path surfaces error state', () async {
      when(() => service.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      container.listen(
          glossaryEntriesProvider(glossaryId: _glossaryId), (_, _) {});
      await container.pump();

      expect(
          container
              .read(glossaryEntriesProvider(glossaryId: _glossaryId))
              .hasError,
          isTrue);
    });
  });

  group('glossarySearchResults provider', () {
    test('empty query short-circuits to []', () async {
      final container = makeContainer();
      final result =
          await container.read(glossarySearchResultsProvider(query: '').future);
      expect(result, isEmpty);
      verifyNever(() => service.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          ));
    });

    test('non-empty query Ok path calls service', () async {
      when(() => service.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => Ok([_entry('e1')]));

      final container = makeContainer();
      final result = await container
          .read(glossarySearchResultsProvider(query: 'Sword').future);
      expect(result, hasLength(1));
    });

    test('non-empty query Err path surfaces error state', () async {
      when(() => service.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      container.listen(
          glossarySearchResultsProvider(query: 'Sword'), (_, _) {});
      await container.pump();

      expect(
          container
              .read(glossarySearchResultsProvider(query: 'Sword'))
              .hasError,
          isTrue);
    });
  });

  group('glossaryStatistics provider', () {
    test('Ok path maps stats', () async {
      when(() => service.getGlossaryStats(any())).thenAnswer(
          (_) async => const Ok({'totalEntries': 3}));

      final container = makeContainer();
      final stats =
          await container.read(glossaryStatisticsProvider(_glossaryId).future);
      expect(stats.totalEntries, 3);
    });

    test('Err path surfaces error state', () async {
      when(() => service.getGlossaryStats(any()))
          .thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      container.listen(glossaryStatisticsProvider(_glossaryId), (_, _) {});
      await container.pump();

      expect(container.read(glossaryStatisticsProvider(_glossaryId)).hasError,
          isTrue);
    });
  });

  group('GlossaryEntryEditor save', () {
    test('edit then clear sets and resets state', () {
      final container = makeContainer();
      final notifier = container.read(glossaryEntryEditorProvider.notifier);

      notifier.edit(_entry('e1'));
      expect(container.read(glossaryEntryEditorProvider)?.id, 'e1');

      notifier.clear();
      expect(container.read(glossaryEntryEditorProvider), isNull);
    });

    test('update existing entry Ok clears state', () async {
      when(() => service.updateEntry(any()))
          .thenAnswer((_) async => Ok(_entry('e1')));

      final container = makeContainer();
      final notifier = container.read(glossaryEntryEditorProvider.notifier);
      notifier.edit(_entry('e1'));

      await notifier.save(
        glossaryId: _glossaryId,
        targetLanguageCode: 'fr',
        sourceTerm: 'Sword',
        targetTerm: 'Épée',
        existingEntry: _entry('e1'),
      );

      verify(() => service.updateEntry(any())).called(1);
      expect(container.read(glossaryEntryEditorProvider), isNull);
    });

    test('update existing entry Err throws', () async {
      when(() => service.updateEntry(any()))
          .thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryEntryEditorProvider.notifier);

      await expectLater(
        notifier.save(
          glossaryId: _glossaryId,
          targetLanguageCode: 'fr',
          sourceTerm: 'Sword',
          targetTerm: 'Épée',
          existingEntry: _entry('e1'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('add new entry Ok emits activity and clears state', () async {
      final logger = _MockActivityLogger();
      when(() => logger.log(any(),
          projectId: any(named: 'projectId'),
          gameCode: any(named: 'gameCode'),
          payload: any(named: 'payload'))).thenAnswer((_) async {});
      when(() => service.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => Ok(_entry('new')));

      final container = makeContainer(overrides: [
        activityLoggerProvider.overrideWithValue(logger),
      ]);
      final notifier = container.read(glossaryEntryEditorProvider.notifier);

      await notifier.save(
        glossaryId: _glossaryId,
        targetLanguageCode: 'fr',
        sourceTerm: 'Sword',
        targetTerm: 'Épée',
      );

      verify(() => service.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).called(1);
      verify(() => logger.log(ActivityEventType.glossaryEnriched,
          payload: any(named: 'payload'))).called(1);
      expect(container.read(glossaryEntryEditorProvider), isNull);
    });

    test('add new entry Err throws', () async {
      when(() => service.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryEntryEditorProvider.notifier);

      await expectLater(
        notifier.save(
          glossaryId: _glossaryId,
          targetLanguageCode: 'fr',
          sourceTerm: 'Sword',
          targetTerm: 'Épée',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('GlossaryFilterState notifier', () {
    test('setTargetLanguage, setSearchText, reset', () {
      final container = makeContainer();
      final notifier = container.read(glossaryFilterStateProvider.notifier);

      notifier.setTargetLanguage('fr');
      expect(container.read(glossaryFilterStateProvider).targetLanguage, 'fr');

      notifier.setSearchText('sword');
      expect(container.read(glossaryFilterStateProvider).searchText, 'sword');

      notifier.reset();
      expect(container.read(glossaryFilterStateProvider).targetLanguage, isNull);
      expect(container.read(glossaryFilterStateProvider).searchText, '');
    });
  });

  group('GlossaryPageState notifier', () {
    test('setPage, nextPage, previousPage guard, reset', () {
      final container = makeContainer();
      final notifier = container.read(glossaryPageStateProvider.notifier);

      expect(container.read(glossaryPageStateProvider), 1);

      notifier.setPage(5);
      expect(container.read(glossaryPageStateProvider), 5);

      notifier.nextPage();
      expect(container.read(glossaryPageStateProvider), 6);

      notifier.previousPage();
      expect(container.read(glossaryPageStateProvider), 5);

      notifier.reset();
      expect(container.read(glossaryPageStateProvider), 1);

      // previousPage at page 1 is guarded (state stays at 1).
      notifier.previousPage();
      expect(container.read(glossaryPageStateProvider), 1);
    });
  });

  group('GlossaryImportState notifier', () {
    late _MockActivityLogger logger;

    setUp(() {
      logger = _MockActivityLogger();
      when(() => logger.log(any(),
          projectId: any(named: 'projectId'),
          gameCode: any(named: 'gameCode'),
          payload: any(named: 'payload'))).thenAnswer((_) async {});
    });

    test('importCsv Ok sets AsyncData(ImportResult) and emits activity',
        () async {
      when(() => service.importFromCsv(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            skipDuplicates: any(named: 'skipDuplicates'),
          )).thenAnswer((_) async => const Ok(7));

      final container = makeContainer(overrides: [
        activityLoggerProvider.overrideWithValue(logger),
      ]);
      final notifier = container.read(glossaryImportStateProvider.notifier);

      await notifier.importCsv(
        glossaryId: _glossaryId,
        filePath: 'C:/in.csv',
        targetLanguageCode: 'fr',
      );

      final state = container.read(glossaryImportStateProvider);
      expect(state.value?.imported, 7);
      verify(() => logger.log(ActivityEventType.glossaryEnriched,
          payload: any(named: 'payload'))).called(1);
    });

    test('importCsv Err sets AsyncError', () async {
      when(() => service.importFromCsv(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            skipDuplicates: any(named: 'skipDuplicates'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryImportStateProvider.notifier);

      await notifier.importCsv(
        glossaryId: _glossaryId,
        filePath: 'C:/in.csv',
        targetLanguageCode: 'fr',
      );

      expect(container.read(glossaryImportStateProvider).hasError, isTrue);
    });

    test('importTbx Ok sets AsyncData(ImportResult)', () async {
      when(() => service.importFromTbx(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((_) async => const Ok(3));

      final container = makeContainer(overrides: [
        activityLoggerProvider.overrideWithValue(logger),
      ]);
      final notifier = container.read(glossaryImportStateProvider.notifier);

      await notifier.importTbx(glossaryId: _glossaryId, filePath: 'C:/in.tbx');

      expect(container.read(glossaryImportStateProvider).value?.imported, 3);
    });

    test('importTbx Err sets AsyncError', () async {
      when(() => service.importFromTbx(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryImportStateProvider.notifier);

      await notifier.importTbx(glossaryId: _glossaryId, filePath: 'C:/in.tbx');

      expect(container.read(glossaryImportStateProvider).hasError, isTrue);
    });

    test('importExcel Ok sets AsyncData(ImportResult)', () async {
      when(() => service.importFromExcel(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sheetName: any(named: 'sheetName'),
            skipDuplicates: any(named: 'skipDuplicates'),
          )).thenAnswer((_) async => const Ok(2));

      final container = makeContainer(overrides: [
        activityLoggerProvider.overrideWithValue(logger),
      ]);
      final notifier = container.read(glossaryImportStateProvider.notifier);

      await notifier.importExcel(
        glossaryId: _glossaryId,
        filePath: 'C:/in.xlsx',
        targetLanguageCode: 'fr',
      );

      expect(container.read(glossaryImportStateProvider).value?.imported, 2);
    });

    test('importExcel Err sets AsyncError', () async {
      when(() => service.importFromExcel(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sheetName: any(named: 'sheetName'),
            skipDuplicates: any(named: 'skipDuplicates'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryImportStateProvider.notifier);

      await notifier.importExcel(
        glossaryId: _glossaryId,
        filePath: 'C:/in.xlsx',
        targetLanguageCode: 'fr',
      );

      expect(container.read(glossaryImportStateProvider).hasError, isTrue);
    });

    test('reset returns AsyncData(null)', () {
      final container = makeContainer();
      final notifier = container.read(glossaryImportStateProvider.notifier);
      notifier.reset();
      expect(container.read(glossaryImportStateProvider).value, isNull);
    });
  });

  group('GlossaryExportState notifier', () {
    test('exportCsv Ok sets AsyncData(ExportResult)', () async {
      when(() => service.exportToCsv(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Ok(5));

      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);

      await notifier.exportCsv(glossaryId: _glossaryId, filePath: 'C:/out.csv');

      final state = container.read(glossaryExportStateProvider);
      expect(state.value?.entriesExported, 5);
      expect(state.value?.filePath, 'C:/out.csv');
    });

    test('exportCsv Err sets AsyncError', () async {
      when(() => service.exportToCsv(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);

      await notifier.exportCsv(glossaryId: _glossaryId, filePath: 'C:/out.csv');

      expect(container.read(glossaryExportStateProvider).hasError, isTrue);
    });

    test('exportTbx Ok sets AsyncData(ExportResult)', () async {
      when(() => service.exportToTbx(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((_) async => const Ok(4));

      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);

      await notifier.exportTbx(glossaryId: _glossaryId, filePath: 'C:/out.tbx');

      expect(container.read(glossaryExportStateProvider).value?.entriesExported,
          4);
    });

    test('exportTbx Err sets AsyncError', () async {
      when(() => service.exportToTbx(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);

      await notifier.exportTbx(glossaryId: _glossaryId, filePath: 'C:/out.tbx');

      expect(container.read(glossaryExportStateProvider).hasError, isTrue);
    });

    test('exportExcel Ok sets AsyncData(ExportResult)', () async {
      when(() => service.exportToExcel(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Ok(6));

      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);

      await notifier.exportExcel(
          glossaryId: _glossaryId, filePath: 'C:/out.xlsx');

      expect(container.read(glossaryExportStateProvider).value?.entriesExported,
          6);
    });

    test('exportExcel Err sets AsyncError', () async {
      when(() => service.exportToExcel(
            glossaryId: any(named: 'glossaryId'),
            filePath: any(named: 'filePath'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Err(_err));

      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);

      await notifier.exportExcel(
          glossaryId: _glossaryId, filePath: 'C:/out.xlsx');

      expect(container.read(glossaryExportStateProvider).hasError, isTrue);
    });

    test('reset returns AsyncData(null)', () {
      final container = makeContainer();
      final notifier = container.read(glossaryExportStateProvider.notifier);
      notifier.reset();
      expect(container.read(glossaryExportStateProvider).value, isNull);
    });
  });
}
