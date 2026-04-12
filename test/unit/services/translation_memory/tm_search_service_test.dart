import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/tm_search_service.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}
class _FakeLogger extends Fake implements LoggingService {
  @override void debug(String m, [dynamic d]) {}
  @override void warning(String m, [dynamic d]) {}
  @override void info(String m, [dynamic d]) {}
  @override void error(String m, [dynamic e, StackTrace? s]) {}
}

void main() {
  late _MockRepo repo;
  late _FakeLogger logger;
  late TmSearchService service;

  setUp(() {
    repo = _MockRepo();
    logger = _FakeLogger();
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
}
