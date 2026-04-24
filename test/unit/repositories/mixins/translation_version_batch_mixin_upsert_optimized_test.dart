import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();
  });

  tearDown(() => TestDatabase.close(db));

  group('upsertBatchOptimized', () {
    test('returns zero counts and no-op for empty list', () async {
      final result = await repo.upsertBatchOptimized(entities: []);
      expect(result.isOk, isTrue);
      final counts = result.unwrap();
      expect(counts.inserted, 0);
      expect(counts.updated, 0);
      expect(counts.effectiveVersionIds, isEmpty);
    });

    test('inserts new rows and returns their own ids when below trigger threshold',
        () async {
      // 10 entities < 50 → triggers stay active.
      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = List.generate(10, (i) {
        return TranslationVersion(
          id: 'v-$i',
          unitId: 'u-$i',
          projectLanguageId: 'pl-1',
          translatedText: 'text $i',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        );
      });

      final result = await repo.upsertBatchOptimized(entities: entities);
      expect(result.isOk, isTrue);
      final counts = result.unwrap();
      expect(counts.inserted, 10);
      expect(counts.updated, 0);
      expect(counts.effectiveVersionIds,
          equals(List.generate(10, (i) => 'v-$i')));

      // Verify rows persisted.
      final rows = await db.query('translation_versions',
          where: 'project_language_id = ?', whereArgs: ['pl-1']);
      expect(rows, hasLength(10));
    });

    test('inserts correctly when crossing trigger threshold (100 entities)',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = List.generate(100, (i) {
        return TranslationVersion(
          id: 'v-$i',
          unitId: 'u-$i',
          projectLanguageId: 'pl-1',
          translatedText: 'text $i',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        );
      });

      final result = await repo.upsertBatchOptimized(entities: entities);
      expect(result.unwrap().inserted, 100);

      // Verify triggers were recreated after the call.
      final triggers = await db.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type = 'trigger'
          AND name IN (
            'trg_update_project_language_progress',
            'trg_translation_versions_fts_insert',
            'trg_translation_versions_fts_update',
            'trg_update_cache_on_version_change'
          )
      ''');
      expect(triggers, hasLength(4),
          reason: 'all four triggers must be recreated');

      // Verify FTS index was manually rebuilt.
      final ftsCount = await db.rawQuery(
          "SELECT COUNT(*) as c FROM translation_versions_fts");
      expect(ftsCount.first['c'], 100);
    });

    test('updates existing rows with preserved ids and created_at', () async {
      // Pre-seed two rows.
      await db.insert('translation_versions', {
        'id': 'existing-1',
        'unit_id': 'u-1',
        'project_language_id': 'pl-1',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 1000,
        'updated_at': 1000,
      });
      await db.insert('translation_versions', {
        'id': 'existing-2',
        'unit_id': 'u-2',
        'project_language_id': 'pl-1',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 2000,
        'updated_at': 2000,
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = [
        TranslationVersion(
          id: 'new-1',  // Ignored: will use 'existing-1' because u-1 exists.
          unitId: 'u-1',
          projectLanguageId: 'pl-1',
          translatedText: 'fresh',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
        TranslationVersion(
          id: 'new-2',
          unitId: 'u-2',
          projectLanguageId: 'pl-1',
          translatedText: 'fresh-2',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final result = await repo.upsertBatchOptimized(entities: entities);
      final counts = result.unwrap();
      expect(counts.inserted, 0);
      expect(counts.updated, 2);
      expect(counts.effectiveVersionIds,
          equals(['existing-1', 'existing-2']),
          reason: 'must return pre-existing ids, not the input entity ids');

      final rows = await db.query('translation_versions',
          where: 'unit_id IN (?, ?)',
          whereArgs: ['u-1', 'u-2'],
          orderBy: 'id ASC');
      expect(rows, hasLength(2));
      expect(rows[0]['id'], 'existing-1');
      expect(rows[0]['translated_text'], 'fresh');
      expect(rows[0]['created_at'], 1000, reason: 'created_at preserved');
      expect(rows[1]['id'], 'existing-2');
      expect(rows[1]['created_at'], 2000);
    });

    test('mixed insert + update yields correct counts and effectiveVersionIds',
        () async {
      await db.insert('translation_versions', {
        'id': 'pre-1',
        'unit_id': 'u-1',
        'project_language_id': 'pl-1',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 1000,
        'updated_at': 1000,
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = [
        TranslationVersion(
          id: 'ignored-1',
          unitId: 'u-1', // will UPDATE existing → effective id = 'pre-1'
          projectLanguageId: 'pl-1',
          translatedText: 'new-1',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
        TranslationVersion(
          id: 'inserted-2',
          unitId: 'u-2', // will INSERT
          projectLanguageId: 'pl-1',
          translatedText: 'new-2',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final result = await repo.upsertBatchOptimized(entities: entities);
      final counts = result.unwrap();
      expect(counts.inserted, 1);
      expect(counts.updated, 1);
      expect(counts.effectiveVersionIds, equals(['pre-1', 'inserted-2']));
    });

    test('recalculates project_languages.progress_percent after bulk write',
        () async {
      // Seed minimal project_languages and translation_units so the
      // aggregation has something to look at.
      await db.insert('project_languages', {
        'id': 'pl-1',
        'project_id': 'proj-1',
        'language_id': 'fr',
        'status': 'pending',
        'progress_percent': 0.0,
        'created_at': 0,
        'updated_at': 0,
      });
      for (var i = 0; i < 100; i++) {
        await db.insert('translation_units', {
          'id': 'u-$i',
          'project_id': 'proj-1',
          'key': 'k-$i',
          'source_text': 'src',
          'is_obsolete': 0,
          'created_at': 0,
          'updated_at': 0,
        });
      }
      // Seed 100 pending translation_versions (one per unit) so the
      // progress formula denominator covers all 100 units.
      for (var i = 0; i < 100; i++) {
        await db.insert('translation_versions', {
          'id': 'seed-v-$i',
          'unit_id': 'u-$i',
          'project_language_id': 'pl-1',
          'translated_text': null,
          'status': 'pending',
          'translation_source': 'unknown',
          'created_at': 0,
          'updated_at': 0,
        });
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      // Upsert 60 of the 100 units as translated (updates existing rows).
      final entities = List.generate(60, (i) {
        return TranslationVersion(
          id: 'v-$i',          // id is ignored on UPDATE path
          unitId: 'u-$i',
          projectLanguageId: 'pl-1',
          translatedText: 't-$i',
          status: TranslationVersionStatus.translated,
          translationSource: TranslationSource.tmExact,
          createdAt: now,
          updatedAt: now,
        );
      });

      await repo.upsertBatchOptimized(entities: entities);

      final plRow = await db.query('project_languages',
          where: 'id = ?', whereArgs: ['pl-1'], limit: 1);
      // 60 translated out of 100 non-obsolete units with versions → 60%.
      expect(plRow.first['progress_percent'], closeTo(60.0, 0.001));
    });
  });
}
