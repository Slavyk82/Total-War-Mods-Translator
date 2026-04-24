// Integration test verifying that bulk translation operations bump
// `projects.updated_at`.
//
// Regression: `acceptBatch`, `rejectBatch`, and `updateValidationBatch` only
// touched `translation_versions` and `project_languages` — not `projects`.
// The Projects screen's `exportOutdated` quick-filter relies on
// `project.updatedAt > lastPackExport.exportedAt + 60`, so a project that was
// bulk-translated or bulk-validated after its last export would stay out of
// the "Export outdated" filter even though its content had clearly changed.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
    // `trg_projects_updated_at` is self-referential (WHEN NEW.updated_at =
    // OLD.updated_at). It bumps `projects.updated_at` to `NOW()` whenever any
    // UPDATE on `projects` would leave the timestamp identical to the prior
    // value. We deliberately seed a stale timestamp (1000) to verify that
    // bulk ops bump it, so the self-trigger gets in the way. Drop it for the
    // test run — we're not testing it here and every bulk op writes its own
    // fresh `updated_at` anyway.
    await db.execute('DROP TRIGGER IF EXISTS trg_projects_updated_at');
  });

  tearDown(() => TestDatabase.close(db));

  /// Seed one game installation, one language, one project with
  /// [rowCount] translation_units and matching translation_versions.
  /// Every version starts at `status = 'needs_review'` with an old
  /// `projects.updated_at` timestamp so we can detect whether a bulk op
  /// bumps it.
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
        'status': 'needs_review',
        'validation_issues': null,
        'validation_schema_version': 0,
        'is_manually_edited': 0,
        'translation_source': 'manual',
        'created_at': 0,
        'updated_at': oldTimestamp,
      });
    }
    // Re-assert the stale timestamp — schema triggers on the inserts above
    // will have bumped it to `NOW()`.
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

  group('acceptBatch', () {
    test('bumps projects.updated_at for a small batch (triggers active)',
        () async {
      const oldTs = 1000;
      await seed(rowCount: 3, oldTimestamp: oldTs);

      final result = await versionRepo
          .acceptBatch(['ver-0000', 'ver-0001', 'ver-0002']);
      expect(result.isOk, isTrue, reason: result.toString());

      expect(await projectUpdatedAt(), greaterThan(oldTs));
    });

    test(
      'bumps projects.updated_at for a large batch (triggers disabled path)',
      () async {
        const oldTs = 1000;
        await seed(rowCount: 75, oldTimestamp: oldTs);

        final ids = List.generate(
          75,
          (i) => 'ver-${i.toString().padLeft(4, '0')}',
        );
        final result = await versionRepo.acceptBatch(ids);
        expect(result.isOk, isTrue, reason: result.toString());

        expect(await projectUpdatedAt(), greaterThan(oldTs));
      },
    );
  });

  group('rejectBatch', () {
    test('bumps projects.updated_at for a small batch (triggers active)',
        () async {
      const oldTs = 1000;
      await seed(rowCount: 3, oldTimestamp: oldTs);

      final result = await versionRepo
          .rejectBatch(['ver-0000', 'ver-0001', 'ver-0002']);
      expect(result.isOk, isTrue, reason: result.toString());

      expect(await projectUpdatedAt(), greaterThan(oldTs));
    });

    test(
      'bumps projects.updated_at for a large batch (triggers disabled path)',
      () async {
        const oldTs = 1000;
        await seed(rowCount: 75, oldTimestamp: oldTs);

        final ids = List.generate(
          75,
          (i) => 'ver-${i.toString().padLeft(4, '0')}',
        );
        final result = await versionRepo.rejectBatch(ids);
        expect(result.isOk, isTrue, reason: result.toString());

        expect(await projectUpdatedAt(), greaterThan(oldTs));
      },
    );
  });

  group('per-row update (trigger path)', () {
    test(
      'UPDATE on translation_versions.status bumps projects.updated_at '
      'via trg_update_project_language_progress',
      () async {
        const oldTs = 1000;
        await seed(rowCount: 1, oldTimestamp: oldTs);

        await db.rawUpdate(
          '''
          UPDATE translation_versions
          SET status = ?, updated_at = ?
          WHERE id = ?
          ''',
          ['translated', oldTs + 1, 'ver-0000'],
        );

        expect(await projectUpdatedAt(), greaterThan(oldTs));
      },
    );
  });

  group('updateValidationBatch', () {
    test('bumps projects.updated_at for a small batch (triggers active)',
        () async {
      const oldTs = 1000;
      await seed(rowCount: 3, oldTimestamp: oldTs);

      final updates = [
        (
          versionId: 'ver-0000',
          status: 'translated',
          validationIssues: null as String?,
          schemaVersion: 1,
        ),
        (
          versionId: 'ver-0001',
          status: 'translated',
          validationIssues: null as String?,
          schemaVersion: 1,
        ),
      ];
      final result = await versionRepo.updateValidationBatch(updates);
      expect(result.isOk, isTrue, reason: result.toString());

      expect(await projectUpdatedAt(), greaterThan(oldTs));
    });

    test(
      'bumps projects.updated_at for a large batch (triggers disabled path)',
      () async {
        const oldTs = 1000;
        await seed(rowCount: 75, oldTimestamp: oldTs);

        final updates = List.generate(
          75,
          (i) => (
            versionId: 'ver-${i.toString().padLeft(4, '0')}',
            status: 'translated',
            validationIssues: null as String?,
            schemaVersion: 1,
          ),
        );
        final result = await versionRepo.updateValidationBatch(updates);
        expect(result.isOk, isTrue, reason: result.toString());

        expect(await projectUpdatedAt(), greaterThan(oldTs));
      },
    );
  });
}
