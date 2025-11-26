import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../config/database_config.dart';
import '../../models/common/service_exception.dart';
import 'database_service.dart';
import '../shared/logging_service.dart';

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
