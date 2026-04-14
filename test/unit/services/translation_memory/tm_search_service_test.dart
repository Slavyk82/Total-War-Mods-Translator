import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/tm_search_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}

// Mocktail-based logger used only by tests that need to verify log calls.
// Kept separate from FakeLogger so the bulk of tests remain unaffected.
class _MockLogger extends Mock implements ILoggingService {}

void main() {
  late _MockRepo repo;
  late FakeLogger logger;
  late TmSearchService service;

  setUp(() {
    repo = _MockRepo();
    logger = FakeLogger();
    service = TmSearchService(repository: repo, logger: logger);
  });

  group('TmSearchService.searchEntries — FTS5 failure path', () {
    test('falls back to LIKE query, never to getAll() in-memory scan', () async {
      // Arrange: FTS5 search returns an error
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Err(TWMTDatabaseException('FTS5 down')));

      when(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));

      // Act
      final result = await service.searchEntries(searchText: 'hello');

      // Assert: getAll() must NOT have been called (OOM hazard at 6M rows)
      verifyNever(() => repo.getAll());
      verify(() => repo.searchByLike(
            searchText: 'hello',
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
      expect(result.isOk, true);
    });
  });

  group('TmSearchService.searchEntries — empty search text', () {
    test('returns Ok([]) without hitting any repo method for empty string',
        () async {
      // Act
      final result = await service.searchEntries(searchText: '');

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
      verifyNever(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          ));
      verifyNever(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          ));
    });

    test('returns Ok([]) without hitting any repo method for whitespace',
        () async {
      // Act
      final result = await service.searchEntries(searchText: '   ');

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
      verifyNever(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          ));
      verifyNever(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          ));
    });
  });

  group('TmSearchService.searchEntries — FTS5 success path', () {
    test('returns FTS5 results directly without invoking LIKE fallback',
        () async {
      // Arrange: a single fixture entry returned by FTS5
      final fixture = TranslationMemoryEntry(
        id: 'tm_1',
        sourceText: 'hello',
        sourceHash: 'hash_hello',
        sourceLanguageId: 'lang_en',
        targetLanguageId: 'lang_fr',
        translatedText: 'bonjour',
        createdAt: 0,
        lastUsedAt: 0,
        updatedAt: 0,
      );

      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Ok([fixture]));

      // Act
      final result = await service.searchEntries(searchText: 'hello');

      // Assert
      expect(result.isOk, true);
      expect(result.value, hasLength(1));
      expect(result.value.first.id, 'tm_1');
      verifyNever(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          ));
    });
  });

  group('TmSearchService.searchEntries — LIKE fallback error path', () {
    test('wraps LIKE DB error in TmServiceException with informative message',
        () async {
      // Arrange: FTS5 errors, LIKE also errors
      final innerDbException = const TWMTDatabaseException('LIKE exploded');

      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer(
              (_) async => Err(const TWMTDatabaseException('FTS5 down')));

      when(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Err(innerDbException));

      // Act
      final result = await service.searchEntries(searchText: 'hello');

      // Assert
      expect(result.isErr, true);
      final exception = result.error;
      expect(exception, isA<TmServiceException>());
      expect(exception.message, contains('LIKE fallback failed'));
      expect(exception.error, same(innerDbException));
    });
  });

  group('TmSearchService.searchEntries — search scope threading', () {
    setUp(() {
      // Force LIKE fallback so we can assert scope on BOTH repo calls
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer(
              (_) async => Err(const TWMTDatabaseException('forced')));
      when(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));
    });

    test('TmSearchScope.source passes "source" to both repo methods',
        () async {
      await service.searchEntries(
        searchText: 'hello',
        searchIn: TmSearchScope.source,
      );

      verify(() => repo.searchFts5(
            searchText: 'hello',
            searchScope: 'source',
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
      verify(() => repo.searchByLike(
            searchText: 'hello',
            searchScope: 'source',
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
    });

    test('TmSearchScope.target passes "target" to both repo methods',
        () async {
      await service.searchEntries(
        searchText: 'hello',
        searchIn: TmSearchScope.target,
      );

      verify(() => repo.searchFts5(
            searchText: 'hello',
            searchScope: 'target',
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
      verify(() => repo.searchByLike(
            searchText: 'hello',
            searchScope: 'target',
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
    });

    test('TmSearchScope.both passes "both" to both repo methods', () async {
      await service.searchEntries(
        searchText: 'hello',
        searchIn: TmSearchScope.both,
      );

      verify(() => repo.searchFts5(
            searchText: 'hello',
            searchScope: 'both',
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
      verify(() => repo.searchByLike(
            searchText: 'hello',
            searchScope: 'both',
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).called(1);
    });
  });

  group('TmSearchService.searchEntries — language filter threading', () {
    test('prepends "lang_" prefix when targetLanguageCode is provided',
        () async {
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));

      await service.searchEntries(
        searchText: 'hello',
        targetLanguageCode: 'fr',
      );

      verify(() => repo.searchFts5(
            searchText: 'hello',
            searchScope: any(named: 'searchScope'),
            targetLanguageId: 'lang_fr',
            limit: any(named: 'limit'),
          )).called(1);
    });

    test('passes null targetLanguageId when targetLanguageCode is null',
        () async {
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));

      await service.searchEntries(searchText: 'hello');

      verify(() => repo.searchFts5(
            searchText: 'hello',
            searchScope: any(named: 'searchScope'),
            targetLanguageId: null,
            limit: any(named: 'limit'),
          )).called(1);
    });
  });

  group('TmSearchService.searchEntries — unexpected internal exception', () {
    test('outer try/catch converts thrown Exception into TmServiceException',
        () async {
      // Arrange: FTS5 mock throws synchronously (not a Future.error)
      final boom = Exception('boom');
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenThrow(boom);

      // Act
      final result = await service.searchEntries(searchText: 'hello');

      // Assert
      expect(result.isErr, true);
      final exception = result.error;
      expect(exception, isA<TmServiceException>());
      expect(exception.message, contains('Unexpected error searching entries'));
      expect(exception.error, same(boom));
      expect(exception.stackTrace, isNotNull);
    });
  });

  group('TmSearchService.searchEntries — inner LIKE fallback exception', () {
    test(
        'inner try/catch wraps synchronous LIKE throw into TmServiceException',
        () async {
      // Arrange: FTS5 returns Err so we fall into _searchEntriesWithLike,
      // then searchByLike throws synchronously to hit the inner catch.
      final boom = Exception('like boom');
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer(
              (_) async => Err(const TWMTDatabaseException('FTS5 down')));
      when(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenThrow(boom);

      // Act
      final result = await service.searchEntries(searchText: 'hello');

      // Assert
      expect(result.isErr, true);
      final exception = result.error;
      expect(exception, isA<TmServiceException>());
      expect(exception.message, contains('Unexpected error in LIKE fallback'));
      expect(exception.error, same(boom));
      expect(exception.stackTrace, isNotNull);
    });
  });

  group('TmSearchService.getEntries', () {
    // Reusable fixture entry for getEntries tests.
    final fixture = TranslationMemoryEntry(
      id: 'tm_fr_1',
      sourceText: 'hello',
      sourceHash: 'hash_hello',
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: 'bonjour',
      createdAt: 0,
      lastUsedAt: 0,
      updatedAt: 0,
    );

    test(
        'happy path: targetLanguageCode "fr" is converted to "lang_fr" '
        'and threaded to repository.getWithFilters', () async {
      // Arrange
      when(() => repo.getWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => Ok([fixture]));

      // Act
      final result = await service.getEntries(targetLanguageCode: 'fr');

      // Assert
      expect(result.isOk, true);
      expect(result.value, hasLength(1));
      expect(result.value.first.id, 'tm_fr_1');
      verify(() => repo.getWithFilters(
            targetLanguageId: 'lang_fr',
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).called(1);
    });

    test(
        'no language filter: targetLanguageCode null forwards null '
        'targetLanguageId to repository', () async {
      // Arrange
      when(() => repo.getWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => const Ok([]));

      // Act
      final result = await service.getEntries();

      // Assert
      expect(result.isOk, true);
      expect(result.value, isEmpty);
      verify(() => repo.getWithFilters(
            targetLanguageId: null,
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).called(1);
    });

    test('repo Err is wrapped into TmServiceException with informative message',
        () async {
      // Arrange
      final innerDbException = const TWMTDatabaseException('db error');
      when(() => repo.getWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => Err(innerDbException));

      // Act
      final result = await service.getEntries();

      // Assert
      expect(result.isErr, true);
      final exception = result.error;
      expect(exception, isA<TmServiceException>());
      expect(exception.message, contains('Failed to get entries'));
      expect(exception.error, same(innerDbException));
    });

    test(
        'unexpected synchronous throw is wrapped with stack trace into '
        'TmServiceException', () async {
      // Arrange: getWithFilters throws synchronously to hit outer try/catch.
      final boom = Exception('unexpected boom');
      when(() => repo.getWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenThrow(boom);

      // Act
      final result = await service.getEntries();

      // Assert
      expect(result.isErr, true);
      final exception = result.error;
      expect(exception, isA<TmServiceException>());
      expect(exception.message, contains('Unexpected error getting entries'));
      expect(exception.error, same(boom));
      expect(exception.stackTrace, isNotNull);
    });
  });

  group('TmSearchService — language code normalization', () {
    test(
        'getEntries with already-prefixed code "lang_fr" forwards it as-is '
        '(no "lang_lang_fr" double-prefix)', () async {
      // Arrange
      when(() => repo.getWithFilters(
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => const Ok([]));

      // Act: caller passes an already-prefixed code.
      final result = await service.getEntries(targetLanguageCode: 'lang_fr');

      // Assert: repository must receive 'lang_fr', not 'lang_lang_fr'.
      expect(result.isOk, true);
      verify(() => repo.getWithFilters(
            targetLanguageId: 'lang_fr',
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            orderBy: any(named: 'orderBy'),
          )).called(1);
    });

    test(
        'searchEntries with already-prefixed code "lang_fr" forwards it as-is '
        'to searchFts5 (no "lang_lang_fr" double-prefix)', () async {
      // Arrange
      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));

      // Act: caller passes an already-prefixed code.
      await service.searchEntries(
        searchText: 'hello',
        targetLanguageCode: 'lang_fr',
      );

      // Assert: repository must receive 'lang_fr', not 'lang_lang_fr'.
      verify(() => repo.searchFts5(
            searchText: 'hello',
            searchScope: any(named: 'searchScope'),
            targetLanguageId: 'lang_fr',
            limit: any(named: 'limit'),
          )).called(1);
    });
  });

  group('TmSearchService.searchEntries — FTS5 failure logs warning', () {
    test(
        'emits exactly one warning when FTS5 fails and LIKE fallback succeeds',
        () async {
      // Arrange: dedicated mocktail logger to observe calls.
      final mockLogger = _MockLogger();
      final localService =
          TmSearchService(repository: repo, logger: mockLogger);

      when(() => repo.searchFts5(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer(
              (_) async => Err(const TWMTDatabaseException('FTS5 down')));
      when(() => repo.searchByLike(
            searchText: any(named: 'searchText'),
            searchScope: any(named: 'searchScope'),
            targetLanguageId: any(named: 'targetLanguageId'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const Ok([]));

      // Act
      final result = await localService.searchEntries(searchText: 'hello');

      // Assert: fallback succeeded and logger.warning was called exactly once.
      expect(result.isOk, true);
      verify(() => mockLogger.warning(any(), any())).called(1);
    });
  });
}
