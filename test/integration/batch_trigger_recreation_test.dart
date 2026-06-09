// Integration test verifying that the bulk paths in
// TranslationVersionBatchMixin (`importBatch`, `upsertBatchOptimized`)
// recreate `trg_update_project_language_progress` identical to schema.sql.
//
// Regression: both methods recreated the trigger INLINE without the final
// `UPDATE projects SET updated_at = ...` block. CREATE TRIGGER is a persisted
// schema change, so after any >50-row import or TM bulk apply the live
// trigger permanently stopped propagating per-row edits to
// `projects.updated_at`, silently breaking the "Export outdated" filter for
// the rest of the DB session and beyond.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionRepository versionRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    versionRepo = TranslationVersionRepository();
    // Drop the self-referential projects trigger: we seed stale timestamps
    // on purpose and only want to observe bumps coming from
    // trg_update_project_language_progress (same setup as
    // projects_updated_at_on_bulk_ops_test.dart).
    await db.execute('DROP TRIGGER IF EXISTS trg_projects_updated_at');
  });

  tearDown(() => TestDatabase.close(db));

  /// Seed one game installation, one language, one project with [rowCount]
  /// translation_units and matching translation_versions.
  Future<void> seed({
    required int rowCount,
    required int oldTimestamp,
  }) async {
    await db.insert('game_installations', {
      'id': 'gi-1',
      'game_code': 'wh3',
      'game_name': 'WH3',
      'created_at': 0,
      'updated_at': 0,
    });
    await db.insert('languages', {
      'id': 'lang-fr',
      'code': 'fr',
      'name': 'French',
      'native_name': 'Français',
      'is_active': 1,
      'is_custom': 0,
    });
    await db.insert('projects', {
      'id': 'proj-1',
      'name': 'Alpha',
      'game_installation_id': 'gi-1',
      'batch_size': 25,
      'parallel_batches': 3,
      'created_at': 0,
      'updated_at': oldTimestamp,
      'has_mod_update_impact': 0,
      'project_type': 'mod',
    });
    await db.insert('project_languages', {
      'id': 'pl-1',
      'project_id': 'proj-1',
      'language_id': 'lang-fr',
      'progress_percent': 0.0,
      'created_at': 0,
      'updated_at': 0,
    });
    for (var i = 0; i < rowCount; i++) {
      final unitId = 'unit-${i.toString().padLeft(4, '0')}';
      final versionId = 'ver-${i.toString().padLeft(4, '0')}';
      await db.insert('translation_units', {
        'id': unitId,
        'project_id': 'proj-1',
        'key': 'key_$i',
        'source_text': 'Source $i',
        'is_obsolete': 0,
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert('translation_versions', {
        'id': versionId,
        'unit_id': unitId,
        'project_language_id': 'pl-1',
        'translated_text': 'Target $i',
        'status': 'pending',
        'validation_issues': null,
        'validation_schema_version': 0,
        'is_manually_edited': 0,
        'translation_source': 'manual',
        'created_at': 0,
        'updated_at': oldTimestamp,
      });
    }
    await db.rawUpdate(
      'UPDATE projects SET updated_at = ? WHERE id = ?',
      [oldTimestamp, 'proj-1'],
    );
  }

  Future<int> projectUpdatedAt() async {
    final rows = await db.rawQuery(
      'SELECT updated_at FROM projects WHERE id = ?',
      ['proj-1'],
    );
    return rows.first['updated_at'] as int;
  }

  /// The live trigger must still propagate a per-row status change to
  /// `projects.updated_at` (i.e. it was recreated identical to schema.sql).
  Future<void> expectLiveTriggerStillBumpsProject({required int oldTs}) async {
    // Re-stale the project timestamp, then make a per-row edit that fires
    // trg_update_project_language_progress.
    await db.rawUpdate(
      'UPDATE projects SET updated_at = ? WHERE id = ?',
      [oldTs, 'proj-1'],
    );
    await db.rawUpdate(
      '''
      UPDATE translation_versions
      SET status = ?, updated_at = ?
      WHERE id = ?
      ''',
      ['approved', oldTs + 1, 'ver-0000'],
    );
    expect(
      await projectUpdatedAt(),
      greaterThan(oldTs),
      reason: 'trg_update_project_language_progress must still contain the '
          'UPDATE projects bump after the bulk path recreated it',
    );

    final triggerSql = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'trg_update_project_language_progress'",
    );
    expect(triggerSql, hasLength(1));
    expect(
      (triggerSql.first['sql'] as String).contains('UPDATE projects'),
      isTrue,
      reason: 'recreated trigger DDL must match schema.sql',
    );
  }

  group('importBatch (>50 rows, triggers dropped/recreated)', () {
    test(
      'recreates trg_update_project_language_progress with the projects bump',
      () async {
        const oldTs = 1000;
        await seed(rowCount: 75, oldTimestamp: oldTs);

        final entities = List.generate(75, (i) {
          final unitId = 'unit-${i.toString().padLeft(4, '0')}';
          return TranslationVersion(
            id: 'new-ver-$i',
            unitId: unitId,
            projectLanguageId: 'pl-1',
            translatedText: 'Imported $i',
            status: TranslationVersionStatus.translated,
            translationSource: TranslationSource.manual,
            createdAt: 0,
            updatedAt: 0,
          );
        });
        final existingVersionIds = {
          for (var i = 0; i < 75; i++)
            'unit-${i.toString().padLeft(4, '0')}':
                'ver-${i.toString().padLeft(4, '0')}',
        };

        final result = await versionRepo.importBatch(
          entities: entities,
          existingVersionIds: existingVersionIds,
        );
        expect(result.isOk, isTrue, reason: result.toString());

        await expectLiveTriggerStillBumpsProject(oldTs: oldTs);
      },
    );
  });

  group('upsertBatchOptimized (>50 rows, triggers dropped/recreated)', () {
    test(
      'recreates trg_update_project_language_progress with the projects bump',
      () async {
        const oldTs = 1000;
        await seed(rowCount: 75, oldTimestamp: oldTs);

        final entities = List.generate(75, (i) {
          final unitId = 'unit-${i.toString().padLeft(4, '0')}';
          return TranslationVersion(
            id: 'new-ver-$i',
            unitId: unitId,
            projectLanguageId: 'pl-1',
            translatedText: 'Applied $i',
            status: TranslationVersionStatus.translated,
            translationSource: TranslationSource.tmExact,
            createdAt: 0,
            updatedAt: 0,
          );
        });

        final result =
            await versionRepo.upsertBatchOptimized(entities: entities);
        expect(result.isOk, isTrue, reason: result.toString());

        await expectLiveTriggerStillBumpsProject(oldTs: oldTs);
      },
    );
  });
}
