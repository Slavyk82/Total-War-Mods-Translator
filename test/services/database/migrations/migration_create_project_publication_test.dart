import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_create_project_publication.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await TestDatabase.openMigrated();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<Set<String>> tables() async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  group('CreateProjectPublicationMigration', () {
    test('creates the table when absent', () async {
      await db.execute('DROP TABLE IF EXISTS project_publication');
      expect(await tables(), isNot(contains('project_publication')));

      await CreateProjectPublicationMigration().execute();

      expect(await tables(), contains('project_publication'));
    });

    test('backfills from legacy projects.published_steam_id, preferring fr',
        () async {
      await db.execute('DROP TABLE IF EXISTS project_publication');

      await db.insert('languages', {
        'id': 'lang-fr',
        'code': 'fr',
        'name': 'French',
        'native_name': 'Français',
        'is_active': 1,
      });
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.insert('projects', {
        'id': 'proj-1',
        'name': 'Legendary Lore',
        'mod_steam_id': '2789857945',
        'game_installation_id': 'gi-1',
        'batch_size': 25,
        'parallel_batches': 3,
        'created_at': now,
        'updated_at': now,
        'project_type': 'mod',
        'published_steam_id': '3664274763',
        'published_at': 1777103299,
      });
      await db.insert('project_languages', {
        'id': 'pl-1',
        'project_id': 'proj-1',
        'language_id': 'lang-fr',
        'progress_percent': 0,
        'created_at': now,
        'updated_at': now,
      });

      await CreateProjectPublicationMigration().execute();

      final rows = await db.query('project_publication',
          where: 'project_id = ?', whereArgs: ['proj-1']);
      expect(rows, hasLength(1));
      expect(rows.first['language_code'], 'fr');
      expect(rows.first['steam_id'], '3664274763');
      expect(rows.first['published_at'], 1777103299);
    });

    test('is idempotent — running twice does not duplicate or throw',
        () async {
      await CreateProjectPublicationMigration().execute();
      await CreateProjectPublicationMigration().execute();
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='project_publication'",
      );
      expect(rows, hasLength(1));
    });
  });
}
