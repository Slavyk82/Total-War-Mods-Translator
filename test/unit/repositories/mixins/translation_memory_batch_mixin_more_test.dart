import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../../helpers/test_database.dart';

/// Coverage for the previously-uncovered methods and branches of
/// [TranslationMemoryBatchMixin] (hosted by [TranslationMemoryRepository]).
///
/// Does NOT overlap with:
/// - translation_memory_batch_mixin_upsert_dedup_test.dart (upsertBatch
///   intra-batch dedup happy path)
/// - translation_memory_bulk_import_dedup_test.dart (bulkImportTmxEntries
///   within/cross-chunk dedup + pre-existing-row insert/update/skip)
///
/// Targets here:
/// - upsertBatch: empty input, INSERT-new path, UPDATE-existing path
///   (usage_count increment + timestamp refresh)
/// - bulkImportTmxEntries: empty input, INSERT-new path
/// - getMissingTmTranslations: matching/non-matching rows, projectId filter,
///   limit/offset paging
/// - countLlmTranslations: DISTINCT counting, projectId filter
void main() {
  late Database db;
  late TranslationMemoryRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = TranslationMemoryRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  TranslationMemoryEntry tmEntry({
    required String id,
    required String hash,
    String sourceText = 'src',
    String targetLang = 'lang_fr',
    String translatedText = 'translated',
    int usageCount = 0,
    int createdAt = 100,
    int lastUsedAt = 100,
    int updatedAt = 100,
  }) {
    return TranslationMemoryEntry(
      id: id,
      sourceText: sourceText,
      sourceHash: hash,
      sourceLanguageId: 'lang_en',
      targetLanguageId: targetLang,
      translatedText: translatedText,
      usageCount: usageCount,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      updatedAt: updatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // upsertBatch — uncovered branches
  // ---------------------------------------------------------------------------
  group('upsertBatch', () {
    test('empty input short-circuits to Ok(0) without touching the DB',
        () async {
      final result = await repository.upsertBatch(const []);

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 0);

      final rows = await db.query('translation_memory');
      expect(rows, isEmpty);
    });

    test('INSERT-new path persists rows and stamps created/last_used/updated',
        () async {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final result = await repository.upsertBatch([
        tmEntry(id: 'n1', hash: 'h1', translatedText: 'fr-one'),
        tmEntry(id: 'n2', hash: 'h2', translatedText: 'fr-two'),
      ]);

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 2);

      final rows = await db.query('translation_memory', orderBy: 'id ASC');
      expect(rows, hasLength(2));

      final r1 = rows.firstWhere((r) => r['id'] == 'n1');
      expect(r1['translated_text'], 'fr-one');
      // Insert path overwrites created/last_used/updated with `now` (seconds).
      expect(r1['created_at'] as int, greaterThanOrEqualTo(before));
      expect(r1['last_used_at'] as int, greaterThanOrEqualTo(before));
      expect(r1['updated_at'] as int, greaterThanOrEqualTo(before));
      // The stale 100 from the entry must have been replaced by `now`.
      expect(r1['created_at'] as int, greaterThan(100));
    });

    test(
        'UPDATE-existing path increments usage_count, refreshes text + '
        'timestamps, and does not insert a new row', () async {
      // Pre-seed a row already in the DB for (hash, target_language_id).
      await db.insert('translation_memory', {
        'id': 'pre',
        'source_hash': 'hx',
        'source_language_id': 'lang_en',
        'target_language_id': 'lang_fr',
        'source_text': 'src',
        'translated_text': 'old',
        'usage_count': 3,
        'created_at': 50,
        'last_used_at': 50,
        'updated_at': 50,
      });

      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Same (hash, target) -> takes the UPDATE branch via the pre-fetch.
      final result = await repository.upsertBatch([
        tmEntry(id: 'incoming', hash: 'hx', translatedText: 'new'),
      ]);

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 1);

      final rows = await db.query('translation_memory',
          where: 'source_hash = ?', whereArgs: ['hx']);
      expect(rows, hasLength(1), reason: 'update must not create a 2nd row');

      final row = rows.single;
      expect(row['id'], 'pre', reason: 'existing row id is preserved');
      expect(row['translated_text'], 'new');
      expect(row['usage_count'], 4, reason: '3 + 1 increment');
      expect(row['last_used_at'] as int, greaterThanOrEqualTo(before));
      expect(row['updated_at'] as int, greaterThanOrEqualTo(before));
      expect(row['created_at'], 50, reason: 'update leaves created_at intact');
    });

    test(
        'mixed batch: same hash with different target languages are BOTH '
        'inserted (distinct unique keys)', () async {
      final result = await repository.upsertBatch([
        tmEntry(id: 'a', hash: 'shared', targetLang: 'lang_fr',
            translatedText: 'fr'),
        tmEntry(id: 'b', hash: 'shared', targetLang: 'lang_de',
            translatedText: 'de'),
      ]);

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 2);

      final rows = await db.query('translation_memory',
          where: 'source_hash = ?', whereArgs: ['shared']);
      expect(rows, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // bulkImportTmxEntries — uncovered branches not exercised by the dedup test
  // ---------------------------------------------------------------------------
  group('bulkImportTmxEntries', () {
    test('empty input short-circuits to Ok(persisted:0, skipped:0)', () async {
      final result = await repository.bulkImportTmxEntries(
        const [],
        overwriteExisting: false,
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.persisted, 0);
      expect(result.value.skipped, 0);
      expect(await db.query('translation_memory'), isEmpty);
    });

    test('INSERT-new path persists fresh rows and reports progress', () async {
      final progress = <(int, int)>[];

      final result = await repository.bulkImportTmxEntries(
        [
          tmEntry(id: 'i1', hash: 'b1', translatedText: 't1'),
          tmEntry(id: 'i2', hash: 'b2', translatedText: 't2'),
        ],
        overwriteExisting: false,
        onProgress: (processed, total) => progress.add((processed, total)),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.persisted, 2);
      expect(result.value.skipped, 0);

      final rows = await db.query('translation_memory', orderBy: 'id ASC');
      expect(rows, hasLength(2));
      // Insert path stores the entry's own timestamps verbatim (no `now`).
      expect(rows.first['created_at'], 100);

      // Single chunk (< 500), so one progress callback at (end=2, total=2).
      expect(progress, equals([(2, 2)]));
    });
  });

  // ---------------------------------------------------------------------------
  // getMissingTmTranslations — fully uncovered
  // ---------------------------------------------------------------------------
  group('getMissingTmTranslations', () {
    // Seeds the translation_units -> translation_versions -> project_languages
    // graph. FK enforcement is OFF in the test DB, so parent rows in
    // projects/languages are unnecessary.
    Future<void> seedVersion({
      required String unitId,
      required String projectId,
      required String key,
      required String sourceText,
      required String versionId,
      required String projectLanguageId,
      required String languageId,
      required String source,
      String? translatedText,
    }) async {
      await db.insert('translation_units', {
        'id': unitId,
        'project_id': projectId,
        'key': key,
        'source_text': sourceText,
        'created_at': 1,
        'updated_at': 1,
      });
      // Multiple versions can share the same (project, language); the join key
      // is pl.id, so reuse the row rather than tripping UNIQUE(project_id,
      // language_id). Callers that need rows to join must pass a shared id.
      await db.insert(
        'project_languages',
        {
          'id': projectLanguageId,
          'project_id': projectId,
          'language_id': languageId,
          'status': 'pending',
          'progress_percent': 0,
          'created_at': 1,
          'updated_at': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert('translation_versions', {
        'id': versionId,
        'unit_id': unitId,
        'project_language_id': projectLanguageId,
        'translated_text': translatedText,
        'status': 'translated',
        'translation_source': source,
        'created_at': 1,
        'updated_at': 1,
      });
    }

    test(
        'returns only llm-sourced versions with non-empty translated_text; '
        'skips non-llm, NULL, and empty-string rows', () async {
      // Matching: llm + non-empty text.
      await seedVersion(
        unitId: 'u1',
        projectId: 'p1',
        key: 'k1',
        sourceText: 'A source',
        versionId: 'v1',
        projectLanguageId: 'pl1',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'A translated',
      );
      // Non-matching: manual source.
      await seedVersion(
        unitId: 'u2',
        projectId: 'p1',
        key: 'k2',
        sourceText: 'B source',
        versionId: 'v2',
        projectLanguageId: 'pl2',
        languageId: 'lang_de',
        source: 'manual',
        translatedText: 'B translated',
      );
      // Non-matching: llm but NULL translated_text.
      await seedVersion(
        unitId: 'u3',
        projectId: 'p1',
        key: 'k3',
        sourceText: 'C source',
        versionId: 'v3',
        projectLanguageId: 'pl3',
        languageId: 'lang_es',
        source: 'llm',
        translatedText: null,
      );
      // Non-matching: llm but empty translated_text.
      await seedVersion(
        unitId: 'u4',
        projectId: 'p1',
        key: 'k4',
        sourceText: 'D source',
        versionId: 'v4',
        projectLanguageId: 'pl4',
        languageId: 'lang_it',
        source: 'llm',
        translatedText: '',
      );

      final result = await repository.getMissingTmTranslations();

      expect(result.isOk, isTrue, reason: result.toString());
      final rows = result.value;
      expect(rows, hasLength(1));
      expect(rows.single['source_text'], 'A source');
      expect(rows.single['translated_text'], 'A translated');
      expect(rows.single['target_language_id'], 'lang_fr');
    });

    test('projectId filter limits results to the matching project', () async {
      await seedVersion(
        unitId: 'u1',
        projectId: 'pA',
        key: 'k1',
        sourceText: 'in-project',
        versionId: 'v1',
        projectLanguageId: 'pl1',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tA',
      );
      await seedVersion(
        unitId: 'u2',
        projectId: 'pB',
        key: 'k2',
        sourceText: 'other-project',
        versionId: 'v2',
        projectLanguageId: 'pl2',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tB',
      );

      final result = await repository.getMissingTmTranslations(projectId: 'pA');

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, hasLength(1));
      expect(result.value.single['source_text'], 'in-project');
    });

    test('limit and offset page through ORDER BY source_text results',
        () async {
      // Three distinct sources, ordered alphabetically by source_text.
      for (final (i, src) in ['alpha', 'bravo', 'charlie'].indexed) {
        await seedVersion(
          unitId: 'u$i',
          projectId: 'p1',
          key: 'k$i',
          sourceText: src,
          versionId: 'v$i',
          // Same project+language for all three -> shared pl row (the join is
          // on pl.id), so they page together by source_text.
          projectLanguageId: 'pl0',
          languageId: 'lang_fr',
          source: 'llm',
          translatedText: 't$i',
        );
      }

      final page1 =
          await repository.getMissingTmTranslations(limit: 2, offset: 0);
      expect(page1.isOk, isTrue, reason: page1.toString());
      expect(page1.value.map((r) => r['source_text']).toList(),
          equals(['alpha', 'bravo']));

      final page2 =
          await repository.getMissingTmTranslations(limit: 2, offset: 2);
      expect(page2.isOk, isTrue, reason: page2.toString());
      expect(page2.value.map((r) => r['source_text']).toList(),
          equals(['charlie']));
    });

    test('returns empty list when nothing matches', () async {
      final result = await repository.getMissingTmTranslations();
      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // countLlmTranslations — fully uncovered
  // ---------------------------------------------------------------------------
  group('countLlmTranslations', () {
    Future<void> seed({
      required String unitId,
      required String projectId,
      required String key,
      required String sourceText,
      required String versionId,
      required String projectLanguageId,
      required String languageId,
      required String source,
      String? translatedText,
    }) async {
      await db.insert('translation_units', {
        'id': unitId,
        'project_id': projectId,
        'key': key,
        'source_text': sourceText,
        'created_at': 1,
        'updated_at': 1,
      });
      // Multiple versions can share the same (project, language); the join key
      // is pl.id, so reuse the row rather than tripping UNIQUE(project_id,
      // language_id). Callers that need rows to join must pass a shared id.
      await db.insert(
        'project_languages',
        {
          'id': projectLanguageId,
          'project_id': projectId,
          'language_id': languageId,
          'status': 'pending',
          'progress_percent': 0,
          'created_at': 1,
          'updated_at': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert('translation_versions', {
        'id': versionId,
        'unit_id': unitId,
        'project_language_id': projectLanguageId,
        'translated_text': translatedText,
        'status': 'translated',
        'translation_source': source,
        'created_at': 1,
        'updated_at': 1,
      });
    }

    test('returns 0 when there are no llm translations', () async {
      final result = await repository.countLlmTranslations();
      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 0);
    });

    test(
        'counts DISTINCT (source_text|language) llm rows and excludes '
        'non-llm / NULL / empty', () async {
      // Two distinct (source_text, language) llm pairs -> count 2.
      await seed(
        unitId: 'u1',
        projectId: 'p1',
        key: 'k1',
        sourceText: 'one',
        versionId: 'v1',
        projectLanguageId: 'pl1',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tr1',
      );
      await seed(
        unitId: 'u2',
        projectId: 'p1',
        key: 'k2',
        sourceText: 'two',
        versionId: 'v2',
        projectLanguageId: 'pl2',
        languageId: 'lang_de',
        source: 'llm',
        translatedText: 'tr2',
      );
      // Excluded: manual.
      await seed(
        unitId: 'u3',
        projectId: 'p1',
        key: 'k3',
        sourceText: 'three',
        versionId: 'v3',
        projectLanguageId: 'pl3',
        languageId: 'lang_es',
        source: 'manual',
        translatedText: 'tr3',
      );
      // Excluded: NULL text.
      await seed(
        unitId: 'u4',
        projectId: 'p1',
        key: 'k4',
        sourceText: 'four',
        versionId: 'v4',
        projectLanguageId: 'pl4',
        languageId: 'lang_it',
        source: 'llm',
        translatedText: null,
      );
      // Excluded: empty text.
      await seed(
        unitId: 'u5',
        projectId: 'p1',
        key: 'k5',
        sourceText: 'five',
        versionId: 'v5',
        projectLanguageId: 'pl5',
        languageId: 'lang_pt',
        source: 'llm',
        translatedText: '',
      );

      final result = await repository.countLlmTranslations();
      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 2);
    });

    test(
        'DISTINCT collapses the same (source_text, language) across units',
        () async {
      // Same source_text + same language under two different units -> the
      // COUNT(DISTINCT source_text || "|" || language) collapses to 1.
      await seed(
        unitId: 'u1',
        projectId: 'p1',
        key: 'k1',
        sourceText: 'dup',
        versionId: 'v1',
        projectLanguageId: 'pl1',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tr1',
      );
      await seed(
        unitId: 'u2',
        projectId: 'p1',
        key: 'k2',
        sourceText: 'dup',
        versionId: 'v2',
        // Same shared pl row as v1 so both rows join and DISTINCT can collapse
        // the identical (source_text, language) pair.
        projectLanguageId: 'pl1',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tr2',
      );

      final result = await repository.countLlmTranslations();
      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value, 1);
    });

    test('projectId filter restricts the count to the given project',
        () async {
      await seed(
        unitId: 'u1',
        projectId: 'pA',
        key: 'k1',
        sourceText: 'a',
        versionId: 'v1',
        projectLanguageId: 'pl1',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tA',
      );
      await seed(
        unitId: 'u2',
        projectId: 'pB',
        key: 'k2',
        sourceText: 'b',
        versionId: 'v2',
        projectLanguageId: 'pl2',
        languageId: 'lang_fr',
        source: 'llm',
        translatedText: 'tB',
      );

      final all = await repository.countLlmTranslations();
      expect(all.value, 2);

      final filtered = await repository.countLlmTranslations(projectId: 'pA');
      expect(filtered.isOk, isTrue, reason: filtered.toString());
      expect(filtered.value, 1);
    });
  });
}
