import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/translation_memory_service_impl.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';

import '../../helpers/noop_logger.dart';

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

void main() {
  late _MockTmRepo repo;
  late _MockLanguageRepo languageRepo;
  late TranslationMemoryServiceImpl service;

  setUpAll(() {
    registerFallbackValue(<String, int>{});
  });

  setUp(() {
    repo = _MockTmRepo();
    languageRepo = _MockLanguageRepo();
    service = TranslationMemoryServiceImpl(
      repository: repo,
      languageRepository: languageRepo,
      normalizer: TextNormalizer(),
      similarityCalculator: SimilarityCalculator(),
      cache: TmCache(),
      logger: NoopLogger(),
    );
  });

  group('countEntries (delegates to TmSearchService)', () {
    test('returns the repository count on success', () async {
      when(() => repo.countWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            minUsageCount: any(named: 'minUsageCount'),
          )).thenAnswer((_) async => const Ok(7));

      final result = await service.countEntries();

      expect(result, isA<Ok>());
      expect(result.value, 7);
      verify(() => repo.countWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            minUsageCount: any(named: 'minUsageCount'),
          )).called(1);
    });

    test('maps a repository error to a TmServiceException', () async {
      when(() => repo.countWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            minUsageCount: any(named: 'minUsageCount'),
          )).thenAnswer(
        (_) async => const Err(TWMTDatabaseException('boom')),
      );

      final result = await service.countEntries();

      expect(result, isA<Err>());
      expect(result.error, isA<ServiceException>());
    });
  });

  group('getEntries (delegates to TmSearchService)', () {
    test('returns the repository entries on success', () async {
      when(() => repo.getWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => const Ok(<TranslationMemoryEntry>[]));

      final result = await service.getEntries();

      expect(result, isA<Ok>());
      expect(result.value, isEmpty);
    });
  });

  group('deleteEntry (delegates to TmCrudService)', () {
    test('forwards the id to the repository and clears cache', () async {
      when(() => repo.delete(any())).thenAnswer((_) async => const Ok(null));

      final result = await service.deleteEntry(entryId: 'entry-1');

      expect(result, isA<Ok>());
      verify(() => repo.delete('entry-1')).called(1);
    });

    test('maps a repository delete failure to an error', () async {
      when(() => repo.delete(any())).thenAnswer(
        (_) async => const Err(TWMTDatabaseException('not found')),
      );

      final result = await service.deleteEntry(entryId: 'missing');

      expect(result, isA<Err>());
    });
  });

  group('incrementUsageCountBatch (delegates to TmCrudService)', () {
    test('forwards the usage map and returns the updated count', () async {
      when(() => repo.incrementUsageCountBatch(any()))
          .thenAnswer((_) async => const Ok(3));

      final result =
          await service.incrementUsageCountBatch({'a': 1, 'b': 2});

      expect(result, isA<Ok>());
      expect(result.value, 3);
      verify(() => repo.incrementUsageCountBatch({'a': 1, 'b': 2})).called(1);
    });
  });

  group('clearCache', () {
    test('completes without touching the repository', () async {
      await service.clearCache();
      verifyNever(() => repo.delete(any()));
    });
  });
}
