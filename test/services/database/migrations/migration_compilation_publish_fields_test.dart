import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_compilation_publish_fields.dart';
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

  Future<Set<String>> compilationColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(compilations)');
    return columns.map((c) => c['name'] as String).toSet();
  }

  /// Recreates the compilations table as CompilationTablesMigration left it
  /// (before this migration ran). DROP COLUMN cannot be used for staging:
  /// it triggers a full schema re-parse that fails on an unrelated legacy
  /// view in the test database.
  Future<void> recreateBaseTable() async {
    await db.execute('DROP TABLE compilations');
    await db.execute('''
      CREATE TABLE compilations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        prefix TEXT NOT NULL DEFAULT '!!!!!!!!!!_fr_compilation_twmt_',
        pack_name TEXT NOT NULL,
        game_installation_id TEXT NOT NULL,
        language_id TEXT,
        last_output_path TEXT,
        last_generated_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
        CHECK (created_at <= updated_at)
      )
    ''');
  }

  /// Simulates the half-applied state left by a crash between the two
  /// auto-committed ALTER TABLE statements: published_steam_id exists but
  /// published_at does not.
  Future<void> stageHalfApplied() async {
    await recreateBaseTable();
    await db.execute(
        'ALTER TABLE compilations ADD COLUMN published_steam_id TEXT');
    expect(await compilationColumns(), contains('published_steam_id'));
    expect(await compilationColumns(), isNot(contains('published_at')));
  }

  group('CompilationPublishFieldsMigration', () {
    test('isApplied returns true when both columns exist', () async {
      final migration = CompilationPublishFieldsMigration();
      expect(await compilationColumns(),
          containsAll(<String>['published_steam_id', 'published_at']));
      expect(await migration.isApplied(), isTrue);
      expect(await migration.execute(), isFalse,
          reason: 'Nothing to do when both columns already exist.');
    });

    test('isApplied returns false on a half-applied database', () async {
      await stageHalfApplied();

      final migration = CompilationPublishFieldsMigration();
      expect(await migration.isApplied(), isFalse,
          reason: 'A database missing published_at is NOT fully migrated; '
              'returning true would skip the repair forever.');
    });

    test('execute repairs a half-applied database without failing on the '
        'already-present column', () async {
      await stageHalfApplied();

      final migration = CompilationPublishFieldsMigration();
      expect(await migration.execute(), isTrue);

      expect(await compilationColumns(),
          containsAll(<String>['published_steam_id', 'published_at']));
      expect(await migration.isApplied(), isTrue);
    });

    test('execute adds both columns when neither exists', () async {
      await recreateBaseTable();

      final migration = CompilationPublishFieldsMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      expect(await compilationColumns(),
          containsAll(<String>['published_steam_id', 'published_at']));
    });
  });
}
