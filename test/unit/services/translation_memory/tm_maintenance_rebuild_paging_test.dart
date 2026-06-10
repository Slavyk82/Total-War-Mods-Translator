import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_crud_service.dart';
import 'package:twmt/services/translation_memory/tm_maintenance_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for the rebuildFromTranslations paging loop bound.
//
// countLlmTranslations() counts DISTINCT (source_text, language) PAIRS while
// getMissingTmTranslations() pages DISTINCT (source, translation, language)
// TRIPLES over the same FROM/WHERE. Whenever the same source text was
// translated differently across units (pervasive for repeated Total War loc
// strings) the row set is strictly larger than the count. The loop used to be
// `for (offset = 0; offset < total; offset += batchSize)` — bounded by the
// smaller count — so the tail pages were silently never fetched and those
// translations never entered the TM. The loop must instead terminate on an
// empty/short page from the paged query itself.

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(<TranslationMemoryEntry>[]);
  });

  late _MockTmRepo repo;
  late _MockLanguageRepo languageRepo;
  late TmMaintenanceService service;

  setUp(() {
    repo = _MockTmRepo();
    languageRepo = _MockLanguageRepo();
    final crud = TmCrudService(
      repository: repo,
      languageRepository: languageRepo,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
    service = TmMaintenanceService(
      repository: repo,
      crudService: crud,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );

    // addTranslationsBatch resolves both the (default 'en') source language
    // and the target language code to IDs.
    for (final code in ['en', 'fr']) {
      when(() => languageRepo.getByCode(code)).thenAnswer(
        (_) async => Ok(Language(
          id: 'lang_$code',
          code: code,
          name: code,
          nativeName: code,
        )),
      );
    }
  });

  group('TmMaintenanceService.rebuildFromTranslations paging termination', () {
    test(
      'processes ALL paged rows even when countLlmTranslations() is smaller '
      'than the row set (tail page beyond `total` must still be fetched)',
      () async {
        // The service pages with a fixed internal batchSize of 500. Feed a
        // full first page (500 rows) plus a 1-row tail page at offset 500,
        // while the (pair-based) count reports only 2. A `offset < total`
        // loop bound stops after the first page (offset 0 < 2, then 500 >= 2)
        // and never sees the tail row; the fixed loop pages until the query
        // returns a short/empty page and processes all 501 rows.
        const batchSize = 500;

        final fullPage = List<Map<String, dynamic>>.generate(
          batchSize,
          (i) => {
            'source_text': 'Source ${i.toString().padLeft(3, '0')}',
            'translated_text': 'Traduction $i',
            'target_language_id': 'lang_fr',
          },
        );
        final tailPage = <Map<String, dynamic>>[
          {
            'source_text': 'Tail source',
            'translated_text': 'Traduction de queue',
            'target_language_id': 'lang_fr',
          },
        ];

        // Pair-based COUNT deliberately smaller than the triple row set.
        when(() => repo.countLlmTranslations(projectId: any(named: 'projectId')))
            .thenAnswer((_) async => const Ok(2));

        when(() => repo.getMissingTmTranslations(
              projectId: any(named: 'projectId'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((invocation) async {
          final offset = invocation.namedArguments[#offset] as int;
          if (offset == 0) return Ok(fullPage);
          if (offset == batchSize) return Ok(tailPage);
          return const Ok(<Map<String, dynamic>>[]);
        });

        // Nothing exists in TM yet.
        when(() => repo.findByHash(any(), any())).thenAnswer(
          (_) async => Err(TWMTDatabaseException('not found')),
        );

        when(() => repo.upsertBatch(any())).thenAnswer((invocation) async {
          final entries = invocation.positionalArguments.first
              as List<TranslationMemoryEntry>;
          return Ok(entries.length);
        });

        final progressTotals = <int>[];
        final progressProcessed = <int>[];
        final result = await service.rebuildFromTranslations(
          onProgress: (processed, total, added) {
            progressProcessed.add(processed);
            progressTotals.add(total);
          },
        );

        expect(result.isOk, isTrue, reason: 'rebuild must succeed: $result');
        expect(result.value.added, batchSize + 1,
            reason: 'every paged row — including the tail page past the '
                'mismatched COUNT — must be added to the TM');

        // The tail page request itself proves the loop was not bounded by
        // the (smaller) pair count.
        verify(() => repo.getMissingTmTranslations(
              projectId: any(named: 'projectId'),
              limit: any(named: 'limit'),
              offset: batchSize,
            )).called(1);

        // Progress denominator must never drop below the processed numerator
        // even though the COUNT estimate (2) is smaller.
        for (var i = 0; i < progressTotals.length; i++) {
          expect(progressTotals[i], greaterThanOrEqualTo(progressProcessed[i]),
              reason: 'progress total must be clamped to processed count');
        }
      },
    );

    test(
      'terminates on a fetch error instead of paging forever, returning the '
      'partial counts accumulated so far',
      () async {
        // The open-ended loop must not spin forever when the paged query
        // keeps failing — it stops and returns what it processed.
        const batchSize = 500;
        final fullPage = List<Map<String, dynamic>>.generate(
          batchSize,
          (i) => {
            'source_text': 'Source $i',
            'translated_text': 'Traduction $i',
            'target_language_id': 'lang_fr',
          },
        );

        when(() => repo.countLlmTranslations(projectId: any(named: 'projectId')))
            .thenAnswer((_) async => const Ok(2));

        when(() => repo.getMissingTmTranslations(
              projectId: any(named: 'projectId'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((invocation) async {
          final offset = invocation.namedArguments[#offset] as int;
          if (offset == 0) return Ok(fullPage);
          return Err(TWMTDatabaseException('db gone'));
        });

        when(() => repo.findByHash(any(), any())).thenAnswer(
          (_) async => Err(TWMTDatabaseException('not found')),
        );

        when(() => repo.upsertBatch(any())).thenAnswer((invocation) async {
          final entries = invocation.positionalArguments.first
              as List<TranslationMemoryEntry>;
          return Ok(entries.length);
        });

        final result = await service.rebuildFromTranslations();

        expect(result.isOk, isTrue);
        expect(result.value.added, batchSize,
            reason: 'first page processed before the error is kept');
        // Exactly two page fetches: the full page, then the failing one.
        verify(() => repo.getMissingTmTranslations(
              projectId: any(named: 'projectId'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(2);
      },
    );
  });
}
