import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_crud_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

TranslationMemoryEntry _entry({
  String id = 'tm-1',
  String source = 'Hello',
  String target = 'Bonjour',
  int usageCount = 7,
  int createdAt = 1000,
  int lastUsedAt = 2000,
  int updatedAt = 2000,
}) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: source,
      sourceHash: 'hash-1',
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: target,
      usageCount: usageCount,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      updatedAt: updatedAt,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_entry());
  });

  late _MockTmRepo repo;
  late _MockLanguageRepo languageRepo;
  late TmCrudService service;

  setUp(() {
    repo = _MockTmRepo();
    languageRepo = _MockLanguageRepo();
    service = TmCrudService(
      repository: repo,
      languageRepository: languageRepo,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
  });

  group('TmCrudService.updateTargetText', () {
    test('updates only translated_text + updated_at; preserves the rest',
        () async {
      final existing = _entry();
      when(() => repo.getById('tm-1')).thenAnswer((_) async => Ok(existing));
      when(() => repo.update(any())).thenAnswer(
        (invocation) async =>
            Ok(invocation.positionalArguments.first as TranslationMemoryEntry),
      );

      final result =
          await service.updateTargetText(entryId: 'tm-1', newTargetText: 'Salut');

      expect(result.isOk, true);
      final captured = verify(() => repo.update(captureAny())).captured.single
          as TranslationMemoryEntry;
      expect(captured.translatedText, 'Salut');
      expect(captured.sourceText, existing.sourceText);
      expect(captured.sourceHash, existing.sourceHash);
      expect(captured.usageCount, existing.usageCount);
      expect(captured.lastUsedAt, existing.lastUsedAt);
      expect(captured.createdAt, existing.createdAt);
      expect(captured.updatedAt, greaterThan(existing.updatedAt));
    });

    test('rejects empty target text without touching the repository',
        () async {
      final result =
          await service.updateTargetText(entryId: 'tm-1', newTargetText: '   ');

      expect(result.isErr, true);
      verifyNever(() => repo.getById(any()));
      verifyNever(() => repo.update(any()));
    });

    test('returns the existing entry untouched when text is unchanged',
        () async {
      final existing = _entry(target: 'Bonjour');
      when(() => repo.getById('tm-1')).thenAnswer((_) async => Ok(existing));

      final result = await service.updateTargetText(
        entryId: 'tm-1',
        newTargetText: 'Bonjour',
      );

      expect(result.isOk, true);
      expect(result.value, same(existing));
      verifyNever(() => repo.update(any()));
    });

    test('propagates a getById error as a TmServiceException', () async {
      when(() => repo.getById('missing')).thenAnswer(
        (_) async => Err(TWMTDatabaseException('not found')),
      );

      final result = await service.updateTargetText(
        entryId: 'missing',
        newTargetText: 'whatever',
      );

      expect(result.isErr, true);
      expect(result.error, isA<TmServiceException>());
      verifyNever(() => repo.update(any()));
    });

    test('propagates a repository update error', () async {
      final existing = _entry();
      when(() => repo.getById('tm-1')).thenAnswer((_) async => Ok(existing));
      when(() => repo.update(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('disk full')),
      );

      final result = await service.updateTargetText(
        entryId: 'tm-1',
        newTargetText: 'Salut',
      );

      expect(result.isErr, true);
      expect(result.error, isA<TmServiceException>());
    });
  });
}
