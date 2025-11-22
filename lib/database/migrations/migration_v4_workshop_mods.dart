import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../services/database/migration_service.dart';

/// Migration V4: Workshop Mods metadata storage
///
/// Adds workshop_mods table to store Steam Workshop mod metadata.
///
/// This migration includes:
/// - workshop_mods table with all Steam Workshop metadata fields
/// - 7 indexes for performance optimization
/// - FTS5 virtual table for full-text search
/// - Triggers for FTS5 sync and auto-update timestamps
class MigrationV4WorkshopMods extends Migration {
  @override
  int get version => 4;

  @override
  String get description => 'Add workshop_mods table for Steam Workshop metadata with FTS5 search';

  @override
  Future<void> up(Transaction txn) async {
    await _createWorkshopModsTable(txn);
    await _createIndexes(txn);
    await _createFTS5Table(txn);
    await _createTriggers(txn);
  }

  @override
  Future<void> down(Transaction txn) async {
    // Drop triggers first
    await txn.execute('DROP TRIGGER IF EXISTS trg_workshop_mods_updated_at');
    await txn.execute('DROP TRIGGER IF EXISTS trg_workshop_mods_fts_delete');
    await txn.execute('DROP TRIGGER IF EXISTS trg_workshop_mods_fts_update');
    await txn.execute('DROP TRIGGER IF EXISTS trg_workshop_mods_fts_insert');

    // Drop FTS5 table
    await txn.execute('DROP TABLE IF EXISTS workshop_mods_fts');

    // Drop indexes (will be dropped with table, but explicit for clarity)
    await txn.execute('DROP INDEX IF EXISTS idx_workshop_mods_last_checked');
    await txn.execute('DROP INDEX IF EXISTS idx_workshop_mods_updated');
    await txn.execute('DROP INDEX IF EXISTS idx_workshop_mods_title');
      await txn.execute('DROP INDEX IF EXISTS idx_workshop_mods_app_updated');
      await txn.execute('DROP INDEX IF EXISTS idx_workshop_mods_app_id');
    await txn.execute('DROP INDEX IF EXISTS idx_workshop_mods_workshop_id');

    // Drop table
    await txn.execute('DROP TABLE IF EXISTS workshop_mods');
  }

  @override
  Future<void> verify(Database db) async {
    // Verify table exists
    final tableResult = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='workshop_mods'",
    );

    if (tableResult.isEmpty) {
      throw Exception('workshop_mods table was not created');
    }

    // Verify all indexes exist (6 total)
    final indexResult = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_workshop_mods_%'",
    );

    if (indexResult.length < 6) {
      throw Exception('Expected 6 workshop_mods indexes, found ${indexResult.length}');
    }

    // Verify FTS5 table exists
    final ftsResult = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='workshop_mods_fts'",
    );

    if (ftsResult.isEmpty) {
      throw Exception('workshop_mods_fts FTS5 table was not created');
    }

    // Verify triggers exist (4 total)
    final triggerResult = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'trg_workshop_mods_%'",
    );

    if (triggerResult.length < 4) {
      throw Exception('Expected 4 workshop_mods triggers, found ${triggerResult.length}');
    }
  }

  Future<void> _createWorkshopModsTable(Transaction txn) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS workshop_mods (
        -- Primary key (UUID following TWMT standard)
        id TEXT PRIMARY KEY,

        -- Steam Workshop identifiers
        workshop_id TEXT NOT NULL UNIQUE,
        app_id INTEGER NOT NULL,

        -- Mod metadata
        title TEXT NOT NULL,
        workshop_url TEXT NOT NULL,

        -- File information
        file_size INTEGER,

        -- Timestamps (Unix timestamps from Steam API)
        time_created INTEGER,
        time_updated INTEGER,

        -- Statistics
        subscriptions INTEGER DEFAULT 0,

        -- Collections/Dependencies (JSON arrays stored as TEXT)
        tags TEXT,

        -- Local metadata
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_checked_at INTEGER,

        -- Constraints
        CHECK (file_size IS NULL OR file_size >= 0),
        CHECK (subscriptions >= 0),
        CHECK (created_at <= updated_at)
      )
    ''');
  }

  Future<void> _createIndexes(Transaction txn) async {
    // UNIQUE index on workshop_id (primary lookup)
    await txn.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_workshop_mods_workshop_id
      ON workshop_mods(workshop_id)
    ''');

    // Index on app_id (filter by game)
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_workshop_mods_app_id
      ON workshop_mods(app_id)
    ''');

    // Composite index on app_id + time_updated (recent mods per game)
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_workshop_mods_app_updated
      ON workshop_mods(app_id, time_updated DESC)
    ''');

    // Index on title for searches (case-insensitive)
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_workshop_mods_title
      ON workshop_mods(title COLLATE NOCASE)
    ''');

    // Index on updated_at (recently updated mods)
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_workshop_mods_updated
      ON workshop_mods(updated_at DESC)
    ''');

    // Index on last_checked_at (find mods needing update check)
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_workshop_mods_last_checked
      ON workshop_mods(last_checked_at)
    ''');
  }

  Future<void> _createFTS5Table(Transaction txn) async {
    // FTS5 virtual table for fast full-text search
    await txn.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS workshop_mods_fts USING fts5(
        title,
        tags,
        content='workshop_mods',
        content_rowid='rowid'
      )
    ''');
  }

  Future<void> _createTriggers(Transaction txn) async {
    // Trigger: Insert into FTS5 when new mod is added
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_fts_insert
      AFTER INSERT ON workshop_mods
      BEGIN
        INSERT INTO workshop_mods_fts(rowid, title, tags)
        VALUES (new.rowid, new.title, new.tags);
      END
    ''');

    // Trigger: Update FTS5 when mod is updated
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_fts_update
      AFTER UPDATE ON workshop_mods
      BEGIN
        UPDATE workshop_mods_fts
        SET title = new.title,
            tags = new.tags
        WHERE rowid = new.rowid;
      END
    ''');

    // Trigger: Delete from FTS5 when mod is deleted
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_fts_delete
      AFTER DELETE ON workshop_mods
      BEGIN
        DELETE FROM workshop_mods_fts WHERE rowid = old.rowid;
      END
    ''');

    // Trigger: Auto-update timestamp on modification
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_updated_at
      AFTER UPDATE ON workshop_mods
      WHEN NEW.updated_at = OLD.updated_at
      BEGIN
        UPDATE workshop_mods SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');
  }
}
