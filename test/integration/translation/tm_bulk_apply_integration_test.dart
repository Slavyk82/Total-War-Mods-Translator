import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../helpers/test_database.dart';

/// End-to-end verification that the bulk apply path produces a consistent
/// schema state: rows persisted, FTS index populated, view cache updated,
/// project_languages.progress_percent recomputed.
void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => TestDatabase.close(db));

  /// Seed a project_language row and [unitCount] translation_unit rows,
  /// all belonging to 'proj-int' / 'pl-int'.
  Future<void> seedBase({int unitCount = 1000}) async {
    await db.insert('project_languages', {
      'id': 'pl-int',
      'project_id': 'proj-int',
      'language_id': 'fr',
      'status': 'pending',
      'progress_percent': 0.0,
      'created_at': 0,
      'updated_at': 0,
    });
    for (var i = 0; i < unitCount; i++) {
      await db.insert('translation_units', {
        'id': 'u-$i',
        'project_id': 'proj-int',
        'key': 'k-$i',
        'source_text': 'source $i',
        'is_obsolete': 0,
        'created_at': 0,
        'updated_at': 0,
      });
    }
  }

  test('bulk-apply 1000 TM matches leaves the schema fully consistent',
      () async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();
    await seedBase(unitCount: 1000);

    final now = DateTime.now().millisecondsSinceEpoch;
    final entities = List.generate(1000, (i) {
      return TranslationVersion(
        id: 'v-$i',
        unitId: 'u-$i',
        projectLanguageId: 'pl-int',
        translatedText: 'bonjour $i',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.tmExact,
        createdAt: now,
        updatedAt: now,
      );
    });

    final res = await repo.upsertBatchOptimized(entities: entities);
    expect(res.isOk, isTrue);
    expect(res.unwrap().inserted, 1000);

    // translation_versions populated.
    final versionsCount = (await db.rawQuery(
            'SELECT COUNT(*) AS c FROM translation_versions WHERE project_language_id = ?',
            ['pl-int']))
        .first['c'] as int;
    expect(versionsCount, 1000);

    // FTS index populated (one entry per non-empty translated_text).
    final ftsCount = (await db.rawQuery(
            'SELECT COUNT(*) AS c FROM translation_versions_fts'))
        .first['c'] as int;
    expect(ftsCount, 1000);

    // Progress = 100% (all 1000 units translated).
    final pl = await db.query('project_languages',
        where: 'id = ?', whereArgs: ['pl-int'], limit: 1);
    expect(pl.first['progress_percent'], closeTo(100.0, 0.001));

    // Triggers restored.
    final triggers = await db.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type = 'trigger'
        AND name IN (
          'trg_update_project_language_progress',
          'trg_translation_versions_fts_update',
          'trg_update_cache_on_version_change'
        )
    ''');
    expect(triggers, hasLength(3));
  });

  test('upsertBatchOptimized returns pre-existing ids on UPDATE path', () async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();

    // Seed project_language so the FK graph is present (FK enforcement is off
    // in test DBs, but we seed it anyway to match the real invariant).
    await db.insert('project_languages', {
      'id': 'pl-int',
      'project_id': 'proj-int',
      'language_id': 'fr',
      'status': 'pending',
      'progress_percent': 0.0,
      'created_at': 0,
      'updated_at': 0,
    });

    // Pre-seed 3 translation_versions with known ids.
    for (final (unitId, versionId) in [
      ('u-1', 'pre-1'),
      ('u-2', 'pre-2'),
      ('u-3', 'pre-3'),
    ]) {
      await db.insert('translation_versions', {
        'id': versionId,
        'unit_id': unitId,
        'project_language_id': 'pl-int',
        'translated_text': 'old',
        'status': 'translated',
        'translation_source': 'manual',
        'created_at': 1000,
        'updated_at': 1000,
      });
    }

    // Call with entities whose ids DIFFER from the pre-existing ids.
    final now = DateTime.now().millisecondsSinceEpoch;
    final entities = [
      TranslationVersion(
        id: 'new-1',
        unitId: 'u-1',
        projectLanguageId: 'pl-int',
        translatedText: 'fresh-1',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.tmExact,
        createdAt: now,
        updatedAt: now,
      ),
      TranslationVersion(
        id: 'new-2',
        unitId: 'u-2',
        projectLanguageId: 'pl-int',
        translatedText: 'fresh-2',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.tmExact,
        createdAt: now,
        updatedAt: now,
      ),
      TranslationVersion(
        id: 'new-3',
        unitId: 'u-3',
        projectLanguageId: 'pl-int',
        translatedText: 'fresh-3',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.tmExact,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final res = await repo.upsertBatchOptimized(entities: entities);
    final counts = res.unwrap();
    expect(counts.inserted, 0);
    expect(counts.updated, 3);
    expect(counts.effectiveVersionIds, equals(['pre-1', 'pre-2', 'pre-3']),
        reason:
            'must return pre-existing ids, not generated ones — this '
            'is the defect fix: TM history must reference real persisted ids');
  });
}
