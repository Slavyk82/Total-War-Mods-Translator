import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../config/database_config.dart';
import '../../models/common/service_exception.dart';
import 'database_service.dart';
import '../../database/migrations/migration_v1.dart';
import '../../database/migrations/migration_v2.dart';
import '../../database/migrations/migration_v3_performance_indexes.dart';
import '../../database/migrations/migration_v4_workshop_mods.dart';
import '../../database/migrations/migration_v5_remove_source_language.dart';
import '../../database/migrations/migration_v6_llm_provider_models.dart';
import '../../database/migrations/migration_v7_event_store.dart';
import '../../database/migrations/migration_v8_tm_performance_index.dart';
import '../shared/logging_service.dart';

/// Migration service for database schema versioning and updates.
///
/// Manages database migrations in a safe, versioned manner with rollback
/// support and verification of seed data.
///
/// This service ensures:
/// - Migrations are executed in order
/// - Each migration is idempotent
/// - Failed migrations trigger rollback
/// - Seed data is verified after migration
class MigrationService {
  MigrationService._();

  /// List of all migrations in order
  static final List<Migration> _migrations = [
    MigrationV1(),
    MigrationV2(),
    MigrationV3PerformanceIndexes(),
    MigrationV4WorkshopMods(),
    MigrationV5RemoveSourceLanguage(),
    MigrationV6LlmProviderModels(),
    MigrationV7EventStore(),
    MigrationV8TmPerformanceIndex(),
  ];

  /// Run all pending migrations
  ///
  /// This method checks the current database version and executes all
  /// migrations that haven't been applied yet.
  ///
  /// Throws [TWMTDatabaseException] if migration fails.
  static Future<void> runMigrations() async {
    final logging = LoggingService.instance;
    if (!DatabaseService.isInitialized) {
      throw StateError('DatabaseService must be initialized before migrations');
    }

    final currentVersion = await DatabaseService.getVersion();
    final targetVersion = DatabaseConfig.databaseVersion;

    logging.debug('Checking migrations', {
      'currentVersion': currentVersion,
      'targetVersion': targetVersion,
    });

    if (currentVersion == targetVersion) {
      // Database is already up to date
      logging.debug('Database is already up to date');
      return;
    }

    if (currentVersion > targetVersion) {
      throw TWMTDatabaseException(
        'Database version ($currentVersion) is higher than app version ($targetVersion). '
        'Please update the application.',
      );
    }

    // Run migrations from current to target version
    for (int version = currentVersion + 1;
        version <= targetVersion;
        version++) {
      logging.info('Running migration to version $version');
      final migration = _getMigration(version);
      if (migration == null) {
        throw TWMTDatabaseException(
          'Migration for version $version not found',
        );
      }

      await _executeMigration(migration, version);
      logging.info('Migration to version $version completed successfully');
    }
  }

  /// Get migration for a specific version
  static Migration? _getMigration(int version) {
    try {
      return _migrations.firstWhere((m) => m.version == version);
    } catch (e) {
      return null;
    }
  }

  /// Execute a single migration with transaction support
  static Future<void> _executeMigration(
    Migration migration,
    int version,
  ) async {
    final logging = LoggingService.instance;
    try {
      logging.debug('Executing migration.up() for version $version');
      await DatabaseService.transaction((txn) async {
        // Execute migration
        await migration.up(txn);

        // Update version
        await txn.execute('PRAGMA user_version = $version');
      });

      // Set version in database service
      await DatabaseService.setVersion(version);

      // Verify migration
      logging.debug('Verifying migration');
      await _verifyMigration(migration);
      logging.debug('Migration verified successfully');
    } catch (e, stackTrace) {
      logging.error('Migration failed', e, stackTrace);
      throw TWMTDatabaseException(
        'Migration to version $version failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Verify that migration was successful
  static Future<void> _verifyMigration(Migration migration) async {
    try {
      await migration.verify(DatabaseService.database);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Migration verification failed for version ${migration.version}',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Check if database needs migration
  static Future<bool> needsMigration() async {
    if (!DatabaseService.isInitialized) {
      return true;
    }

    final currentVersion = await DatabaseService.getVersion();
    final targetVersion = DatabaseConfig.databaseVersion;

    return currentVersion < targetVersion;
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
  /// Only use for development or testing.
  static Future<void> reset() async {
    await DatabaseService.deleteDatabase();
    await DatabaseService.initialize();
    await runMigrations();
  }
}

/// Base class for database migrations
abstract class Migration {
  /// Migration version number
  int get version;

  /// Migration description
  String get description;

  /// Execute the migration (upgrade)
  Future<void> up(Transaction txn);

  /// Rollback the migration (downgrade)
  ///
  /// Optional: Not all migrations need to support rollback
  Future<void> down(Transaction txn) async {
    throw UnimplementedError('Rollback not implemented for migration $version');
  }

  /// Verify that migration was successful
  ///
  /// This method should check that tables, indexes, triggers, and seed data
  /// exist as expected after migration.
  Future<void> verify(Database db) async {
    // Default implementation does nothing
    // Subclasses should override to add verification
  }

  /// Execute a SQL script file
  ///
  /// Splits the script by semicolons and executes each statement.
  /// Handles multi-line statements and comments.
  Future<void> executeSqlScript(Transaction txn, String script) async {
    // Split script into individual statements
    final statements = _splitSqlScript(script);

    // Execute each statement
    for (final statement in statements) {
      if (statement.trim().isNotEmpty) {
        await txn.execute(statement);
      }
    }
  }

  /// Split SQL script into individual statements
  ///
  /// Handles:
  /// - Multi-line statements
  /// - Single-line comments (-- and //)
  /// - Multi-line comments (/* */)
  /// - BEGIN...END blocks (for triggers, procedures)
  /// - String literals with semicolons
  List<String> _splitSqlScript(String script) {
    final statements = <String>[];
    final buffer = StringBuffer();
    bool inString = false;
    bool inComment = false;
    bool inMultiLineComment = false;
    int beginEndDepth = 0; // Track BEGIN...END block depth

    for (int i = 0; i < script.length; i++) {
      final char = script[i];
      final nextChar = i + 1 < script.length ? script[i + 1] : '';

      // Handle multi-line comments
      if (!inString && char == '/' && nextChar == '*') {
        inMultiLineComment = true;
        i++; // Skip next character
        continue;
      }

      if (inMultiLineComment && char == '*' && nextChar == '/') {
        inMultiLineComment = false;
        i++; // Skip next character
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

      // Track BEGIN...END blocks (only when not in string or comment)
      if (!inString && !inComment && !inMultiLineComment) {
        // Check for BEGIN keyword
        if (_isKeywordAt(script, i, 'BEGIN')) {
          beginEndDepth++;
        }
        // Check for END keyword
        else if (_isKeywordAt(script, i, 'END')) {
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
  /// (case-insensitive, must be a whole word)
  bool _isKeywordAt(String script, int position, String keyword) {
    final endPos = position + keyword.length;

    // Check if keyword would exceed script length
    if (endPos > script.length) return false;

    // Check if characters before position form a word boundary
    if (position > 0) {
      final prevChar = script[position - 1];
      if (RegExp(r'[a-zA-Z0-9_]').hasMatch(prevChar)) {
        return false; // Not a word boundary
      }
    }

    // Check if the keyword matches (case-insensitive)
    final word = script.substring(position, endPos);
    if (word.toUpperCase() != keyword.toUpperCase()) {
      return false;
    }

    // Check if characters after keyword form a word boundary
    if (endPos < script.length) {
      final nextChar = script[endPos];
      if (RegExp(r'[a-zA-Z0-9_]').hasMatch(nextChar)) {
        return false; // Not a word boundary
      }
    }

    return true;
  }
}

/// Migration result status
enum MigrationStatus {
  success,
  failed,
  pending,
}

/// Migration result information
class MigrationResult {
  final int version;
  final String description;
  final MigrationStatus status;
  final String? error;
  final DateTime executedAt;

  MigrationResult({
    required this.version,
    required this.description,
    required this.status,
    this.error,
    required this.executedAt,
  });

  bool get isSuccess => status == MigrationStatus.success;
  bool get isFailed => status == MigrationStatus.failed;
  bool get isPending => status == MigrationStatus.pending;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('Migration v$version: $description');
    buffer.write(' - ${status.name}');
    if (error != null) {
      buffer.write(' (Error: $error)');
    }
    return buffer.toString();
  }
}
