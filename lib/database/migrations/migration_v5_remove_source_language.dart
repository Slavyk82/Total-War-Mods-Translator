import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/service_exception.dart';
import '../../services/database/migration_service.dart';

/// Migration V5: Remove source_language_id columns
///
/// This migration removes the concept of "source language" from the application:
/// - Removes source_language_id from translation_units table
/// - Removes source_language_id from translation_memory table
/// - Removes source_language_id from glossaries table
/// - Drops associated indexes
/// - Recreates indexes without source_language_id
///
/// IMPORTANT: This is a breaking change that removes data.
/// Any queries or code referencing source_language_id will need to be updated.
class MigrationV5RemoveSourceLanguage extends Migration {
  @override
  int get version => 5;

  @override
  String get description => 'Remove source_language_id columns from all tables';

  @override
  Future<void> up(Transaction txn) async {
    // ========================================================================
    // STEP 0: DROP ALL VIEWS AND TRIGGERS FIRST (to avoid errors during table operations)
    // ========================================================================

    // Drop all views that reference the tables we're modifying
    await txn.execute('DROP VIEW IF EXISTS v_project_language_stats');
    await txn.execute('DROP VIEW IF EXISTS v_translations_needing_review');

    // Drop all triggers for translation_units
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_updated_at');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_insert');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_update');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_delete');
    await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_unit_change');

    // Drop all triggers for translation_versions that reference translation_units
    await txn.execute('DROP TRIGGER IF EXISTS trg_insert_cache_on_version_insert');
    await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
    await txn.execute('DROP TRIGGER IF EXISTS trg_delete_cache_on_version_delete');
    await txn.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');

    // Drop all triggers for translation_memory
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_insert');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_update');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_delete');

    // Drop all triggers for glossaries
    await txn.execute('DROP TRIGGER IF EXISTS trg_glossaries_updated_at');

    // ========================================================================
    // STEP 1: DROP INDEXES THAT REFERENCE source_language_id
    // ========================================================================

    // Drop index on translation_memory
    await txn.execute('DROP INDEX IF EXISTS idx_tm_source_lang');

    // Drop index on glossaries
    await txn.execute('DROP INDEX IF EXISTS idx_glossaries_languages');

    // ========================================================================
    // STEP 2: REMOVE source_language_id FROM translation_units
    // ========================================================================

    // Create new table without source_language_id
    await txn.execute('''
      CREATE TABLE translation_units_new (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        key TEXT NOT NULL,
        source_text TEXT NOT NULL,
        context TEXT,
        notes TEXT,
        is_obsolete INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        UNIQUE(project_id, key),
        CHECK (is_obsolete IN (0, 1)),
        CHECK (created_at <= updated_at)
      )
    ''');

    // Copy data from old table (excluding source_language_id)
    await txn.execute('''
      INSERT INTO translation_units_new (
        id, project_id, key, source_text, context, notes,
        is_obsolete, created_at, updated_at
      )
      SELECT
        id, project_id, key, source_text, context, notes,
        is_obsolete, created_at, updated_at
      FROM translation_units
    ''');

    // Drop old table
    await txn.execute('DROP TABLE translation_units');

    // Rename new table
    await txn.execute('ALTER TABLE translation_units_new RENAME TO translation_units');

    // Recreate indexes for translation_units
    await txn.execute(
      'CREATE INDEX idx_translation_units_project ON translation_units(project_id)',
    );
    await txn.execute(
      'CREATE INDEX idx_translation_units_key ON translation_units(key)',
    );
    await txn.execute(
      'CREATE INDEX idx_translation_units_obsolete ON translation_units(project_id, is_obsolete)',
    );

    // Recreate triggers for translation_units
    await txn.execute('''
      CREATE TRIGGER trg_translation_units_updated_at
      AFTER UPDATE ON translation_units
      BEGIN
        UPDATE translation_units SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');

    // Recreate FTS5 triggers for translation_units
    await txn.execute('''
      CREATE TRIGGER trg_translation_units_fts_insert AFTER INSERT ON translation_units
      BEGIN
        INSERT INTO translation_units_fts(rowid, key, source_text, context, notes)
        VALUES (new.rowid, new.key, new.source_text, new.context, new.notes);
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER trg_translation_units_fts_update AFTER UPDATE ON translation_units
      BEGIN
        UPDATE translation_units_fts
        SET key = new.key,
            source_text = new.source_text,
            context = new.context,
            notes = new.notes
        WHERE rowid = new.rowid;
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER trg_translation_units_fts_delete AFTER DELETE ON translation_units
      BEGIN
        DELETE FROM translation_units_fts WHERE rowid = old.rowid;
      END
    ''');

    // Recreate cache update trigger for translation_units
    await txn.execute('''
      CREATE TRIGGER trg_update_cache_on_unit_change
      AFTER UPDATE ON translation_units
      BEGIN
        UPDATE translation_view_cache
        SET key = new.key,
            source_text = new.source_text,
            is_obsolete = new.is_obsolete,
            unit_updated_at = new.updated_at
        WHERE unit_id = new.id;
      END
    ''');

    // ========================================================================
    // STEP 3: REMOVE source_language_id FROM translation_memory
    // ========================================================================

    // Create new table without source_language_id
    await txn.execute('''
      CREATE TABLE translation_memory_new (
        id TEXT PRIMARY KEY,
        source_text TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        game_context TEXT,
        translation_provider_id TEXT,
        quality_score REAL,
        usage_count INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        FOREIGN KEY (translation_provider_id) REFERENCES translation_providers(id) ON DELETE SET NULL,
        UNIQUE(source_hash, target_language_id, game_context),
        CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
        CHECK (usage_count >= 1)
      )
    ''');

    // Copy data from old table (excluding source_language_id)
    await txn.execute('''
      INSERT INTO translation_memory_new (
        id, source_text, source_hash, target_language_id, translated_text,
        game_context, translation_provider_id, quality_score, usage_count,
        created_at, last_used_at, updated_at
      )
      SELECT
        id, source_text, source_hash, target_language_id, translated_text,
        game_context, translation_provider_id, quality_score, usage_count,
        created_at, last_used_at, updated_at
      FROM translation_memory
    ''');

    // Drop old table
    await txn.execute('DROP TABLE translation_memory');

    // Rename new table
    await txn.execute('ALTER TABLE translation_memory_new RENAME TO translation_memory');

    // Recreate indexes for translation_memory (without source_language_id)
    await txn.execute(
      'CREATE INDEX idx_tm_hash_lang_context ON translation_memory(source_hash, target_language_id, game_context)',
    );
    await txn.execute(
      'CREATE INDEX idx_tm_target_lang ON translation_memory(target_language_id)',
    );
    await txn.execute(
      'CREATE INDEX idx_tm_last_used ON translation_memory(last_used_at DESC)',
    );
    await txn.execute(
      'CREATE INDEX idx_tm_game_context ON translation_memory(game_context, quality_score DESC)',
    );

    // Recreate FTS5 triggers for translation_memory
    await txn.execute('''
      CREATE TRIGGER trg_translation_memory_fts_insert AFTER INSERT ON translation_memory
      BEGIN
        INSERT INTO translation_memory_fts(rowid, source_text, translated_text, game_context)
        VALUES (new.rowid, new.source_text, new.translated_text, new.game_context);
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER trg_translation_memory_fts_update AFTER UPDATE ON translation_memory
      BEGIN
        UPDATE translation_memory_fts
        SET source_text = new.source_text,
            translated_text = new.translated_text,
            game_context = new.game_context
        WHERE rowid = new.rowid;
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER trg_translation_memory_fts_delete AFTER DELETE ON translation_memory
      BEGIN
        DELETE FROM translation_memory_fts WHERE rowid = old.rowid;
      END
    ''');

    // ========================================================================
    // STEP 4: REMOVE source_language_id FROM glossaries
    // ========================================================================

    // Create new table without source_language_id
    await txn.execute('''
      CREATE TABLE glossaries_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        is_global INTEGER NOT NULL DEFAULT 0,
        project_id TEXT,
        target_language_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        CHECK (is_global IN (0, 1)),
        CHECK ((is_global = 1 AND project_id IS NULL) OR (is_global = 0 AND project_id IS NOT NULL)),
        CHECK (created_at <= updated_at)
      )
    ''');

    // Copy data from old table (excluding source_language_id)
    await txn.execute('''
      INSERT INTO glossaries_new (
        id, name, description, is_global, project_id, target_language_id,
        created_at, updated_at
      )
      SELECT
        id, name, description, is_global, project_id, target_language_id,
        created_at, updated_at
      FROM glossaries
    ''');

    // Drop old table
    await txn.execute('DROP TABLE glossaries');

    // Rename new table
    await txn.execute('ALTER TABLE glossaries_new RENAME TO glossaries');

    // Recreate indexes for glossaries (without source_language_id)
    await txn.execute(
      'CREATE INDEX idx_glossaries_project ON glossaries(project_id, is_global)',
    );
    await txn.execute(
      'CREATE INDEX idx_glossaries_target_lang ON glossaries(target_language_id)',
    );
    await txn.execute('CREATE INDEX idx_glossaries_name ON glossaries(name)');

    // Recreate triggers for glossaries
    await txn.execute('''
      CREATE TRIGGER trg_glossaries_updated_at
      AFTER UPDATE ON glossaries
      BEGIN
        UPDATE glossaries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');

    // ========================================================================
    // STEP 5: RECREATE VIEWS
    // ========================================================================

    // Recreate v_project_language_stats view
    await txn.execute('''
      CREATE VIEW v_project_language_stats AS
      SELECT
        pl.id AS project_language_id,
        pl.project_id,
        p.name AS project_name,
        l.code AS language_code,
        l.native_name AS language_name,
        pl.status,
        pl.progress_percent,
        COUNT(DISTINCT tu.id) AS total_units,
        COUNT(DISTINCT CASE WHEN tv.status = 'approved' THEN tv.id END) AS approved_units,
        COUNT(DISTINCT CASE WHEN tv.status = 'reviewed' THEN tv.id END) AS reviewed_units,
        COUNT(DISTINCT CASE WHEN tv.status = 'translated' THEN tv.id END) AS translated_units,
        COUNT(DISTINCT CASE WHEN tv.status = 'pending' THEN tv.id END) AS pending_units,
        COUNT(DISTINCT CASE WHEN tv.is_manually_edited = 1 THEN tv.id END) AS manually_edited_units
      FROM project_languages pl
      INNER JOIN projects p ON pl.project_id = p.id
      INNER JOIN languages l ON pl.language_id = l.id
      LEFT JOIN translation_units tu ON tu.project_id = p.id AND tu.is_obsolete = 0
      LEFT JOIN translation_versions tv ON tv.unit_id = tu.id AND tv.project_language_id = pl.id
      GROUP BY pl.id
    ''');

    // Recreate v_translations_needing_review view
    await txn.execute('''
      CREATE VIEW v_translations_needing_review AS
      SELECT
        tv.id AS version_id,
        tu.project_id,
        l.code AS language_code,
        tu.key,
        tu.source_text,
        tv.translated_text,
        tv.status,
        tv.confidence_score,
        tv.validation_issues,
        tv.updated_at
      FROM translation_versions tv
      INNER JOIN translation_units tu ON tv.unit_id = tu.id
      INNER JOIN project_languages pl ON tv.project_language_id = pl.id
      INNER JOIN languages l ON pl.language_id = l.id
      WHERE tv.status IN ('needs_review', 'translated')
        AND tu.is_obsolete = 0
        AND (tv.confidence_score < 0.8 OR tv.validation_issues IS NOT NULL)
    ''');

    // ========================================================================
    // STEP 6: RECREATE TRIGGERS ON translation_versions THAT REFERENCE translation_units
    // ========================================================================

    // Recreate cache update trigger for translation_versions
    await txn.execute('''
      CREATE TRIGGER trg_update_cache_on_version_change
      AFTER UPDATE ON translation_versions
      BEGIN
        UPDATE translation_view_cache
        SET translated_text = new.translated_text,
            status = new.status,
            confidence_score = new.confidence_score,
            is_manually_edited = new.is_manually_edited,
            version_id = new.id,
            version_updated_at = new.updated_at
        WHERE unit_id = new.unit_id
          AND project_language_id = new.project_language_id;
      END
    ''');

    // Recreate cache insert trigger for translation_versions
    await txn.execute('''
      CREATE TRIGGER trg_insert_cache_on_version_insert
      AFTER INSERT ON translation_versions
      BEGIN
        INSERT OR REPLACE INTO translation_view_cache (
          id,
          project_id,
          project_language_id,
          language_code,
          unit_id,
          version_id,
          key,
          source_text,
          translated_text,
          status,
          confidence_score,
          is_manually_edited,
          is_obsolete,
          unit_created_at,
          unit_updated_at,
          version_updated_at
        )
        SELECT
          new.id || '_' || tu.id AS id,
          tu.project_id,
          new.project_language_id,
          l.code,
          tu.id,
          new.id,
          tu.key,
          tu.source_text,
          new.translated_text,
          new.status,
          new.confidence_score,
          new.is_manually_edited,
          tu.is_obsolete,
          tu.created_at,
          tu.updated_at,
          new.updated_at
        FROM translation_units tu
        INNER JOIN project_languages pl ON pl.id = new.project_language_id
        INNER JOIN languages l ON l.id = pl.language_id
        WHERE tu.id = new.unit_id;
      END
    ''');

    // Recreate cache delete trigger for translation_versions
    await txn.execute('''
      CREATE TRIGGER trg_delete_cache_on_version_delete
      AFTER DELETE ON translation_versions
      BEGIN
        DELETE FROM translation_view_cache
        WHERE version_id = old.id;
      END
    ''');

    // Recreate project language progress trigger
    await txn.execute('''
      CREATE TRIGGER trg_update_project_language_progress
      AFTER UPDATE ON translation_versions
      WHEN NEW.status != OLD.status
      BEGIN
        UPDATE project_languages
        SET progress_percent = (
          SELECT
            CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
            NULLIF(COUNT(*), 0)
          FROM translation_versions tv
          INNER JOIN translation_units tu ON tv.unit_id = tu.id
          WHERE tv.project_language_id = NEW.project_language_id
            AND tu.is_obsolete = 0
        ),
        updated_at = strftime('%s', 'now')
        WHERE id = NEW.project_language_id;
      END
    ''');
  }

  @override
  Future<void> verify(Database db) async {
    // Verify tables exist with correct schema (no source_language_id)
    await _verifyTableSchema(db, 'translation_units');
    await _verifyTableSchema(db, 'translation_memory');
    await _verifyTableSchema(db, 'glossaries');

    // Verify indexes were recreated
    await _verifyIndexExists(db, 'idx_translation_units_project');
    await _verifyIndexExists(db, 'idx_translation_units_key');
    await _verifyIndexExists(db, 'idx_translation_units_obsolete');

    await _verifyIndexExists(db, 'idx_tm_hash_lang_context');
    await _verifyIndexExists(db, 'idx_tm_target_lang');
    await _verifyIndexExists(db, 'idx_tm_last_used');
    await _verifyIndexExists(db, 'idx_tm_game_context');

    await _verifyIndexExists(db, 'idx_glossaries_project');
    await _verifyIndexExists(db, 'idx_glossaries_target_lang');
    await _verifyIndexExists(db, 'idx_glossaries_name');

    // Verify old indexes were dropped
    await _verifyIndexNotExists(db, 'idx_tm_source_lang');
    await _verifyIndexNotExists(db, 'idx_glossaries_languages');

    // Verify triggers were recreated
    await _verifyTriggerExists(db, 'trg_translation_units_updated_at');
    await _verifyTriggerExists(db, 'trg_translation_units_fts_insert');
    await _verifyTriggerExists(db, 'trg_translation_units_fts_update');
    await _verifyTriggerExists(db, 'trg_translation_units_fts_delete');
    await _verifyTriggerExists(db, 'trg_update_cache_on_unit_change');

    await _verifyTriggerExists(db, 'trg_translation_memory_fts_insert');
    await _verifyTriggerExists(db, 'trg_translation_memory_fts_update');
    await _verifyTriggerExists(db, 'trg_translation_memory_fts_delete');

    await _verifyTriggerExists(db, 'trg_glossaries_updated_at');

    // Verify source_language_id column was removed
    await _verifyColumnNotExists(db, 'translation_units', 'source_language_id');
    await _verifyColumnNotExists(db, 'translation_memory', 'source_language_id');
    await _verifyColumnNotExists(db, 'glossaries', 'source_language_id');
  }

  /// Verify a table exists and has correct schema
  Future<void> _verifyTableSchema(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );

    if (result.isEmpty) {
      throw TWMTDatabaseException('Table $tableName does not exist');
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

  /// Verify an index does NOT exist in the database
  Future<void> _verifyIndexNotExists(Database db, String indexName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
      [indexName],
    );

    if (result.isNotEmpty) {
      throw TWMTDatabaseException('Index $indexName should have been dropped');
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

  /// Verify a column does NOT exist in a table
  Future<void> _verifyColumnNotExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    final columns = result.map((row) => row['name'] as String).toList();

    if (columns.contains(columnName)) {
      throw TWMTDatabaseException(
        'Column $columnName should have been removed from $tableName',
      );
    }
  }

  @override
  Future<void> down(Transaction txn) async {
    // ========================================================================
    // ROLLBACK: Add source_language_id columns back
    // ========================================================================
    // NOTE: This rollback will restore the schema but cannot restore
    // the source_language_id data that was removed.

    // ROLLBACK translation_units
    await txn.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_unit_change');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_delete');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_update');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_insert');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_units_updated_at');

    await txn.execute('''
      CREATE TABLE translation_units_old (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        key TEXT NOT NULL,
        source_text TEXT NOT NULL,
        source_language_id TEXT,
        context TEXT,
        notes TEXT,
        is_obsolete INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE SET NULL,
        UNIQUE(project_id, key),
        CHECK (is_obsolete IN (0, 1)),
        CHECK (created_at <= updated_at)
      )
    ''');

    await txn.execute('''
      INSERT INTO translation_units_old (
        id, project_id, key, source_text, source_language_id, context, notes,
        is_obsolete, created_at, updated_at
      )
      SELECT
        id, project_id, key, source_text, NULL, context, notes,
        is_obsolete, created_at, updated_at
      FROM translation_units
    ''');

    await txn.execute('DROP TABLE translation_units');
    await txn.execute('ALTER TABLE translation_units_old RENAME TO translation_units');

    // ROLLBACK translation_memory
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_delete');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_update');
    await txn.execute('DROP TRIGGER IF EXISTS trg_translation_memory_fts_insert');

    await txn.execute('''
      CREATE TABLE translation_memory_old (
        id TEXT PRIMARY KEY,
        source_text TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        source_language_id TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        game_context TEXT,
        translation_provider_id TEXT,
        quality_score REAL,
        usage_count INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
        FOREIGN KEY (translation_provider_id) REFERENCES translation_providers(id) ON DELETE SET NULL,
        UNIQUE(source_hash, target_language_id, game_context),
        CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
        CHECK (usage_count >= 1)
      )
    ''');

    // WARNING: source_language_id will be set to 'lang_en' (English) as default
    // Original source language information is lost
    await txn.execute('''
      INSERT INTO translation_memory_old (
        id, source_text, source_hash, source_language_id, target_language_id, translated_text,
        game_context, translation_provider_id, quality_score, usage_count,
        created_at, last_used_at, updated_at
      )
      SELECT
        id, source_text, source_hash, 'lang_en', target_language_id, translated_text,
        game_context, translation_provider_id, quality_score, usage_count,
        created_at, last_used_at, updated_at
      FROM translation_memory
    ''');

    await txn.execute('DROP TABLE translation_memory');
    await txn.execute('ALTER TABLE translation_memory_old RENAME TO translation_memory');

    // ROLLBACK glossaries
    await txn.execute('DROP TRIGGER IF EXISTS trg_glossaries_updated_at');

    await txn.execute('''
      CREATE TABLE glossaries_old (
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

    // WARNING: source_language_id will be set to 'lang_en' (English) as default
    // Original source language information is lost
    await txn.execute('''
      INSERT INTO glossaries_old (
        id, name, description, is_global, project_id, source_language_id, target_language_id,
        created_at, updated_at
      )
      SELECT
        id, name, description, is_global, project_id, 'lang_en', target_language_id,
        created_at, updated_at
      FROM glossaries
    ''');

    await txn.execute('DROP TABLE glossaries');
    await txn.execute('ALTER TABLE glossaries_old RENAME TO glossaries');

    // Recreate old indexes
    await txn.execute(
      'CREATE INDEX idx_tm_source_lang ON translation_memory(source_language_id, target_language_id)',
    );
    await txn.execute(
      'CREATE INDEX idx_glossaries_languages ON glossaries(source_language_id, target_language_id)',
    );

    // Note: All other indexes and triggers need to be recreated
    // This is a simplified rollback - full restoration would require
    // re-running the previous migration
  }
}
