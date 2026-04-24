import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_glossary_game_code_partial.dart';
import '../../../helpers/test_database.dart';

/// Reset the `glossaries` table to its pre-migration shape so that
/// [GlossaryGameCodePartialMigration] has real work to do. The
/// [TestDatabase.openMigrated] helper applies every migration registered
/// in the registry, which means by the time a test starts, this
/// migration has already run on the empty table. To exercise the actual
/// populate/rebuild logic we drop the post-migration `glossaries` and
/// recreate the original pre-migration schema.
Future<void> _resetToPreMigrationGlossaries() async {
  await DatabaseService.execute('DROP TABLE IF EXISTS glossaries');
  await DatabaseService.execute('''
    CREATE TABLE glossaries (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      description TEXT,
      is_global INTEGER NOT NULL DEFAULT 0,
      game_installation_id TEXT,
      target_language_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE CASCADE,
      FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
      CHECK (is_global IN (0, 1)),
      CHECK ((is_global = 1 AND game_installation_id IS NULL) OR (is_global = 0 AND game_installation_id IS NOT NULL)),
      CHECK (created_at <= updated_at)
    )
  ''');
}

void main() {
  late Database db;

  setUp(() async {
    db = await TestDatabase.openMigrated(clearSeeds: true);
    await _resetToPreMigrationGlossaries();
  });
  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('GlossaryGameCodePartialMigration', () {
    test('isApplied returns true after execute', () async {
      await GlossaryGameCodePartialMigration().execute();
      final applied = await GlossaryGameCodePartialMigration().isApplied();
      expect(applied, isTrue);
    });

    test('populates game_code for game-specific glossaries', () async {
      await DatabaseService.execute(
        "INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at) VALUES ('gi1', 'wh3', 'WH3', 0, 0)",
      );
      await DatabaseService.execute(
        "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_fr', 'fr', 'French', 'Français', 1)",
      );
      await DatabaseService.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, target_language_id, created_at, updated_at) VALUES ('g1', 'WH3 FR', 0, 'gi1', 'lang_fr', 0, 0)",
      );

      final ok = await GlossaryGameCodePartialMigration().execute();

      expect(ok, isTrue);
      final rows = await DatabaseService.database
          .rawQuery('SELECT game_code FROM glossaries WHERE id = ?', ['g1']);
      expect(rows.first['game_code'], 'wh3');
    });

    test('leaves game_code NULL for universal glossaries', () async {
      await DatabaseService.execute(
        "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_fr', 'fr', 'French', 'Français', 1)",
      );
      await DatabaseService.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('gu', 'Universal FR', 1, 'lang_fr', 0, 0)",
      );

      await GlossaryGameCodePartialMigration().execute();

      final rows = await DatabaseService.database
          .rawQuery('SELECT game_code FROM glossaries WHERE id = ?', ['gu']);
      expect(rows.first['game_code'], isNull);
    });

    test('drops UNIQUE(name) — same name insertable twice after migration', () async {
      await DatabaseService.execute(
        "INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at) VALUES ('gi1', 'wh3', 'WH3', 0, 0)",
      );
      await DatabaseService.execute(
        "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_fr', 'fr', 'French', 'Français', 1)",
      );
      await DatabaseService.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('g1', 'Dup', 1, 'lang_fr', 0, 0)",
      );

      await GlossaryGameCodePartialMigration().execute();

      // Same name should now be insertable twice
      await DatabaseService.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, target_language_id, game_code, created_at, updated_at) VALUES ('g2', 'Dup', 0, 'gi1', 'lang_fr', 'wh3', 0, 0)",
      );
      final rows = await DatabaseService.database
          .rawQuery("SELECT COUNT(*) as cnt FROM glossaries WHERE name = 'Dup'");
      expect(rows.first['cnt'], 2);
    });

    test('drops CHECK on is_global/game_installation_id — previously-violating row insertable', () async {
      await DatabaseService.execute(
        "INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at) VALUES ('gi1', 'wh3', 'WH3', 0, 0)",
      );
      await DatabaseService.execute(
        "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_fr', 'fr', 'French', 'Français', 1)",
      );

      await GlossaryGameCodePartialMigration().execute();

      // Before the migration, the CHECK constraint required:
      //   (is_global = 1 AND game_installation_id IS NULL)
      //   OR (is_global = 0 AND game_installation_id IS NOT NULL)
      // A row with is_global=1 AND game_installation_id='gi1' would have
      // violated it. After the migration it must be insertable.
      await DatabaseService.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, target_language_id, game_code, created_at, updated_at) VALUES ('gv', 'Violator', 1, 'gi1', 'lang_fr', 'wh3', 0, 0)",
      );
      final rows = await DatabaseService.database
          .rawQuery("SELECT is_global, game_installation_id FROM glossaries WHERE id = 'gv'");
      expect(rows.first['is_global'], 1);
      expect(rows.first['game_installation_id'], 'gi1');
    });

    test('is idempotent on already-migrated DB', () async {
      await GlossaryGameCodePartialMigration().execute();
      final applied = await GlossaryGameCodePartialMigration().isApplied();
      expect(applied, isTrue);
      final secondRun = await GlossaryGameCodePartialMigration().execute();
      // Second run may return true or false but must not throw.
      expect(secondRun, anyOf(isTrue, isFalse));
      final applied2 = await GlossaryGameCodePartialMigration().isApplied();
      expect(applied2, isTrue);
    });
  });
}
