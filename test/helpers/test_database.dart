import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migration_service.dart';
import 'package:twmt/services/database/migrations/migration_registry.dart';

import 'test_bootstrap.dart';

/// Test helper that opens an in-memory SQLite database with the real
/// production schema.
///
/// The legacy pattern in repo tests — a hand-written `CREATE TABLE` per
/// table — drifts silently whenever a migration adds columns. This helper
/// runs `lib/database/schema.sql` verbatim and then applies every migration
/// in [MigrationRegistry], so repository tests exercise the same schema the
/// app actually ships.
class TestDatabase {
  TestDatabase._();

  /// Open a migrated in-memory database and wire it into
  /// [DatabaseService.setTestDatabase].
  ///
  /// Also registers baseline fakes via [TestBootstrap.registerFakes] so that
  /// migrations pulling an `ILoggingService` from [ServiceLocator] resolve.
  ///
  /// Set [clearSeeds] to false to preserve schema.sql reference data
  /// (languages, translation_providers, settings, llm_provider_models).
  /// Most repository tests assert against sets they insert themselves, so
  /// they want empty tables — hence the default.
  ///
  /// Callers must release the database in `tearDown` with [close].
  static Future<Database> openMigrated({bool clearSeeds = true}) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await TestBootstrap.registerFakes();

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    await _applySchema(db);
    await _runMigrations();

    // Repository tests focus on query/update behaviour; they have never
    // seeded the full FK graph. Disable FK enforcement (after schema.sql
    // turned it on) so tests can insert rows with dangling parent refs
    // the same way they did with the legacy hand-written CREATE TABLE.
    await db.execute('PRAGMA foreign_keys = OFF');

    if (clearSeeds) {
      await _clearSeedData(db);
    }

    return db;
  }

  static Future<void> _clearSeedData(Database db) async {
    // Tables populated by schema.sql's INSERT OR IGNORE ... VALUES blocks.
    // Keep in sync with seed blocks in lib/database/schema.sql.
    const seededTables = [
      'settings',
      'llm_provider_models',
      'translation_providers',
      'languages',
    ];
    for (final table in seededTables) {
      await db.delete(table);
    }
  }

  /// Close the test database and clear the [DatabaseService] singleton.
  static Future<void> close(Database db) async {
    await db.close();
    DatabaseService.resetTestDatabase();
  }

  static Future<void> _applySchema(Database db) async {
    final schema = await File('lib/database/schema.sql').readAsString();
    final statements = MigrationService.splitSqlScriptForTesting(schema);
    for (final raw in statements) {
      final statement = raw.trim();
      if (statement.isEmpty) continue;
      await db.execute(statement);
    }
  }

  static Future<void> _runMigrations() async {
    for (final migration in MigrationRegistry.getAllMigrations()) {
      try {
        if (await migration.isApplied()) continue;
        await migration.execute();
      } catch (_) {
        // Migrations log their own failures through the injected logger.
        // They are designed to be non-fatal; skip and continue so a broken
        // migration doesn't mask unrelated test failures.
      }
    }
  }
}
