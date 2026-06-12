import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/tm_crud_service.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLangRepo extends Mock implements LanguageRepository {}

class _MockNormalizer extends Mock implements TextNormalizer {}

TranslationMemoryEntry _entry(String id,
        {String source = 's', String target = 't', int usage = 0}) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: source,
      sourceHash: 'h',
      sourceLanguageId: 'en-id',
      targetLanguageId: 'fr-id',
      translatedText: target,
      usageCount: usage,
      createdAt: 0,
      lastUsedAt: 0,
      updatedAt: 0,
    );

Ok<T, TWMTDatabaseException> _ok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _dbErr<T>(String m) => Err(TWMTDatabaseException(m));

void main() {
  setUpAll(() => registerFallbackValue(_entry('f')));

  late _MockTmRepo repo;
  late _MockLangRepo langRepo;
  late _MockNormalizer normalizer;
  late TmCrudService service;

  setUp(() {
    repo = _MockTmRepo();
    langRepo = _MockLangRepo();
    normalizer = _MockNormalizer();
    service = TmCrudService(
      repository: repo,
      languageRepository: langRepo,
      normalizer: normalizer,
      logger: FakeLogger(),
    );

    when(() => normalizer.normalize(any())).thenAnswer((inv) => inv.positionalArguments[0] as String);
    when(() => langRepo.getByCode('en')).thenAnswer((_) async =>
        Ok(const Language(id: 'en-id', code: 'en', name: 'English', nativeName: 'English')));
    when(() => langRepo.getByCode('fr')).thenAnswer((_) async =>
        Ok(const Language(id: 'fr-id', code: 'fr', name: 'French', nativeName: 'Français')));
  });

  group('resolveLanguageId', () {
    test('resolves and caches a known code (one repo hit)', () async {
      expect(await service.resolveLanguageId('FR'), 'fr-id');
      await service.resolveLanguageId('fr');
      verify(() => langRepo.getByCode('fr')).called(1); // cached on 2nd call
    });

    test('returns null for an unknown code', () async {
      when(() => langRepo.getByCode('zz'))
          .thenAnswer((_) async => _dbErr<Language>('missing'));
      expect(await service.resolveLanguageId('zz'), isNull);
    });
  });

  group('addTranslation', () {
    test('rejects empty source or target', () async {
      expect((await service.addTranslation(
              sourceText: '  ', targetText: 't', targetLanguageCode: 'fr'))
          .isErr, isTrue);
      expect((await service.addTranslation(
              sourceText: 's', targetText: '  ', targetLanguageCode: 'fr'))
          .isErr, isTrue);
    });

    test('errors when a language code cannot be resolved', () async {
      when(() => langRepo.getByCode('zz'))
          .thenAnswer((_) async => _dbErr<Language>('missing'));

      final r = await service.addTranslation(
          sourceText: 's', targetText: 't', targetLanguageCode: 'zz');
      expect(r.isErr, isTrue);
    });

    test('updates an existing entry (usage +1) on a hash hit', () async {
      when(() => repo.findBySourceHash(any(), any()))
          .thenAnswer((_) async => _ok(_entry('e1', usage: 5)));
      when(() => repo.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationMemoryEntry));

      final r = await service.addTranslation(
          sourceText: 'Hello', targetText: 'Bonjour', targetLanguageCode: 'fr');

      expect(r.isOk, isTrue);
      final saved = verify(() => repo.update(captureAny())).captured.single
          as TranslationMemoryEntry;
      expect(saved.usageCount, 6);
      expect(saved.translatedText, 'Bonjour');
    });

    test('creates a new entry when no hash match exists', () async {
      when(() => repo.findBySourceHash(any(), any()))
          .thenAnswer((_) async => _dbErr<TranslationMemoryEntry>('not found'));
      when(() => repo.insert(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationMemoryEntry));

      final r = await service.addTranslation(
          sourceText: 'New', targetText: 'Nouveau', targetLanguageCode: 'fr');

      expect(r.isOk, isTrue);
      final saved = verify(() => repo.insert(captureAny())).captured.single
          as TranslationMemoryEntry;
      expect(saved.usageCount, 0);
      expect(saved.translatedText, 'Nouveau');
    });
  });

  group('addTranslationsBatch', () {
    test('is a no-op for an empty list', () async {
      expect((await service.addTranslationsBatch(
              translations: [], targetLanguageCode: 'fr'))
          .unwrap(), 0);
    });

    test('skips blank rows and upserts the rest', () async {
      when(() => repo.upsertBatch(any())).thenAnswer((_) async => _ok(2));

      final r = await service.addTranslationsBatch(
        translations: const [
          (sourceText: 'a', targetText: 'A'),
          (sourceText: '  ', targetText: 'skip'),
          (sourceText: 'b', targetText: 'B'),
        ],
        targetLanguageCode: 'fr',
      );

      expect(r.unwrap(), 2);
      final entries = verify(() => repo.upsertBatch(captureAny())).captured.single
          as List<TranslationMemoryEntry>;
      expect(entries, hasLength(2)); // blank row skipped
    });
  });

  group('incrementUsageCount', () {
    test('increments the stored usage count', () async {
      when(() => repo.getById('e1'))
          .thenAnswer((_) async => _ok(_entry('e1', usage: 2)));
      when(() => repo.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationMemoryEntry));

      final r = await service.incrementUsageCount(entryId: 'e1');
      expect(r.unwrap().usageCount, 3);
    });

    test('propagates a lookup error', () async {
      when(() => repo.getById('e1'))
          .thenAnswer((_) async => _dbErr<TranslationMemoryEntry>('gone'));
      expect((await service.incrementUsageCount(entryId: 'e1')).isErr, isTrue);
    });

    test('batch increment is a no-op for an empty map', () async {
      expect((await service.incrementUsageCountBatch({})).unwrap(), 0);
    });
  });

  group('updateTargetText', () {
    test('rejects empty target text', () async {
      expect((await service.updateTargetText(entryId: 'e', newTargetText: ' '))
          .isErr, isTrue);
    });

    test('is a no-op (no update) when the value is unchanged', () async {
      when(() => repo.getById('e'))
          .thenAnswer((_) async => _ok(_entry('e', target: 'same')));

      final r = await service.updateTargetText(entryId: 'e', newTargetText: 'same');
      expect(r.isOk, isTrue);
      verifyNever(() => repo.update(any()));
    });

    test('updates when the value changed', () async {
      when(() => repo.getById('e'))
          .thenAnswer((_) async => _ok(_entry('e', target: 'old')));
      when(() => repo.update(any()))
          .thenAnswer((inv) async => _ok(inv.positionalArguments[0] as TranslationMemoryEntry));

      final r = await service.updateTargetText(entryId: 'e', newTargetText: 'new');
      expect(r.unwrap().translatedText, 'new');
    });
  });

  group('deleteEntry + calculateSourceHash', () {
    test('deleteEntry maps an ok result to Ok(null)', () async {
      when(() => repo.delete('e')).thenAnswer((_) async => _ok(null));
      expect((await service.deleteEntry(entryId: 'e')).isOk, isTrue);
    });

    test('calculateSourceHash is a stable 64-char sha256 hex', () {
      final h1 = service.calculateSourceHash('Hello');
      final h2 = service.calculateSourceHash('Hello');
      expect(h1, h2);
      expect(h1.length, 64);
    });
  });
}
