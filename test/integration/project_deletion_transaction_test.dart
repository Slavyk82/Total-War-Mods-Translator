import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/projects/project_deletion_service.dart';
import 'package:twmt/services/projects/project_language_deletion_service.dart';

import '../helpers/test_database.dart';

/// Integration tests pinning the transactional behavior of the deletion
/// services: deletion must be atomic, must not touch other projects, must
/// restore the globally-dropped triggers, and on failure must roll everything
/// back (triggers included).
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Future<void> lang(String id, String code) => db.insert('languages', {
          'id': id,
          'code': code,
          'name': code,
          'native_name': code,
          'is_active': 1,
        });
    Future<void> project(String id) => db.insert('projects', {
          'id': id,
          'name': 'Project $id',
          'game_installation_id': 'game-1',
          'created_at': now,
          'updated_at': now,
        });
    Future<void> projectLanguage(String id, String projectId, String langId) =>
        db.insert('project_languages', {
          'id': id,
          'project_id': projectId,
          'language_id': langId,
          'status': 'pending',
          'progress_percent': 0,
          'created_at': now,
          'updated_at': now,
        });
    Future<void> unit(String id, String projectId, String key) =>
        db.insert('translation_units', {
          'id': id,
          'project_id': projectId,
          'key': key,
          'source_text': 'src $key',
          'is_obsolete': 0,
          'created_at': now,
          'updated_at': now,
        });
    Future<void> version(String id, String unitId, String plId) =>
        db.insert('translation_versions', {
          'id': id,
          'unit_id': unitId,
          'project_language_id': plId,
          'translated_text': 'tr $id',
          'is_manually_edited': 0,
          'status': 'translated',
          'created_at': now,
          'updated_at': now,
        });

    await lang('lang_en', 'en');

    // Project A — the deletion target.
    await project('A');
    await projectLanguage('plA', 'A', 'lang_en');
    await unit('uA1', 'A', 'A_KEY_1');
    await unit('uA2', 'A', 'A_KEY_2');
    await version('vA1', 'uA1', 'plA');
    await version('vA2', 'uA2', 'plA');

    // Project B — must remain completely untouched.
    await project('B');
    await projectLanguage('plB', 'B', 'lang_en');
    await unit('uB1', 'B', 'B_KEY_1');
    await version('vB1', 'uB1', 'plB');
  });

  tearDown(() => TestDatabase.close(db));

  Future<int> count(String sql, [List<Object?> args = const []]) async {
    final rows = await db.rawQuery(sql, args);
    return (rows.first.values.first as int?) ?? 0;
  }

  Future<Set<String>> triggerNames() async {
    final rows = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'trigger'");
    return rows.map((r) => r['name'] as String).toSet();
  }

  group('ProjectDeletionServiceV2', () {
    test('deletes the target project and leaves other projects intact',
        () async {
      final triggersBefore = await triggerNames();
      expect(triggersBefore, isNotEmpty);

      final result = await ProjectDeletionServiceV2().deleteProject('A');
      expect(result.isOk, isTrue);

      // Project A fully gone.
      expect(await count('SELECT COUNT(*) FROM projects WHERE id = ?', ['A']), 0);
      expect(
          await count(
              'SELECT COUNT(*) FROM project_languages WHERE project_id = ?',
              ['A']),
          0);
      expect(
          await count(
              'SELECT COUNT(*) FROM translation_units WHERE project_id = ?',
              ['A']),
          0);
      expect(
          await count(
            'SELECT COUNT(*) FROM translation_versions WHERE project_language_id = ?',
            ['plA'],
          ),
          0);
      expect(
          await count(
              'SELECT COUNT(*) FROM translation_view_cache WHERE project_id = ?',
              ['A']),
          0);

      // Project B untouched.
      expect(await count('SELECT COUNT(*) FROM projects WHERE id = ?', ['B']), 1);
      expect(
          await count(
              'SELECT COUNT(*) FROM translation_units WHERE project_id = ?',
              ['B']),
          1);
      expect(
          await count(
            'SELECT COUNT(*) FROM translation_versions WHERE project_language_id = ?',
            ['plB'],
          ),
          1);

      // Triggers restored to exactly the pre-deletion set.
      expect(await triggerNames(), triggersBefore);
    });

    test('rolls back and restores triggers when the project does not exist',
        () async {
      final triggersBefore = await triggerNames();

      final result =
          await ProjectDeletionServiceV2().deleteProject('NOPE');
      expect(result.isErr, isTrue);

      // Nothing deleted anywhere (A and B both intact).
      expect(await count('SELECT COUNT(*) FROM projects'), 2);
      expect(await count('SELECT COUNT(*) FROM translation_versions'), 3);

      // Rollback restored the dropped triggers.
      expect(await triggerNames(), triggersBefore);
    });
  });

  group('ProjectLanguageDeletionService', () {
    test('deletes one project language without touching the other', () async {
      final triggersBefore = await triggerNames();

      final result =
          await ProjectLanguageDeletionService().deleteProjectLanguage('plA');
      expect(result.isOk, isTrue);

      // plA and its versions gone.
      expect(
          await count('SELECT COUNT(*) FROM project_languages WHERE id = ?',
              ['plA']),
          0);
      expect(
          await count(
            'SELECT COUNT(*) FROM translation_versions WHERE project_language_id = ?',
            ['plA'],
          ),
          0);

      // The units themselves belong to the project, not the language, so they
      // remain; plB and its version are untouched.
      expect(
          await count('SELECT COUNT(*) FROM project_languages WHERE id = ?',
              ['plB']),
          1);
      expect(
          await count(
            'SELECT COUNT(*) FROM translation_versions WHERE project_language_id = ?',
            ['plB'],
          ),
          1);

      expect(await triggerNames(), triggersBefore);
    });
  });
}
