import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_service_impl.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';

class _MockGlossaryRepo extends Mock implements GlossaryRepository {}

Glossary _glossary(String id, String name) => Glossary(
      id: id,
      name: name,
      gameCode: 'wh3',
      targetLanguageId: 'fr-id',
      createdAt: 0,
      updatedAt: 0,
    );

GlossaryEntry _entry(
  String id,
  String glossaryId,
  String source,
  String target, {
  String lang = 'fr',
}) =>
    GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      targetLanguageCode: lang,
      sourceTerm: source,
      targetTerm: target,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_glossary('f', 'f'));
    registerFallbackValue(_entry('f', 'g', 's', 't'));
  });

  late _MockGlossaryRepo repo;
  late GlossaryServiceImpl service;

  setUp(() async {
    // A glossary delegate constructs GlossaryImportService, which resolves
    // ILoggingService from the ServiceLocator — register it for tests.
    await TestBootstrap.registerFakes();
    repo = _MockGlossaryRepo();
    service = GlossaryServiceImpl(repository: repo, logger: FakeLogger());
  });

  group('createGlossary', () {
    test('rejects an empty name', () async {
      final r = await service.createGlossary(
          name: '   ', gameCode: 'wh3', targetLanguageId: 'fr-id');
      expect(r.unwrapErr(), isA<InvalidGlossaryDataException>());
    });

    test('rejects a duplicate name', () async {
      when(() => repo.getByName('Dup')).thenAnswer((_) async => _glossary('x', 'Dup'));

      final r = await service.createGlossary(
          name: 'Dup', gameCode: 'wh3', targetLanguageId: 'fr-id');
      expect(r.unwrapErr(), isA<GlossaryAlreadyExistsException>());
    });

    test('creates and persists a new glossary', () async {
      when(() => repo.getByName(any())).thenAnswer((_) async => null);
      when(() => repo.insertGlossary(any())).thenAnswer((_) async {});

      final r = await service.createGlossary(
          name: '  New  ', gameCode: 'wh3', targetLanguageId: 'fr-id');

      expect(r.isOk, isTrue);
      expect(r.unwrap().name, 'New'); // trimmed
      verify(() => repo.insertGlossary(any())).called(1);
    });
  });

  group('getGlossaryById / getAllGlossaries', () {
    test('returns NotFound when missing', () async {
      when(() => repo.getGlossaryById('x')).thenAnswer((_) async => null);
      expect((await service.getGlossaryById('x')).unwrapErr(),
          isA<GlossaryNotFoundException>());
    });

    test('returns the glossary when present', () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => _glossary('g', 'G'));
      expect((await service.getGlossaryById('g')).unwrap().id, 'g');
    });

    test('lists all glossaries', () async {
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => [_glossary('a', 'A'), _glossary('b', 'B')]);
      expect((await service.getAllGlossaries()).unwrap(), hasLength(2));
    });
  });

  group('updateGlossary', () {
    test('returns NotFound when the glossary does not exist', () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => null);
      expect((await service.updateGlossary(_glossary('g', 'G'))).unwrapErr(),
          isA<GlossaryNotFoundException>());
    });

    test('rejects a rename that collides with another glossary', () async {
      when(() => repo.getGlossaryById('g'))
          .thenAnswer((_) async => _glossary('g', 'Old'));
      when(() => repo.getByName('New'))
          .thenAnswer((_) async => _glossary('other', 'New'));

      final r = await service.updateGlossary(_glossary('g', 'New'));
      expect(r.unwrapErr(), isA<GlossaryAlreadyExistsException>());
    });

    test('updates when valid', () async {
      when(() => repo.getGlossaryById('g'))
          .thenAnswer((_) async => _glossary('g', 'Same'));
      when(() => repo.updateGlossary(any())).thenAnswer((_) async {});

      final r = await service.updateGlossary(_glossary('g', 'Same'));
      expect(r.isOk, isTrue);
      verify(() => repo.updateGlossary(any())).called(1);
    });
  });

  group('deleteGlossary', () {
    test('returns NotFound when missing', () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => null);
      expect((await service.deleteGlossary('g')).unwrapErr(),
          isA<GlossaryNotFoundException>());
    });

    test('deletes when present', () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => _glossary('g', 'G'));
      when(() => repo.deleteGlossary('g')).thenAnswer((_) async {});

      expect((await service.deleteGlossary('g')).isOk, isTrue);
      verify(() => repo.deleteGlossary('g')).called(1);
    });
  });

  group('addEntry', () {
    setUp(() {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => _glossary('g', 'G'));
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => null);
      when(() => repo.insertEntry(any())).thenAnswer((_) async {});
    });

    test('returns NotFound when the glossary is missing', () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => null);
      final r = await service.addEntry(
          glossaryId: 'g', targetLanguageCode: 'fr', sourceTerm: 's', targetTerm: 't');
      expect(r.unwrapErr(), isA<GlossaryNotFoundException>());
    });

    test('rejects empty source or target terms', () async {
      final r = await service.addEntry(
          glossaryId: 'g', targetLanguageCode: 'fr', sourceTerm: '  ', targetTerm: 't');
      expect(r.unwrapErr(), isA<InvalidGlossaryDataException>());
    });

    test('rejects a duplicate entry', () async {
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry('d', 'g', 's', 't'));

      final r = await service.addEntry(
          glossaryId: 'g', targetLanguageCode: 'fr', sourceTerm: 's', targetTerm: 't');
      expect(r.unwrapErr(), isA<DuplicateGlossaryEntryException>());
    });

    test('inserts a trimmed entry on success', () async {
      final r = await service.addEntry(
          glossaryId: 'g',
          targetLanguageCode: 'fr',
          sourceTerm: '  Empire  ',
          targetTerm: '  Empire FR  ');

      expect(r.isOk, isTrue);
      final captured =
          verify(() => repo.insertEntry(captureAny())).captured.single as GlossaryEntry;
      expect(captured.sourceTerm, 'Empire');
      expect(captured.targetTerm, 'Empire FR');
    });
  });

  group('entry get/update/delete', () {
    test('getEntryById returns NotFound when missing', () async {
      when(() => repo.getEntryById('e')).thenAnswer((_) async => null);
      expect((await service.getEntryById('e')).unwrapErr(),
          isA<GlossaryEntryNotFoundException>());
    });

    test('updateEntry persists when present', () async {
      when(() => repo.getEntryById('e'))
          .thenAnswer((_) async => _entry('e', 'g', 's', 't'));
      when(() => repo.updateEntry(any())).thenAnswer((_) async {});

      expect((await service.updateEntry(_entry('e', 'g', 's2', 't2'))).isOk, isTrue);
      verify(() => repo.updateEntry(any())).called(1);
    });

    test('deleteEntry returns NotFound when missing', () async {
      when(() => repo.getEntryById('e')).thenAnswer((_) async => null);
      expect((await service.deleteEntry('e')).unwrapErr(),
          isA<GlossaryEntryNotFoundException>());
    });

    test('deleteEntries is a no-op for an empty list', () async {
      expect((await service.deleteEntries([])).isOk, isTrue);
      verifyNever(() => repo.getEntryById(any()));
    });
  });

  group('validateGlossary', () {
    test('returns NotFound when the glossary is missing', () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => null);
      expect((await service.validateGlossary('g')).unwrapErr(),
          isA<GlossaryNotFoundException>());
    });

    test('reports empty terms, duplicates, and conflicting translations',
        () async {
      when(() => repo.getGlossaryById('g')).thenAnswer((_) async => _glossary('g', 'G'));
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            _entry('1', 'g', '  ', 'empty-source'),
            _entry('2', 'g', 'Lord', 'Seigneur'),
            _entry('3', 'g', 'lord', 'Maitre'), // dup key + conflicting target
          ]);

      final errors = (await service.validateGlossary('g')).unwrap();

      expect(errors.any((e) => e.contains('Empty source term')), isTrue);
      expect(errors.any((e) => e.contains('Duplicate term')), isTrue);
      expect(errors.any((e) => e.contains('Conflicting translations')), isTrue);
    });
  });

  group('searchEntries', () {
    test('delegates to the repository', () async {
      when(() => repo.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry('1', 'g', 's', 't')]);

      expect((await service.searchEntries(query: 'x')).unwrap(), hasLength(1));
    });
  });
}
