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

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

Language _language(String code) => Language(
      id: 'lang_$code',
      code: code,
      name: code,
      nativeName: code,
    );

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

    for (final code in ['en', 'fr', 'de']) {
      when(() => languageRepo.getByCode(code))
          .thenAnswer((_) async => Ok(_language(code)));
    }
  });

  group('TmMaintenanceService.rebuildFromTranslations language grouping', () {
    test(
      'a source translated into two languages creates one TM entry per '
      'language with the correct target language',
      () async {
        // The repository query returns one row per target language for the
        // same source text, adjacent in the same batch (ORDER BY source_text).
        final rows = <Map<String, dynamic>>[
          {
            'source_text': 'Hello',
            'translated_text': 'Bonjour',
            'target_language_id': 'lang_fr',
          },
          {
            'source_text': 'Hello',
            'translated_text': 'Hallo',
            'target_language_id': 'lang_de',
          },
        ];

        when(() => repo.countLlmTranslations(projectId: any(named: 'projectId')))
            .thenAnswer((_) async => const Ok(2));

        when(() => repo.getMissingTmTranslations(
              projectId: any(named: 'projectId'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((invocation) async {
          final offset = invocation.namedArguments[#offset] as int;
          return Ok(offset == 0 ? rows : <Map<String, dynamic>>[]);
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

        final result = await service.rebuildFromTranslations();

        expect(result.isOk, isTrue, reason: 'rebuild must succeed: $result');
        expect(result.value.added, 2,
            reason: 'both language entries must be counted as added');
        expect(result.value.existing, 0);

        // Collect every entry passed to upsertBatch across all calls.
        final captured = verify(() => repo.upsertBatch(captureAny())).captured;
        final allEntries = captured
            .cast<List<TranslationMemoryEntry>>()
            .expand((e) => e)
            .toList();

        expect(allEntries, hasLength(2),
            reason: 'one TM entry per target language must be persisted');

        final frEntry = allEntries
            .where((e) => e.translatedText == 'Bonjour')
            .toList();
        final deEntry =
            allEntries.where((e) => e.translatedText == 'Hallo').toList();

        expect(frEntry, hasLength(1));
        expect(frEntry.single.targetLanguageId, 'lang_fr',
            reason: 'French translation must be stored under lang_fr');
        expect(deEntry, hasLength(1));
        expect(deEntry.single.targetLanguageId, 'lang_de',
            reason: 'German translation must be stored under lang_de');
      },
    );

    test(
      'rows already present in TM are counted as existing, '
      'missing languages of the same source are still added',
      () async {
        final rows = <Map<String, dynamic>>[
          {
            'source_text': 'Hello',
            'translated_text': 'Bonjour',
            'target_language_id': 'lang_fr',
          },
          {
            'source_text': 'Hello',
            'translated_text': 'Hallo',
            'target_language_id': 'lang_de',
          },
        ];

        when(() => repo.countLlmTranslations(projectId: any(named: 'projectId')))
            .thenAnswer((_) async => const Ok(2));

        when(() => repo.getMissingTmTranslations(
              projectId: any(named: 'projectId'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((invocation) async {
          final offset = invocation.namedArguments[#offset] as int;
          return Ok(offset == 0 ? rows : <Map<String, dynamic>>[]);
        });

        // The French entry already exists; the German one does not.
        when(() => repo.findByHash(any(), 'lang_fr')).thenAnswer(
          (_) async => Ok(TranslationMemoryEntry(
            id: 'tm-1',
            sourceText: 'Hello',
            sourceHash: 'hash',
            sourceLanguageId: 'lang_en',
            targetLanguageId: 'lang_fr',
            translatedText: 'Bonjour',
            usageCount: 1,
            createdAt: 1000,
            lastUsedAt: 2000,
            updatedAt: 2000,
          )),
        );
        when(() => repo.findByHash(any(), 'lang_de')).thenAnswer(
          (_) async => Err(TWMTDatabaseException('not found')),
        );

        when(() => repo.upsertBatch(any())).thenAnswer((invocation) async {
          final entries = invocation.positionalArguments.first
              as List<TranslationMemoryEntry>;
          return Ok(entries.length);
        });

        final result = await service.rebuildFromTranslations();

        expect(result.isOk, isTrue, reason: 'rebuild must succeed: $result');
        expect(result.value.added, 1);
        expect(result.value.existing, 1);

        final captured = verify(() => repo.upsertBatch(captureAny())).captured;
        final allEntries = captured
            .cast<List<TranslationMemoryEntry>>()
            .expand((e) => e)
            .toList();

        expect(allEntries, hasLength(1));
        expect(allEntries.single.targetLanguageId, 'lang_de');
        expect(allEntries.single.translatedText, 'Hallo');
      },
    );
  });
}
