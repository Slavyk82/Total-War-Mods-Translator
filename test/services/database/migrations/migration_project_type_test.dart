import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_project_type.dart';
import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<Set<String>> projectColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(projects)');
    return columns.map((c) => c['name'] as String).toSet();
  }

  /// Recreates the projects table as schema.sql defines it (before this
  /// migration ran): without project_type and source_language_code.
  Future<void> recreateBaseTable() async {
    await db.execute('DROP TABLE projects');
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mod_steam_id TEXT,
        mod_version TEXT,
        game_installation_id TEXT NOT NULL,
        source_file_path TEXT,
        output_file_path TEXT,
        last_update_check INTEGER,
        source_mod_updated INTEGER,
        batch_size INTEGER NOT NULL DEFAULT 25,
        parallel_batches INTEGER NOT NULL DEFAULT 5,
        custom_prompt TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        metadata TEXT,
        published_steam_id TEXT,
        published_at INTEGER,
        FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
        CHECK (batch_size > 0 AND batch_size <= 100),
        CHECK (parallel_batches > 0 AND parallel_batches <= 20),
        CHECK (created_at <= updated_at)
      )
    ''');
  }

  /// Simulates the half-applied state left by a crash between the two
  /// auto-committed ALTER TABLE statements: project_type exists but
  /// source_language_code does not.
  Future<void> stageHalfApplied() async {
    await recreateBaseTable();
    await db.execute(
        "ALTER TABLE projects ADD COLUMN project_type TEXT NOT NULL DEFAULT 'mod'");
    expect(await projectColumns(), contains('project_type'));
    expect(await projectColumns(), isNot(contains('source_language_code')));
  }

  group('ProjectTypeMigration', () {
    test('isApplied returns true when both columns exist', () async {
      final migration = ProjectTypeMigration();
      expect(await projectColumns(),
          containsAll(<String>['project_type', 'source_language_code']));
      expect(await migration.isApplied(), isTrue);
      expect(await migration.execute(), isFalse,
          reason: 'Nothing to do when both columns already exist.');
    });

    test('isApplied returns false on a half-applied database', () async {
      await stageHalfApplied();

      final migration = ProjectTypeMigration();
      expect(await migration.isApplied(), isFalse,
          reason: 'A database missing source_language_code is NOT fully '
              'migrated; returning true would skip the repair forever.');
    });

    test('execute repairs a half-applied database without failing on the '
        'already-present column', () async {
      await stageHalfApplied();

      final migration = ProjectTypeMigration();
      expect(await migration.execute(), isTrue);

      expect(await projectColumns(),
          containsAll(<String>['project_type', 'source_language_code']));
      expect(await migration.isApplied(), isTrue);
    });

    test('execute adds both columns when neither exists', () async {
      await recreateBaseTable();

      final migration = ProjectTypeMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      expect(await projectColumns(),
          containsAll(<String>['project_type', 'source_language_code']));
    });
  });
}
