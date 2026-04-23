import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Phase 1 of the game-specific glossary refactor.
///
/// Adds `game_code` to `glossaries`, populates it from `game_installations`
/// for game-specific rows, and strips the now-obsolete `UNIQUE(name)` and
/// CHECK constraints. Universals keep `game_code = NULL` until the user
/// resolves them via [GlossaryMigrationService].
class GlossaryGameCodePartialMigration extends Migration {
  final ILoggingService _logger;

  GlossaryGameCodePartialMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'glossary_game_code_partial';

  @override
  String get description =>
      'Add game_code to glossaries, drop obsolete CHECK/UNIQUE constraints';

  @override
  int get priority => 130;

  @override
  Future<bool> isApplied() async {
    final cols = await DatabaseService.database
        .rawQuery('PRAGMA table_info(glossaries)');
    return cols.any((row) => row['name'] == 'game_code');
  }

  @override
  Future<bool> execute() async {
    if (await isApplied()) return false;

    try {
      // SQLite's schema validation during ALTER TABLE ... RENAME re-checks
      // every view/trigger in the database. A pre-existing latent bug —
      // `v_translations_needing_review` references a `confidence_score`
      // column that was never present on `translation_versions` — would
      // make the rename fail in a database that still has that view.
      // `legacy_alter_table = 1` tells SQLite to skip that full-schema
      // validation during this migration only. Restored afterward.
      await DatabaseService.database.execute('PRAGMA legacy_alter_table = 1');
      try {
        await DatabaseService.database.transaction((txn) async {
          await txn.execute('ALTER TABLE glossaries ADD COLUMN game_code TEXT');
          await txn.execute('''
            UPDATE glossaries
            SET game_code = (
              SELECT gi.game_code
              FROM game_installations gi
              WHERE gi.id = glossaries.game_installation_id
            )
            WHERE is_global = 0
          ''');

          // Rebuild to drop UNIQUE(name) and the is_global CHECK constraint.
          await txn.execute('''
            CREATE TABLE glossaries_new (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT,
              is_global INTEGER NOT NULL DEFAULT 0,
              game_installation_id TEXT,
              game_code TEXT,
              target_language_id TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE CASCADE,
              FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
              CHECK (created_at <= updated_at)
            )
          ''');
          await txn.execute('''
            INSERT INTO glossaries_new
              (id, name, description, is_global, game_installation_id, game_code,
               target_language_id, created_at, updated_at)
            SELECT id, name, description, is_global, game_installation_id, game_code,
                   target_language_id, created_at, updated_at
            FROM glossaries
          ''');
          await txn.execute('DROP TABLE glossaries');
          await txn.execute('ALTER TABLE glossaries_new RENAME TO glossaries');

          // Recreate the indexes defined in schema.sql for glossaries.
          // They were dropped together with the original table.
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_glossaries_game ON glossaries(game_installation_id, is_global)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_glossaries_target_language ON glossaries(target_language_id)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_glossaries_name ON glossaries(name)');

          // Recreate the updated_at trigger dropped with the original table.
          await txn.execute('''
            CREATE TRIGGER IF NOT EXISTS trg_glossaries_updated_at
            AFTER UPDATE ON glossaries
            WHEN NEW.updated_at = OLD.updated_at
            BEGIN
                UPDATE glossaries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
            END
          ''');
        });
      } finally {
        await DatabaseService.database.execute('PRAGMA legacy_alter_table = 0');
      }

      _logger.info('glossary_game_code_partial migration applied');
      return true;
    } catch (e, stackTrace) {
      _logger.error('glossary_game_code_partial migration failed', e, stackTrace);
      return false;
    }
  }
}
