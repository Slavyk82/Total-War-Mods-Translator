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
