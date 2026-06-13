import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_service_impl.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

// Coverage-focused characterisation tests for GlossaryServiceImpl.
//
// GlossaryRepository is a concrete class but mocktail can still subclass it.
// The impl constructs its delegate sub-services (import/export, DeepL, matching,
// statistics) from the mock repository at construction time; none of those
// constructors touch the database, so a bare mock repo is enough. The logger is
// injected directly (no GetIt), so NoopLogger() keeps the suite silent.
//
// Methods that the impl delegates to GlossaryMatchingService /
// GlossaryStatisticsService are driven through the (mocked) repository methods
// those services call internally, exercising the forwarding lines + happy/error
// paths without any real DB.

class _MockRepo extends Mock implements GlossaryRepository {}

Glossary _glossary({
  String id = 'g1',
  String name = 'Gloss',
  String gameCode = 'wh3',
  String targetLanguageId = 'lang_fr',
  int entryCount = 0,
}) =>
    Glossary(
      id: id,
      name: name,
      gameCode: gameCode,
      targetLanguageId: targetLanguageId,
      entryCount: entryCount,
      createdAt: 1,
      updatedAt: 2,
    );

GlossaryEntry _entry({
  String id = 'e1',
  String glossaryId = 'g1',
  String targetLanguageCode = 'fr',
  String sourceTerm = 'Sword',
  String targetTerm = 'Epee',
  bool caseSensitive = false,
  String? notes,
}) =>
    GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      targetLanguageCode: targetLanguageCode,
      sourceTerm: sourceTerm,
      targetTerm: targetTerm,
      caseSensitive: caseSensitive,
      notes: notes,
      createdAt: 1,
      updatedAt: 2,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_glossary());
    registerFallbackValue(_entry());
  });

  late _MockRepo repo;
  late GlossaryServiceImpl service;

  setUp(() async {
    // The impl's delegate sub-services fall back to ServiceLocator for their
    // own loggers at construction time, so install baseline fakes first.
    await TestBootstrap.registerFakes();
    repo = _MockRepo();
    service = GlossaryServiceImpl(repository: repo, logger: NoopLogger());
  });

  // ==========================================================================
  // createGlossary
  // ==========================================================================
  group('createGlossary', () {
    test('Ok: creates a glossary when name is unique', () async {
      // Impl checks duplicates against the raw (untrimmed) name.
      when(() => repo.getByName('  New  ')).thenAnswer((_) async => null);
      when(() => repo.insertGlossary(any())).thenAnswer((_) async {});

      final result = await service.createGlossary(
        name: '  New  ',
        description: '  desc  ',
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
      );

      expect(result.isOk, isTrue);
      expect(result.value.name, 'New');
      expect(result.value.description, 'desc');
      verify(() => repo.insertGlossary(any())).called(1);
    });

    test('Err: empty name returns InvalidGlossaryDataException', () async {
      final result = await service.createGlossary(
        name: '   ',
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<InvalidGlossaryDataException>());
      verifyNever(() => repo.insertGlossary(any()));
    });

    test('Err: duplicate name returns GlossaryAlreadyExistsException', () async {
      when(() => repo.getByName('Dup'))
          .thenAnswer((_) async => _glossary(name: 'Dup'));

      final result = await service.createGlossary(
        name: 'Dup',
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<GlossaryAlreadyExistsException>());
    });

    test('Err: repository throw maps to GlossaryDatabaseException', () async {
      when(() => repo.getByName(any())).thenThrow(Exception('boom'));

      final result = await service.createGlossary(
        name: 'X',
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // getGlossaryById
  // ==========================================================================
  group('getGlossaryById', () {
    test('Ok', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      final result = await service.getGlossaryById('g1');
      expect(result.isOk, isTrue);
      expect(result.value.id, 'g1');
    });

    test('Err: not found', () async {
      when(() => repo.getGlossaryById('missing'))
          .thenAnswer((_) async => null);
      final result = await service.getGlossaryById('missing');
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getGlossaryById(any())).thenThrow(Exception('x'));
      final result = await service.getGlossaryById('g1');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // getAllGlossaries
  // ==========================================================================
  group('getAllGlossaries', () {
    test('Ok', () async {
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => [_glossary()]);
      final result = await service.getAllGlossaries(gameCode: 'wh3');
      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('Err: repo throws', () async {
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenThrow(Exception('x'));
      final result = await service.getAllGlossaries();
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // getGlossaryByGameAndLanguage
  // ==========================================================================
  group('getGlossaryByGameAndLanguage', () {
    test('Ok: returns matching glossary', () async {
      when(() => repo.getGlossaryByGameAndLanguage(
            gameCode: 'wh3',
            targetLanguageId: 'lang_fr',
          )).thenAnswer((_) async => _glossary());
      final result = await service.getGlossaryByGameAndLanguage(
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
      );
      expect(result.isOk, isTrue);
      expect(result.value, isNotNull);
    });

    test('Ok: returns null when absent', () async {
      when(() => repo.getGlossaryByGameAndLanguage(
            gameCode: any(named: 'gameCode'),
            targetLanguageId: any(named: 'targetLanguageId'),
          )).thenAnswer((_) async => null);
      final result = await service.getGlossaryByGameAndLanguage(
        gameCode: 'wh3',
        targetLanguageId: 'lang_de',
      );
      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });

    test('Err: repo throws', () async {
      when(() => repo.getGlossaryByGameAndLanguage(
            gameCode: any(named: 'gameCode'),
            targetLanguageId: any(named: 'targetLanguageId'),
          )).thenThrow(Exception('x'));
      final result = await service.getGlossaryByGameAndLanguage(
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
      );
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // updateGlossary
  // ==========================================================================
  group('updateGlossary', () {
    test('Ok: same name skips conflict check', () async {
      final g = _glossary(name: 'Same');
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => g);
      when(() => repo.updateGlossary(any())).thenAnswer((_) async {});

      final result = await service.updateGlossary(g);
      expect(result.isOk, isTrue);
      verifyNever(() => repo.getByName(any()));
    });

    test('Ok: name changed with no conflict', () async {
      final existing = _glossary(name: 'Old');
      final updated = _glossary(name: 'New');
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => existing);
      when(() => repo.getByName('New')).thenAnswer((_) async => null);
      when(() => repo.updateGlossary(any())).thenAnswer((_) async {});

      final result = await service.updateGlossary(updated);
      expect(result.isOk, isTrue);
    });

    test('Ok: name conflict on same id is allowed', () async {
      final existing = _glossary(name: 'Old');
      final updated = _glossary(name: 'New');
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => existing);
      // Conflict resolves to the same id => allowed.
      when(() => repo.getByName('New'))
          .thenAnswer((_) async => _glossary(id: 'g1', name: 'New'));
      when(() => repo.updateGlossary(any())).thenAnswer((_) async {});

      final result = await service.updateGlossary(updated);
      expect(result.isOk, isTrue);
    });

    test('Err: not found', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.updateGlossary(_glossary());
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('Err: name conflict with different id', () async {
      final existing = _glossary(name: 'Old');
      final updated = _glossary(name: 'New');
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => existing);
      when(() => repo.getByName('New'))
          .thenAnswer((_) async => _glossary(id: 'other', name: 'New'));

      final result = await service.updateGlossary(updated);
      expect(result.error, isA<GlossaryAlreadyExistsException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getGlossaryById(any())).thenThrow(Exception('x'));
      final result = await service.updateGlossary(_glossary());
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // deleteGlossary
  // ==========================================================================
  group('deleteGlossary', () {
    test('Ok', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.deleteGlossary('g1')).thenAnswer((_) async {});
      final result = await service.deleteGlossary('g1');
      expect(result.isOk, isTrue);
    });

    test('Err: not found', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.deleteGlossary('g1');
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getGlossaryById(any())).thenThrow(Exception('x'));
      final result = await service.deleteGlossary('g1');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // addEntry
  // ==========================================================================
  group('addEntry', () {
    void stubGlossaryExists() {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
    }

    test('Ok: adds entry, trimming notes', () async {
      stubGlossaryExists();
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => null);
      when(() => repo.insertEntry(any())).thenAnswer((_) async {});

      final result = await service.addEntry(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
        sourceTerm: '  Sword  ',
        targetTerm: '  Epee  ',
        notes: '  note  ',
      );

      expect(result.isOk, isTrue);
      expect(result.value.sourceTerm, 'Sword');
      expect(result.value.targetTerm, 'Epee');
      expect(result.value.notes, 'note');
    });

    test('Ok: blank notes become null', () async {
      stubGlossaryExists();
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => null);
      when(() => repo.insertEntry(any())).thenAnswer((_) async {});

      final result = await service.addEntry(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Sword',
        targetTerm: 'Epee',
        notes: '   ',
      );

      expect(result.isOk, isTrue);
      expect(result.value.notes, isNull);
    });

    test('Err: glossary not found', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.addEntry(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Sword',
        targetTerm: 'Epee',
      );
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('Err: empty terms', () async {
      stubGlossaryExists();
      final result = await service.addEntry(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
        sourceTerm: '   ',
        targetTerm: 'Epee',
      );
      expect(result.error, isA<InvalidGlossaryDataException>());
    });

    test('Err: duplicate entry', () async {
      stubGlossaryExists();
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry());
      final result = await service.addEntry(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Sword',
        targetTerm: 'Epee',
      );
      expect(result.error, isA<DuplicateGlossaryEntryException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getGlossaryById(any())).thenThrow(Exception('x'));
      final result = await service.addEntry(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
        sourceTerm: 'Sword',
        targetTerm: 'Epee',
      );
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // getEntryById
  // ==========================================================================
  group('getEntryById', () {
    test('Ok', () async {
      when(() => repo.getEntryById('e1')).thenAnswer((_) async => _entry());
      final result = await service.getEntryById('e1');
      expect(result.isOk, isTrue);
    });

    test('Err: not found', () async {
      when(() => repo.getEntryById('e1')).thenAnswer((_) async => null);
      final result = await service.getEntryById('e1');
      expect(result.error, isA<GlossaryEntryNotFoundException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getEntryById(any())).thenThrow(Exception('x'));
      final result = await service.getEntryById('e1');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // getEntriesByGlossary
  // ==========================================================================
  group('getEntriesByGlossary', () {
    test('Ok', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      final result = await service.getEntriesByGlossary(
        glossaryId: 'g1',
        targetLanguageCode: 'fr',
      );
      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('Err: repo throws', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenThrow(Exception('x'));
      final result = await service.getEntriesByGlossary(glossaryId: 'g1');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // updateEntry
  // ==========================================================================
  group('updateEntry', () {
    test('Ok', () async {
      when(() => repo.getEntryById('e1')).thenAnswer((_) async => _entry());
      when(() => repo.updateEntry(any())).thenAnswer((_) async {});
      final result = await service.updateEntry(_entry());
      expect(result.isOk, isTrue);
    });

    test('Err: not found', () async {
      when(() => repo.getEntryById('e1')).thenAnswer((_) async => null);
      final result = await service.updateEntry(_entry());
      expect(result.error, isA<GlossaryEntryNotFoundException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getEntryById(any())).thenThrow(Exception('x'));
      final result = await service.updateEntry(_entry());
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // deleteEntry
  // ==========================================================================
  group('deleteEntry', () {
    test('Ok', () async {
      when(() => repo.getEntryById('e1')).thenAnswer((_) async => _entry());
      when(() => repo.deleteEntry('e1')).thenAnswer((_) async {});
      final result = await service.deleteEntry('e1');
      expect(result.isOk, isTrue);
    });

    test('Err: not found', () async {
      when(() => repo.getEntryById('e1')).thenAnswer((_) async => null);
      final result = await service.deleteEntry('e1');
      expect(result.error, isA<GlossaryEntryNotFoundException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getEntryById(any())).thenThrow(Exception('x'));
      final result = await service.deleteEntry('e1');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // deleteEntries
  // ==========================================================================
  group('deleteEntries', () {
    test('Ok: empty list short-circuits', () async {
      final result = await service.deleteEntries(const []);
      expect(result.isOk, isTrue);
      verifyNever(() => repo.getEntryById(any()));
    });

    test('Ok: deletes found entries, skips missing', () async {
      when(() => repo.getEntryById('e1'))
          .thenAnswer((_) async => _entry(id: 'e1', glossaryId: 'g1'));
      when(() => repo.getEntryById('e2'))
          .thenAnswer((_) async => null); // missing => skipped
      when(() => repo.deleteEntry(any())).thenAnswer((_) async {});

      final result = await service.deleteEntries(['e1', 'e2']);
      expect(result.isOk, isTrue);
      verify(() => repo.deleteEntry('e1')).called(1);
      verifyNever(() => repo.deleteEntry('e2'));
    });

    test('Err: repo throws', () async {
      when(() => repo.getEntryById(any())).thenThrow(Exception('x'));
      final result = await service.deleteEntries(['e1']);
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // searchEntries
  // ==========================================================================
  group('searchEntries', () {
    test('Ok: returns matches', () async {
      when(() => repo.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [_entry()]);
      final result = await service.searchEntries(
        query: 'Sw',
        glossaryIds: ['g1'],
        targetLanguageCode: 'fr',
      );
      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('Ok: empty results', () async {
      when(() => repo.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => []);
      final result = await service.searchEntries(query: 'zzz');
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('Err: repo throws', () async {
      when(() => repo.searchEntries(
            query: any(named: 'query'),
            glossaryIds: any(named: 'glossaryIds'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenThrow(Exception('x'));
      final result = await service.searchEntries(query: 'q');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // validateGlossary
  // ==========================================================================
  group('validateGlossary', () {
    test('Ok: no errors for clean glossary', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            _entry(id: 'a', sourceTerm: 'Sword', targetTerm: 'Epee'),
          ]);
      final result = await service.validateGlossary('g1');
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('Ok: detects empty terms, duplicates and conflicts', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            // empty source term
            _entry(id: 'a', sourceTerm: '  ', targetTerm: 'X'),
            // empty target term
            _entry(id: 'b', sourceTerm: 'Y', targetTerm: '  '),
            // duplicate + conflicting translations of 'Sword'
            _entry(id: 'c', sourceTerm: 'Sword', targetTerm: 'Epee'),
            _entry(id: 'd', sourceTerm: 'sword', targetTerm: 'Glaive'),
          ]);
      final result = await service.validateGlossary('g1');
      expect(result.isOk, isTrue);
      final errors = result.value;
      expect(errors.any((e) => e.contains('Empty source term')), isTrue);
      expect(errors.any((e) => e.contains('Empty target term')), isTrue);
      expect(errors.any((e) => e.contains('Duplicate term')), isTrue);
      expect(errors.any((e) => e.contains('Conflicting translations')), isTrue);
    });

    test('Err: glossary not found', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.validateGlossary('g1');
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('Err: repo throws', () async {
      when(() => repo.getGlossaryById(any())).thenThrow(Exception('x'));
      final result = await service.validateGlossary('g1');
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // checkConsistency (delegates to findMatchingTerms via matching service)
  // ==========================================================================
  group('checkConsistency', () {
    test('Ok: reports missing translation in target', () async {
      // Single glossary with one entry that matches the source text.
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => [_glossary()]);
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async =>
              [_entry(sourceTerm: 'Sword', targetTerm: 'Epee')]);

      final result = await service.checkConsistency(
        sourceText: 'The Sword is here',
        targetText: 'Rien ici', // no "Epee" => inconsistency
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
      expect(result.value.first, contains('Sword'));
    });

    test('Ok: consistent when target contains term', () async {
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => [_glossary()]);
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async =>
              [_entry(sourceTerm: 'Sword', targetTerm: 'Epee')]);

      final result = await service.checkConsistency(
        sourceText: 'The Sword',
        targetText: 'Une Epee',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('Err: propagates matching error', () async {
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenThrow(Exception('x'));
      final result = await service.checkConsistency(
        sourceText: 'The Sword',
        targetText: 'X',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );
      expect(result.isErr, isTrue);
      expect(result.error, isA<GlossaryDatabaseException>());
    });
  });

  // ==========================================================================
  // findMatchingTerms / applySubstitutions delegation
  // ==========================================================================
  group('matching delegation', () {
    test('findMatchingTerms Ok via explicit glossary ids', () async {
      when(() => repo.getGlossariesByIds(['g1']))
          .thenAnswer((_) async => [_glossary()]);
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async =>
              [_entry(sourceTerm: 'Sword', targetTerm: 'Epee')]);

      final result = await service.findMatchingTerms(
        sourceText: 'The Sword',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
        glossaryIds: ['g1'],
      );
      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('applySubstitutions Ok increments usage', () async {
      when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
          .thenAnswer((_) async => [_glossary()]);
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async =>
              [_entry(sourceTerm: 'Sword', targetTerm: 'Epee')]);
      when(() => repo.incrementUsageCount(any())).thenAnswer((_) async {});

      final result = await service.applySubstitutions(
        sourceText: 'The Sword',
        targetText: 'Une arme',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );
      expect(result.isOk, isTrue);
    });
  });

  // ==========================================================================
  // getGlossaryStats delegation
  // ==========================================================================
  group('getGlossaryStats', () {
    test('Ok: computes statistics', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => _glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            _entry(id: 'a', sourceTerm: 'Sword', targetTerm: 'Epee'),
            _entry(id: 'b', sourceTerm: 'sword', targetTerm: 'Glaive'),
          ]);
      when(() => repo.getUsageStats('g1')).thenAnswer((_) async => {
            'usedCount': 1,
            'unusedCount': 1,
            'totalUsage': 3,
          });

      final result = await service.getGlossaryStats('g1');
      expect(result.isOk, isTrue);
      expect(result.value['totalEntries'], 2);
      expect(result.value['duplicatesDetected'], 1);
    });

    test('Err: glossary not found', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.getGlossaryStats('g1');
      expect(result.error, isA<GlossaryNotFoundException>());
    });
  });

  // ==========================================================================
  // Import/Export delegation
  //
  // These methods forward to GlossaryImportExportService. We drive only the
  // forwarding lines through cheap, deterministic paths: imports short-circuit
  // on a missing glossary (no file IO), and CSV export writes an empty file to
  // a temp dir.
  // ==========================================================================
  group('import/export delegation', () {
    test('importFromCsv forwards (missing glossary => Err)', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.importFromCsv(
        glossaryId: 'g1',
        filePath: 'nope.csv',
        targetLanguageCode: 'fr',
      );
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('importFromTbx forwards (missing glossary => Err)', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result =
          await service.importFromTbx(glossaryId: 'g1', filePath: 'nope.tbx');
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('importFromExcel forwards (missing glossary => Err)', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result = await service.importFromExcel(
        glossaryId: 'g1',
        filePath: 'nope.xlsx',
        targetLanguageCode: 'fr',
      );
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('exportToTbx forwards (missing glossary => Err)', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result =
          await service.exportToTbx(glossaryId: 'g1', filePath: 'out.tbx');
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('exportToExcel forwards (missing glossary => Err)', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final result =
          await service.exportToExcel(glossaryId: 'g1', filePath: 'out.xlsx');
      expect(result.error, isA<GlossaryNotFoundException>());
    });

    test('exportToCsv forwards (writes empty export)', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => <GlossaryEntry>[]);

      final dir = await Directory.systemTemp.createTemp('glx_csv');
      addTearDown(() => dir.delete(recursive: true));
      final out = '${dir.path}${Platform.pathSeparator}out.csv';

      final result =
          await service.exportToCsv(glossaryId: 'g1', filePath: out);
      expect(result.isOk, isTrue);
      expect(result.value, 0);
    });
  });
}
