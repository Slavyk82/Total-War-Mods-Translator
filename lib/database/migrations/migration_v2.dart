import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/service_exception.dart';
import '../../services/database/migration_service.dart';

/// Migration V2: Add Glossary, Search History, and Translation Memory FTS5
///
/// This migration adds:
/// - Glossary tables (glossaries, glossary_entries) with indexes and triggers
/// - Search management tables (search_history, saved_searches) with indexes
/// - Translation Memory FTS5 table with sync triggers
///
/// These tables are required for Phase 3 features:
/// - Glossary Management UI (Phase 3.2)
/// - Advanced Search UI (Phase 3.4)
/// - Translation Memory search optimization
class MigrationV2 extends Migration {
  @override
  int get version => 2;

  @override
  String get description =>
      'Add glossary tables, search history, and translation memory FTS5';

  @override
  Future<void> up(Transaction txn) async {
    // ========================================================================
    // GLOSSARY MANAGEMENT
    // ========================================================================

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS glossaries (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        is_global INTEGER NOT NULL DEFAULT 0,
        project_id TEXT,
        source_language_id TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        CHECK (is_global IN (0, 1)),
        CHECK ((is_global = 1 AND project_id IS NULL) OR (is_global = 0 AND project_id IS NOT NULL)),
        CHECK (created_at <= updated_at)
      )
    ''');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS glossary_entries (
        id TEXT PRIMARY KEY,
        glossary_id TEXT NOT NULL,
        source_term TEXT NOT NULL,
        target_term TEXT NOT NULL,
        category TEXT,
        definition TEXT,
        notes TEXT,
        is_forbidden INTEGER NOT NULL DEFAULT 0,
        case_sensitive INTEGER NOT NULL DEFAULT 0,
        usage_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (glossary_id) REFERENCES glossaries(id) ON DELETE CASCADE,
        CHECK (is_forbidden IN (0, 1)),
        CHECK (case_sensitive IN (0, 1)),
        CHECK (usage_count >= 0),
        CHECK (created_at <= updated_at),
        UNIQUE(glossary_id, source_term, case_sensitive)
      )
    ''');

    // Glossary indexes
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossaries_project ON glossaries(project_id, is_global)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossaries_languages ON glossaries(source_language_id, target_language_id)',
    );
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_glossaries_name ON glossaries(name)');

    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossary_entries_glossary ON glossary_entries(glossary_id)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossary_entries_source ON glossary_entries(source_term)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossary_entries_category ON glossary_entries(category)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_glossary_entries_usage ON glossary_entries(usage_count DESC)',
    );

    // Glossary triggers
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_glossaries_updated_at
      AFTER UPDATE ON glossaries
      BEGIN
        UPDATE glossaries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_glossary_entries_updated_at
      AFTER UPDATE ON glossary_entries
      BEGIN
        UPDATE glossary_entries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');

    // ========================================================================
    // SEARCH MANAGEMENT
    // ========================================================================

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        id TEXT PRIMARY KEY,
        query TEXT NOT NULL,
        scope TEXT NOT NULL,
        filters_json TEXT,
        result_count INTEGER NOT NULL,
        searched_at INTEGER NOT NULL,
        CHECK (scope IN ('source', 'target', 'both', 'key', 'all'))
      )
    ''');

    await txn.execute('''
      CREATE TABLE IF NOT EXISTS saved_searches (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        query TEXT NOT NULL,
        scope TEXT NOT NULL,
        filters_json TEXT,
        usage_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL,
        CHECK (scope IN ('source', 'target', 'both', 'key', 'all')),
        CHECK (usage_count >= 0)
      )
    ''');

    // Search indexes
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_search_history_searched ON search_history(searched_at DESC)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_searches_name ON saved_searches(name)',
    );
    await txn.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_searches_last_used ON saved_searches(last_used_at DESC)',
    );

    // ========================================================================
    // TRANSLATION MEMORY FTS5
    // ========================================================================

    await txn.execute('''
      CREATE VIRTUAL TABLE translation_memory_fts USING fts5(
        source_text,
        translated_text,
        game_context,
        content='translation_memory',
        content_rowid='rowid'
      )
    ''');

    // TM FTS5 sync triggers
    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_translation_memory_fts_insert AFTER INSERT ON translation_memory
      BEGIN
        INSERT INTO translation_memory_fts(rowid, source_text, translated_text, game_context)
        VALUES (new.rowid, new.source_text, new.translated_text, new.game_context);
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_translation_memory_fts_update AFTER UPDATE ON translation_memory
      BEGIN
        UPDATE translation_memory_fts
        SET source_text = new.source_text,
            translated_text = new.translated_text,
            game_context = new.game_context
        WHERE rowid = new.rowid;
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_translation_memory_fts_delete AFTER DELETE ON translation_memory
      BEGIN
        DELETE FROM translation_memory_fts WHERE rowid = old.rowid;
      END
    ''');
  }

  @override
  Future<void> verify(Database db) async {
    // Verify glossary tables exist
    await _verifyTableExists(db, 'glossaries');
    await _verifyTableExists(db, 'glossary_entries');

    // Verify search tables exist
    await _verifyTableExists(db, 'search_history');
    await _verifyTableExists(db, 'saved_searches');

    // Verify TM FTS5 table exists
    await _verifyTableExists(db, 'translation_memory_fts');

    // Verify glossary indexes
    await _verifyIndexExists(db, 'idx_glossaries_project');
    await _verifyIndexExists(db, 'idx_glossaries_languages');
    await _verifyIndexExists(db, 'idx_glossaries_name');
    await _verifyIndexExists(db, 'idx_glossary_entries_glossary');
    await _verifyIndexExists(db, 'idx_glossary_entries_source');
    await _verifyIndexExists(db, 'idx_glossary_entries_category');
    await _verifyIndexExists(db, 'idx_glossary_entries_usage');

    // Verify search indexes
    await _verifyIndexExists(db, 'idx_search_history_searched');
    await _verifyIndexExists(db, 'idx_saved_searches_name');
    await _verifyIndexExists(db, 'idx_saved_searches_last_used');

    // Verify glossary triggers
    await _verifyTriggerExists(db, 'trg_glossaries_updated_at');
    await _verifyTriggerExists(db, 'trg_glossary_entries_updated_at');

    // Verify TM FTS5 triggers
    await _verifyTriggerExists(db, 'trg_translation_memory_fts_insert');
    await _verifyTriggerExists(db, 'trg_translation_memory_fts_update');
    await _verifyTriggerExists(db, 'trg_translation_memory_fts_delete');
  }

  /// Verify a table exists in the database
  Future<void> _verifyTableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );

    if (result.isEmpty) {
      throw TWMTDatabaseException('Table $tableName was not created');
    }
  }

  /// Verify an index exists in the database
  Future<void> _verifyIndexExists(Database db, String indexName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
      [indexName],
    );

    if (result.isEmpty) {
      throw TWMTDatabaseException('Index $indexName was not created');
    }
  }

  /// Verify a trigger exists in the database
  Future<void> _verifyTriggerExists(Database db, String triggerName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name=?",
      [triggerName],
    );

    if (result.isEmpty) {
      throw TWMTDatabaseException('Trigger $triggerName was not created');
    }
  }

  @override
  Future<void> down(Transaction txn) async {
    // Drop triggers first
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_delete');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_update');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_insert');
    await txn.execute('DROP TRIGGER IF EXISTS trg_glossary_entries_updated_at');
    await txn.execute('DROP TRIGGER IF EXISTS trg_glossaries_updated_at');

    // Drop FTS5 table
    await txn.execute('DROP TABLE IF EXISTS translation_memory_fts');

    // Drop search tables
    await txn.execute('DROP TABLE IF EXISTS saved_searches');
    await txn.execute('DROP TABLE IF EXISTS search_history');

    // Drop glossary tables (entries first due to foreign key)
    await txn.execute('DROP TABLE IF EXISTS glossary_entries');
    await txn.execute('DROP TABLE IF EXISTS glossaries');

    // Note: Indexes are automatically dropped when tables are dropped
  }
}
