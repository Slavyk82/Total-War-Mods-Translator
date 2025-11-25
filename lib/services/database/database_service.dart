import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../config/database_config.dart';
import '../../models/common/service_exception.dart';
import '../shared/logging_service.dart';

/// Database service for TWMT application.
///
/// Provides SQLite database initialization, connection management, and
/// transaction support using sqflite_common_ffi for Windows desktop.
///
/// This service follows the singleton pattern to ensure a single database
/// connection throughout the application lifecycle.
class DatabaseService {
  DatabaseService._();

  static final DatabaseService _instance = DatabaseService._();
  static Database? _database;
  static bool _initialized = false;

  /// Get the singleton instance
  static DatabaseService get instance => _instance;

  /// Get the database instance.
  ///
  /// Throws [StateError] if database is not initialized.
  /// Call [initialize] first before accessing the database.
  static Database get database {
    if (_database == null) {
      throw StateError(
        'Database not initialized. Call DatabaseService.initialize() first.',
      );
    }
    return _database!;
  }

  /// Check if database is initialized
  static bool get isInitialized => _initialized && _database != null;

  /// Initialize the database service.
  ///
  /// This method must be called before any database operations.
  /// It performs the following:
  /// - Initializes SQLite FFI for Windows
  /// - Creates application directories if needed
  /// - Opens the database connection
  /// - Enables WAL mode and foreign keys
  /// - Runs migrations if needed
  ///
  /// Throws [TWMTDatabaseException] if initialization fails.
  static Future<void> initialize() async {
    final logging = LoggingService.instance;
    if (_initialized && _database != null) {
      logging.debug('Database already initialized, skipping');
      return; // Already initialized
    }

    try {
      logging.debug('Starting database initialization');

      // Initialize SQLite FFI for Windows
      if (Platform.isWindows) {
        logging.debug('Initializing SQLite FFI for Windows');
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // Ensure application directories exist
      await DatabaseConfig.ensureDirectoriesExist();

      // Get database path
      final dbPath = await DatabaseConfig.getDatabasePath();
      logging.debug('Database path', {'path': dbPath});

      // Check if database file exists
      final dbFile = File(dbPath);
      final dbExists = await dbFile.exists();
      logging.debug('Database file exists', {'exists': dbExists});

      // Open database with target version
      // onCreate and onUpgrade will ensure version starts at 0 for MigrationService
      logging.debug('Opening database');
      // Open database without specifying onCreate/onUpgrade
      // We'll handle versioning manually via MigrationService
      _database = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          onConfigure: _onConfigure,
          onOpen: _onOpen,
        ),
      );

      logging.info('Database opened successfully');
      final currentVersion = await _database!.getVersion();
      logging.debug('Current database version', {'version': currentVersion});

      _initialized = true;
    } catch (e, stackTrace) {
      _initialized = false;
      _database = null;
      throw TWMTDatabaseException(
        'Failed to initialize database: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Configure database before opening
  static Future<void> _onConfigure(Database db) async {
    // Enable foreign key constraints
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Called after database is opened
  static Future<void> _onOpen(Database db) async {
    // Apply PRAGMA settings
    final pragmas = DatabaseConfig.getPragmaStatements();
    for (final pragma in pragmas) {
      await db.execute(pragma);
    }
  }

  /// Execute a raw SQL query
  ///
  /// Use parameterized queries to prevent SQL injection:
  /// ```dart
  /// await DatabaseService.rawQuery(
  ///   'SELECT * FROM projects WHERE id = ?',
  ///   ['project_id_123'],
  /// );
  /// ```
  static Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      return await database.rawQuery(sql, arguments);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Query failed: $sql',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute a raw SQL insert
  ///
  /// Returns the row ID of the inserted row.
  static Future<int> rawInsert(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      return await database.rawInsert(sql, arguments);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Insert failed: $sql',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute a raw SQL update
  ///
  /// Returns the number of rows affected.
  static Future<int> rawUpdate(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      return await database.rawUpdate(sql, arguments);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Update failed: $sql',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute a raw SQL delete
  ///
  /// Returns the number of rows deleted.
  static Future<int> rawDelete(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      return await database.rawDelete(sql, arguments);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Delete failed: $sql',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute a raw SQL statement (for CREATE, DROP, etc.)
  static Future<void> execute(String sql) async {
    try {
      await database.execute(sql);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Execute failed: $sql',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Execute a batch of SQL statements
  static Future<void> executeBatch(List<String> statements) async {
    try {
      final batch = database.batch();
      for (final statement in statements) {
        batch.execute(statement);
      }
      await batch.commit(noResult: true);
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Batch execution failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Checkpoint the WAL file to merge changes back to main database
  ///
  /// This should be called periodically to prevent WAL file from growing too large.
  /// Returns true if checkpoint was successful.
  static Future<bool> checkpointWal() async {
    try {
      final result = await database.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');
      final busy = result.first['busy'] as int;
      final checkpointed = result.first['checkpointed'] as int;
      
      LoggingService.instance.debug('WAL checkpoint completed', {
        'busy': busy,
        'checkpointed': checkpointed,
      });
      
      return busy == 0;
    } catch (e, stackTrace) {
      LoggingService.instance.error('WAL checkpoint failed', e, stackTrace);
      return false;
    }
  }

  /// Get WAL file statistics
  static Future<Map<String, dynamic>> getWalStats() async {
    try {
      final dbPath = await DatabaseConfig.getDatabasePath();
      final walPath = '$dbPath-wal';
      final walFile = File(walPath);
      
      if (!await walFile.exists()) {
        return {'exists': false};
      }
      
      final stat = await walFile.stat();
      return {
        'exists': true,
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Check WAL file size and checkpoint if necessary
  ///
  /// Checkpoints the WAL file if it's larger than threshold (default 1MB).
  /// This prevents the WAL file from growing too large and causing lock issues.
  static Future<void> checkpointIfNeeded({int thresholdBytes = 1048576}) async {
    try {
      final stats = await getWalStats();
      if (stats['exists'] == true && stats['size'] != null) {
        final size = stats['size'] as int;
        if (size > thresholdBytes) {
          LoggingService.instance.debug('WAL file exceeds threshold', {
            'size': size,
            'threshold': thresholdBytes,
          });
          await checkpointWal();
        }
      }
    } catch (e, stackTrace) {
      LoggingService.instance.error(
        'Failed to check WAL size',
        e,
        stackTrace,
      );
    }
  }

  /// Execute operations in a transaction
  ///
  /// All operations in the callback will be executed atomically.
  /// If any operation fails, the entire transaction will be rolled back.
  ///
  /// Example:
  /// ```dart
  /// await DatabaseService.transaction((txn) async {
  ///   await txn.insert('projects', projectData);
  ///   await txn.insert('project_languages', languageData);
  /// });
  /// ```
  static Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    Duration? timeout,
  }) async {
    // Default transaction timeout: 30 seconds
    const defaultTimeout = Duration(seconds: 30);
    final effectiveTimeout = timeout ?? defaultTimeout;

    try {
      return await database.transaction(action).timeout(
        effectiveTimeout,
        onTimeout: () {
          throw TWMTDatabaseException(
            'Transaction timeout after ${effectiveTimeout.inSeconds} seconds. '
            'Consider breaking into smaller transactions or increasing timeout.',
          );
        },
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Transaction failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Insert a record into a table
  ///
  /// Returns the row ID of the inserted record.
  ///
  /// Example:
  /// ```dart
  /// final id = await DatabaseService.insert('projects', {
  ///   'id': 'project_uuid',
  ///   'name': 'My Project',
  ///   'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  /// });
  /// ```
  static Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    try {
      return await database.insert(
        table,
        values,
        conflictAlgorithm: conflictAlgorithm,
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Insert failed for table: $table',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Update records in a table
  ///
  /// Returns the number of rows affected.
  static Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    try {
      return await database.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Update failed for table: $table',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Delete records from a table
  ///
  /// Returns the number of rows deleted.
  static Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    try {
      return await database.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Delete failed for table: $table',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Query records from a table
  ///
  /// Returns a list of records as maps.
  static Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    try {
      return await database.query(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    } catch (e, stackTrace) {
      throw TWMTDatabaseException(
        'Query failed for table: $table',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Close the database connection
  ///
  /// This should be called when the application is shutting down.
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _initialized = false;
    }
  }

  /// Delete the database file
  ///
  /// WARNING: This will permanently delete all data.
  /// Only use for testing or reset functionality.
  static Future<void> deleteDatabase() async {
    await close();
    final dbPath = await DatabaseConfig.getDatabasePath();
    await databaseFactory.deleteDatabase(dbPath);
  }

  /// Get database file path
  static Future<String> getDatabasePath() async {
    return await DatabaseConfig.getDatabasePath();
  }

  /// Get current database version
  static Future<int> getVersion() async {
    return await database.getVersion();
  }

  /// Set database version
  static Future<void> setVersion(int version) async {
    await database.setVersion(version);
  }

  /// Set the database instance (for testing only)
  ///
  /// WARNING: This should only be used in tests to inject a mock database.
  static void setDatabase(Database db) {
    _database = db;
    _initialized = true;
  }
}
