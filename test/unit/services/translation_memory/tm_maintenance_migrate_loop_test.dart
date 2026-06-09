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
import 'package:twmt/services/translation_memory/tm_maintenance_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

TranslationMemoryEntry _entry({
  String id = 'tm-legacy-1',
  String source = 'Hello',
  String target = 'Bonjour',
}) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: source,
      // A legacy (short, non-SHA256) hash so it qualifies as "legacy".
      sourceHash: 'legacy',
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: target,
      usageCount: 1,
      createdAt: 1000,
      lastUsedAt: 2000,
      updatedAt: 2000,
    );

void main() {
  late _MockTmRepo repo;
  late TmMaintenanceService service;

  setUp(() {
    repo = _MockTmRepo();
    final crud = TmCrudService(
      repository: repo,
      languageRepository: _MockLanguageRepo(),
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
    service = TmMaintenanceService(
      repository: repo,
      crudService: crud,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
  });

  group('TmMaintenanceService.migrateLegacyHashes no-progress guard', () {
    test(
      'terminates and returns Err when a row persistently fails to migrate',
      () async {
        final stuck = _entry();

        when(() => repo.countLegacyHashes())
            .thenAnswer((_) async => const Ok(1));

        // The repository keeps handing back the same legacy entry forever —
        // simulating a row whose hash update never lands.
        when(() => repo.getEntriesWithLegacyHashes(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => Ok([stuck]));

        // No duplicate exists, so the service will try updateHash...
        when(() => repo.findBySourceHash(any(), any())).thenAnswer(
          (_) async => Err(TWMTDatabaseException('not found')),
        );

        // ...but updateHash always fails (transient DB error). Pre-fix this
        // would loop forever; post-fix the no-progress guard aborts.
        when(() => repo.updateHash(any(), any())).thenAnswer(
          (_) async => Err(TWMTDatabaseException('database is locked')),
        );

        // The test completing at all proves the loop terminates. The timeout
        // guards against a regression that reintroduces the infinite loop.
        final result = await service
            .migrateLegacyHashes()
            .timeout(const Duration(seconds: 5));

        expect(result.isErr, isTrue,
            reason: 'a persistently failing batch must yield an Err');
        expect(result.error, isA<TmServiceException>());
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'still succeeds when rows actually migrate',
      () async {
        final entry = _entry();
        var served = false;

        when(() => repo.countLegacyHashes())
            .thenAnswer((_) async => const Ok(1));

        // Serve the legacy entry once, then report none left (as the real
        // repo would after the hash is rewritten).
        when(() => repo.getEntriesWithLegacyHashes(
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async {
          if (served) return Ok(<TranslationMemoryEntry>[]);
          served = true;
          return Ok([entry]);
        });

        when(() => repo.findBySourceHash(any(), any())).thenAnswer(
          (_) async => Err(TWMTDatabaseException('not found')),
        );
        when(() => repo.updateHash(any(), any()))
            .thenAnswer((_) async => const Ok(null));

        final result = await service
            .migrateLegacyHashes()
            .timeout(const Duration(seconds: 5));

        expect(result.isOk, isTrue);
        expect(result.value, 1);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
