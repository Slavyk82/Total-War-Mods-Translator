import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../config/database_config.dart';
import '../../models/common/service_exception.dart';
import 'database_service.dart';
import '../shared/logging_service.dart';
import '../text/french_hyphen_fixer.dart';

/// Migration service for database schema initialization.
///
/// Simplified service that creates fresh databases from schema.sql.
/// No incremental migrations - fresh install only.
class MigrationService {
  MigrationService._();

  /// Initialize database schema for fresh databases
  ///
  /// For fresh databases (version 0), executes schema.sql to create
  /// all tables, indexes, triggers, views, and seed data.
  ///
  /// Throws [TWMTDatabaseException] if schema execution fails.
  static Future<void> runMigrations() async {
    final logging = LoggingService.instance;
    if (!DatabaseService.isInitialized) {
      throw StateError('DatabaseService must be initialized before migrations');
    }

    final currentVersion = await DatabaseService.getVersion();
    final targetVersion = DatabaseConfig.databaseVersion;

    logging.debug('Checking database version', {
      'currentVersion': currentVersion,
      'targetVersion': targetVersion,
    });

    if (currentVersion == targetVersion) {
      logging.debug('Database is already up to date');
      return;
    }

    if (currentVersion > targetVersion) {
      throw TWMTDatabaseException(
        'Database version ($currentVersion) is higher than app version ($targetVersion). '
        'Please update the application.',
      );
    }

    // Only support fresh database initialization
    if (currentVersion == 0) {
      logging.info('Fresh database detected - initializing schema');
      await _initializeSchema();
      logging.info('Schema initialization completed successfully');
    } else {
      // Existing database with different version - not supported
      throw TWMTDatabaseException(
        'Database migration not supported. '
        'Please delete the database file and restart the application. '
        'Database path: ${await DatabaseConfig.getDatabasePath()}',
      );
    }
  }

  /// Execute schema.sql to create all database objects
  static Future<void> _initializeSchema() async {
    final logging = LoggingService.instance;

    try {
      // Load schema from assets
      final schema = await rootBundle.loadString('lib/database/schema.sql');
      logging.debug('Schema loaded, executing...');

      await DatabaseService.transaction((txn) async {
        // Execute schema
        await _executeSqlScript(txn, schema);

        // Update version
        await txn.execute('PRAGMA user_version = ${DatabaseConfig.databaseVersion}');
      });

      // Set version in database service
      await DatabaseService.setVersion(DatabaseConfig.databaseVersion);

      // Verify schema
      await _verifySchema();
      logging.debug('Schema verified successfully');
    } catch (e, stackTrace) {
      logging.error('Schema initialization failed', e, stackTrace);
      throw TWMTDatabaseException(
        'Schema initialization failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Verify that schema was created correctly
  static Future<void> _verifySchema() async {
    final db = DatabaseService.database;

    // Verify core tables exist
    final requiredTables = [
      'languages',
      'translation_providers',
      'game_installations',
      'projects',
      'project_languages',
      'translation_units',
      'translation_versions',
      'translation_memory',
      'glossaries',
      'glossary_entries',
      'workshop_mods',
      'llm_provider_models',
      'settings',
    ];

    final tablesResult = await db.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type='table' AND name NOT LIKE 'sqlite_%'
    ''');
    final existingTables = tablesResult.map((r) => r['name'] as String).toSet();

    for (final table in requiredTables) {
      if (!existingTables.contains(table)) {
        throw TWMTDatabaseException('Required table not found: $table');
      }
    }

    // Verify FTS5 tables exist
    final requiredFtsTables = [
      'translation_units_fts',
      'translation_versions_fts',
      'translation_memory_fts',
      'workshop_mods_fts',
    ];

    for (final fts in requiredFtsTables) {
      if (!existingTables.contains(fts)) {
        throw TWMTDatabaseException('Required FTS5 table not found: $fts');
      }
    }

    // Verify seed data
    final languageCount = await db.rawQuery('SELECT COUNT(*) as cnt FROM languages');
    if ((languageCount.first['cnt'] as int) < 6) {
      throw TWMTDatabaseException('Language seed data missing');
    }

    final providerCount = await db.rawQuery('SELECT COUNT(*) as cnt FROM translation_providers');
    if ((providerCount.first['cnt'] as int) < 3) {
      throw TWMTDatabaseException('Translation provider seed data missing');
    }
  }

  /// Execute a SQL script file
  static Future<void> _executeSqlScript(Transaction txn, String script) async {
    final statements = _splitSqlScript(script);

    for (final statement in statements) {
      if (statement.trim().isNotEmpty) {
        await txn.execute(statement);
      }
    }
  }

  /// Split SQL script into individual statements
  static List<String> _splitSqlScript(String script) {
    final statements = <String>[];
    final buffer = StringBuffer();
    bool inString = false;
    bool inComment = false;
    bool inMultiLineComment = false;
    int beginEndDepth = 0;

    for (int i = 0; i < script.length; i++) {
      final char = script[i];
      final nextChar = i + 1 < script.length ? script[i + 1] : '';

      // Handle multi-line comments
      if (!inString && char == '/' && nextChar == '*') {
        inMultiLineComment = true;
        i++;
        continue;
      }

      if (inMultiLineComment && char == '*' && nextChar == '/') {
        inMultiLineComment = false;
        i++;
        continue;
      }

      if (inMultiLineComment) {
        continue;
      }

      // Handle single-line comments
      if (!inString && (char == '-' && nextChar == '-')) {
        inComment = true;
        continue;
      }

      if (inComment && char == '\n') {
        inComment = false;
        buffer.write(char);
        continue;
      }

      if (inComment) {
        continue;
      }

      // Handle string literals
      if (char == "'") {
        inString = !inString;
        buffer.write(char);
        continue;
      }

      // Track BEGIN...END blocks
      if (!inString && !inComment && !inMultiLineComment) {
        if (_isKeywordAt(script, i, 'BEGIN')) {
          beginEndDepth++;
        } else if (_isKeywordAt(script, i, 'END')) {
          beginEndDepth--;
        }
      }

      // Split on semicolon if not in string and not inside BEGIN...END block
      if (!inString && beginEndDepth == 0 && char == ';') {
        statements.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }

      buffer.write(char);
    }

    // Add remaining statement if any
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      statements.add(remaining);
    }

    return statements;
  }

  /// Check if a SQL keyword exists at the given position
  static bool _isKeywordAt(String script, int position, String keyword) {
    final endPos = position + keyword.length;

    if (endPos > script.length) return false;

    if (position > 0) {
      final prevChar = script[position - 1];
      if (RegExp(r'[a-zA-Z0-9_]').hasMatch(prevChar)) {
        return false;
      }
    }

    final word = script.substring(position, endPos);
    if (word.toUpperCase() != keyword.toUpperCase()) {
      return false;
    }

    if (endPos < script.length) {
      final nextChar = script[endPos];
      if (RegExp(r'[a-zA-Z0-9_]').hasMatch(nextChar)) {
        return false;
      }
    }

    return true;
  }

  /// Ensure performance indexes exist on the database.
  ///
  /// This method can be called on any database (fresh or existing) to ensure
  /// that recommended performance indexes are present. Uses CREATE INDEX IF NOT EXISTS
  /// so it's safe to run multiple times.
  ///
  /// These indexes were identified through database analysis as high-priority
  /// optimizations for common query patterns.
  static Future<void> ensurePerformanceIndexes() async {
    final logging = LoggingService.instance;
    if (!DatabaseService.isInitialized) {
      throw StateError('DatabaseService must be initialized before applying indexes');
    }

    logging.debug('Ensuring performance indexes exist');

    const performanceIndexes = [
      // Index on translation_version_history.version_id for FK lookups
      '''CREATE INDEX IF NOT EXISTS idx_translation_version_history_version
         ON translation_version_history(version_id)''',
      // Composite index for common JOIN pattern between units and versions
      '''CREATE INDEX IF NOT EXISTS idx_translation_versions_unit_proj_lang
         ON translation_versions(unit_id, project_language_id)''',
    ];

    try {
      for (final indexSql in performanceIndexes) {
        await DatabaseService.execute(indexSql);
      }
      logging.info('Performance indexes verified/created successfully');
    } catch (e, stackTrace) {
      logging.error('Failed to create performance indexes', e, stackTrace);
      // Non-fatal: indexes are optimization, not required for functionality
    }

    // Ensure new tables exist for existing databases
    await _ensureModUpdateAnalysisCacheTable();

    // Ensure translation_source column exists
    await _ensureTranslationSourceColumn();

    // Ensure compilation tables exist
    await _ensureCompilationTables();

    // Fix escaped newlines in existing translations
    await _fixEscapedNewlinesInTranslations();

    // Fix backslash-before-newline pattern from LLM translations
    await _fixBackslashBeforeNewlines();

    // Ensure is_hidden column exists on workshop_mods
    await _ensureWorkshopModsHiddenColumn();

    // Ensure llm_custom_rules table exists
    await _ensureLlmCustomRulesTable();

    // Ensure is_custom column exists on languages table
    await _ensureLanguagesCustomColumn();

    // Fix missing hyphens in French translations
    // DISABLED: await FrenchHyphenFixer.fixMissingHyphens();

    // Remove deprecated score columns from database
    await _removeScoreColumns();
  }

  /// Remove deprecated quality_score and confidence_score columns.
  ///
  /// These columns are no longer used in the application.
  /// SQLite doesn't support DROP COLUMN directly, but we leave the columns
  /// in place as they don't harm functionality. The application code
  /// no longer references them.
  static Future<void> _removeScoreColumns() async {
    final logging = LoggingService.instance;
    logging.debug('Score columns are deprecated but left in place for backward compatibility');
    // Note: SQLite doesn't support DROP COLUMN. The columns remain but are unused.
    // Future database recreations will not include these columns.
  }

  /// Ensure mod_update_analysis_cache table exists for existing databases.
  ///
  /// This allows existing databases to get the new caching functionality
  /// without requiring a full database re-creation.
  static Future<void> _ensureModUpdateAnalysisCacheTable() async {
    final logging = LoggingService.instance;

    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS mod_update_analysis_cache (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL,
          pack_file_path TEXT NOT NULL,
          file_last_modified INTEGER NOT NULL,
          new_units_count INTEGER NOT NULL DEFAULT 0,
          removed_units_count INTEGER NOT NULL DEFAULT 0,
          modified_units_count INTEGER NOT NULL DEFAULT 0,
          total_pack_units INTEGER NOT NULL DEFAULT 0,
          total_project_units INTEGER NOT NULL DEFAULT 0,
          analyzed_at INTEGER NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
          UNIQUE(project_id, pack_file_path)
        )
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_mod_update_analysis_cache_project
        ON mod_update_analysis_cache(project_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_mod_update_analysis_cache_pack_path
        ON mod_update_analysis_cache(pack_file_path)
      ''');

      logging.debug('mod_update_analysis_cache table verified/created');
    } catch (e, stackTrace) {
      logging.error('Failed to create mod_update_analysis_cache table', e, stackTrace);
      // Non-fatal: caching is optimization, not required for functionality
    }
  }

  /// Ensure translation_source column exists in translation_versions table.
  ///
  /// This column tracks the source of each translation (manual, tm_exact, tm_fuzzy, llm).
  static Future<void> _ensureTranslationSourceColumn() async {
    final logging = LoggingService.instance;

    try {
      // Check if column exists
      final columns = await DatabaseService.database.rawQuery(
        "PRAGMA table_info(translation_versions)"
      );
      final hasColumn = columns.any((col) => col['name'] == 'translation_source');

      if (!hasColumn) {
        await DatabaseService.execute('''
          ALTER TABLE translation_versions
          ADD COLUMN translation_source TEXT DEFAULT 'unknown'
        ''');
        logging.info('Added translation_source column to translation_versions');
      }
    } catch (e, stackTrace) {
      logging.error('Failed to add translation_source column', e, stackTrace);
      // Non-fatal: display will fall back to confidence-based detection
    }
  }

  /// Ensure compilation tables exist for existing databases.
  ///
  /// Creates compilations and compilation_projects tables for
  /// grouping multiple projects into a single pack file.
  static Future<void> _ensureCompilationTables() async {
    final logging = LoggingService.instance;

    try {
      // Create compilations table
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS compilations (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          prefix TEXT NOT NULL DEFAULT '!!!!!!!!!!_fr_compilation_twmt_',
          pack_name TEXT NOT NULL,
          game_installation_id TEXT NOT NULL,
          last_output_path TEXT,
          last_generated_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
          CHECK (created_at <= updated_at)
        )
      ''');

      // Create compilation_projects junction table
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS compilation_projects (
          id TEXT PRIMARY KEY,
          compilation_id TEXT NOT NULL,
          project_id TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          added_at INTEGER NOT NULL,
          FOREIGN KEY (compilation_id) REFERENCES compilations(id) ON DELETE CASCADE,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
          UNIQUE(compilation_id, project_id)
        )
      ''');

      // Create indexes
      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_compilations_game
        ON compilations(game_installation_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_compilation_projects_compilation
        ON compilation_projects(compilation_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_compilation_projects_project
        ON compilation_projects(project_id)
      ''');

      // Add language_id column if it doesn't exist (migration for existing databases)
      final compilationColumns = await DatabaseService.database.rawQuery(
        "PRAGMA table_info(compilations)"
      );
      final hasLanguageIdColumn = compilationColumns.any((col) => col['name'] == 'language_id');

      if (!hasLanguageIdColumn) {
        await DatabaseService.execute('''
          ALTER TABLE compilations ADD COLUMN language_id TEXT
            REFERENCES languages(id) ON DELETE SET NULL
        ''');
        logging.info('Added language_id column to compilations');
      }

      logging.debug('Compilation tables verified/created');
    } catch (e, stackTrace) {
      logging.error('Failed to create compilation tables', e, stackTrace);
      // Non-fatal: feature will be unavailable but app still works
    }
  }

  /// Fix escaped newline sequences in existing translations.
  ///
  /// Prior versions incorrectly stored `\n` (backslash + n) instead of actual
  /// newline characters in translation_versions.translated_text. This causes
  /// double-escaping at export time, resulting in `\\n` in game which displays
  /// as `//` in-game.
  ///
  /// This migration converts stored `\n` sequences to actual newline characters
  /// to match how source texts are stored.
  static Future<void> _fixEscapedNewlinesInTranslations() async {
    final logging = LoggingService.instance;

    try {
      logging.debug('Checking for escaped newlines in translations...');

      // Check if there are any translations with escaped newlines
      // The backslash-n sequence is stored as two characters: \ (char 92) and n
      // Using INSTR to find the literal backslash-n sequence
      final countResult = await DatabaseService.database.rawQuery('''
        SELECT COUNT(*) as cnt FROM translation_versions
        WHERE INSTR(translated_text, char(92) || 'n') > 0
      ''');
      final count = countResult.first['cnt'] as int;

      logging.debug('Found $count translations with potential escaped newlines');

      if (count == 0) {
        return;
      }

      logging.info('Fixing escaped newlines in $count translation records (this may take a moment)...');

      // Replace \r\n and \n sequences with actual newlines
      // char(92) = backslash, char(10) = newline
      // Process in batches to avoid blocking UI
      const batchSize = 500;
      var totalProcessed = 0;

      while (true) {
        final updated = await DatabaseService.database.rawUpdate('''
          UPDATE translation_versions
          SET translated_text = REPLACE(
            REPLACE(translated_text, char(92) || 'r' || char(92) || 'n', char(10)),
            char(92) || 'n',
            char(10)
          )
          WHERE id IN (
            SELECT id FROM translation_versions
            WHERE INSTR(translated_text, char(92) || 'n') > 0
            LIMIT $batchSize
          )
        ''');

        if (updated == 0) break;

        totalProcessed += updated;
        logging.debug('Processed $totalProcessed / $count translations');

        // Yield to UI thread
        await Future.delayed(Duration.zero);
      }

      logging.info('Fixed escaped newlines, rebuilding search index...');

      // FTS rebuild - skip if it takes too long, search will still work
      // but may have stale data until next full reindex
      try {
        await DatabaseService.execute('''
          INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')
        ''').timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            logging.warning('FTS rebuild timed out, will be done lazily');
          },
        );
      } catch (e) {
        logging.warning('FTS rebuild skipped: $e');
      }

      logging.info('Fixed escaped newlines in $count translation records');
    } catch (e, stackTrace) {
      logging.error('Failed to fix escaped newlines', e, stackTrace);
      // Non-fatal: translations will still work, just display incorrectly
    }
  }

  /// Fix backslash-before-newline pattern in translations.
  ///
  /// Some LLM translations incorrectly produced backslash + newline sequences
  /// like `text.\<newline>` instead of just `text.<newline>`.
  /// This causes `\\` to appear before line breaks in game.
  ///
  /// This migration removes spurious backslashes before newlines.
  static Future<void> _fixBackslashBeforeNewlines() async {
    final logging = LoggingService.instance;

    try {
      logging.debug('Checking for backslash-before-newline patterns...');

      // Check for backslash followed by newline (char 92 + char 10)
      final countResult = await DatabaseService.database.rawQuery('''
        SELECT COUNT(*) as cnt FROM translation_versions
        WHERE INSTR(translated_text, char(92) || char(10)) > 0
      ''');
      final count = countResult.first['cnt'] as int;

      logging.debug('Found $count translations with backslash-before-newline');

      if (count == 0) {
        return;
      }

      logging.info('Fixing backslash-before-newline in $count translations...');

      // Replace backslash + newline with just newline
      // Process in batches
      const batchSize = 500;
      var totalProcessed = 0;

      while (true) {
        final updated = await DatabaseService.database.rawUpdate('''
          UPDATE translation_versions
          SET translated_text = REPLACE(translated_text, char(92) || char(10), char(10))
          WHERE id IN (
            SELECT id FROM translation_versions
            WHERE INSTR(translated_text, char(92) || char(10)) > 0
            LIMIT $batchSize
          )
        ''');

        if (updated == 0) break;

        totalProcessed += updated;
        logging.debug('Processed $totalProcessed / $count translations');

        // Yield to UI thread
        await Future.delayed(Duration.zero);
      }

      logging.info('Fixed backslash-before-newline in $totalProcessed translations');
    } catch (e, stackTrace) {
      logging.error('Failed to fix backslash-before-newline', e, stackTrace);
      // Non-fatal
    }
  }

  /// Ensure is_hidden column exists on workshop_mods table.
  ///
  /// This column allows users to hide mods from the main list.
  static Future<void> _ensureWorkshopModsHiddenColumn() async {
    final logging = LoggingService.instance;

    try {
      // Check if column exists
      final columns = await DatabaseService.database.rawQuery(
        "PRAGMA table_info(workshop_mods)"
      );
      final hasColumn = columns.any((col) => col['name'] == 'is_hidden');

      if (!hasColumn) {
        await DatabaseService.execute('''
          ALTER TABLE workshop_mods
          ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0
        ''');
        logging.info('Added is_hidden column to workshop_mods');
      }
    } catch (e, stackTrace) {
      logging.error('Failed to add is_hidden column', e, stackTrace);
      // Non-fatal: hiding feature will be unavailable but app still works
    }
  }

  /// Ensure llm_custom_rules table exists for existing databases.
  ///
  /// This table stores custom rules that users can add to LLM translation prompts.
  /// Rules can be global (project_id = NULL) or project-specific.
  static Future<void> _ensureLlmCustomRulesTable() async {
    final logging = LoggingService.instance;

    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS llm_custom_rules (
          id TEXT PRIMARY KEY,
          rule_text TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          project_id TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          CHECK (is_enabled IN (0, 1)),
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        )
      ''');

      // Add project_id column if it doesn't exist (migration for existing databases)
      final rulesColumns = await DatabaseService.database.rawQuery(
        "PRAGMA table_info(llm_custom_rules)"
      );
      final hasProjectIdColumn = rulesColumns.any((col) => col['name'] == 'project_id');

      if (!hasProjectIdColumn) {
        await DatabaseService.execute('''
          ALTER TABLE llm_custom_rules ADD COLUMN project_id TEXT
            REFERENCES projects(id) ON DELETE CASCADE
        ''');
        logging.info('Added project_id column to llm_custom_rules');
      }

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_llm_custom_rules_enabled_order
        ON llm_custom_rules(is_enabled, sort_order)
      ''');

      // Index for project-specific rules queries
      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_llm_custom_rules_project
        ON llm_custom_rules(project_id)
      ''');

      logging.debug('llm_custom_rules table verified/created');
    } catch (e, stackTrace) {
      logging.error('Failed to create llm_custom_rules table', e, stackTrace);
      // Non-fatal: custom rules feature will be unavailable but app still works
    }
  }

  /// Ensure is_custom column exists on languages table.
  ///
  /// This column allows users to add custom languages that can be deleted,
  /// while system languages (is_custom = 0) are read-only.
  static Future<void> _ensureLanguagesCustomColumn() async {
    final logging = LoggingService.instance;

    try {
      // Check if column exists
      final columns = await DatabaseService.database.rawQuery(
        "PRAGMA table_info(languages)"
      );
      final hasColumn = columns.any((col) => col['name'] == 'is_custom');

      if (!hasColumn) {
        await DatabaseService.execute('''
          ALTER TABLE languages
          ADD COLUMN is_custom INTEGER NOT NULL DEFAULT 0
        ''');
        logging.info('Added is_custom column to languages');
      }
    } catch (e, stackTrace) {
      logging.error('Failed to add is_custom column to languages', e, stackTrace);
      // Non-fatal: custom languages feature will be unavailable but app still works
    }
  }

  /// Check if database needs initialization
  static Future<bool> needsMigration() async {
    if (!DatabaseService.isInitialized) {
      return true;
    }

    final currentVersion = await DatabaseService.getVersion();
    return currentVersion == 0;
  }

  /// Get current database version
  static Future<int> getCurrentVersion() async {
    if (!DatabaseService.isInitialized) {
      return 0;
    }
    return await DatabaseService.getVersion();
  }

  /// Get target database version (from config)
  static int getTargetVersion() {
    return DatabaseConfig.databaseVersion;
  }

  /// Reset database to initial state
  ///
  /// WARNING: This will delete all data and recreate the database.
  static Future<void> reset() async {
    await DatabaseService.deleteDatabase();
    await DatabaseService.initialize();
    await runMigrations();
  }
}
