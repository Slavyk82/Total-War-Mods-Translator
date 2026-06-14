import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/config/database_config.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migration_service.dart';

import '../../helpers/fakes/fake_logger.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    MigrationService.loggerForTesting = FakeLogger();
  });

  // --------------------------------------------------------------------------
  // Guards: service requires DatabaseService to be initialized first.
  // --------------------------------------------------------------------------
  group('initialization guards', () {
    setUp(() {
      DatabaseService.resetTestDatabase();
    });

    test('runMigrations throws StateError when DB is not initialized',
        () async {
      await expectLater(
        MigrationService.runMigrations(),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'ensurePerformanceIndexes throws StateError when DB is not initialized',
        () async {
      await expectLater(
        MigrationService.ensurePerformanceIndexes(),
        throwsA(isA<StateError>()),
      );
    });

    test('needsMigration returns true when DB is not initialized', () async {
      expect(await MigrationService.needsMigration(), isTrue);
    });

    test('getCurrentVersion returns 0 when DB is not initialized', () async {
      expect(await MigrationService.getCurrentVersion(), 0);
    });

    test('getTargetVersion returns the frozen config version', () {
      expect(
        MigrationService.getTargetVersion(),
        DatabaseConfig.databaseVersion,
      );
    });
  });

  // --------------------------------------------------------------------------
  // Fresh database (version 0) -> full schema initialization.
  // --------------------------------------------------------------------------
  group('runMigrations on a fresh (version 0) database', () {
    late Database db;

    setUp(() async {
      await TestBootstrap.registerFakes();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);
      // A brand-new in-memory DB already reports user_version == 0, but make
      // the precondition explicit for the reader.
      await db.execute('PRAGMA user_version = 0');
    });

    tearDown(() async {
      await db.close();
      DatabaseService.resetTestDatabase();
    });

    test('creates all required core tables, FTS tables and seed data',
        () async {
      expect(await MigrationService.needsMigration(), isTrue);

      await MigrationService.runMigrations();

      // Version was bumped to the target.
      expect(await DatabaseService.getVersion(),
          DatabaseConfig.databaseVersion);
      expect(await MigrationService.needsMigration(), isFalse);

      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%'",
      ))
          .map((r) => r['name'] as String)
          .toSet();

      // Core tables verified by _verifySchema.
      for (final t in const [
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
      ]) {
        expect(tables, contains(t), reason: 'missing core table $t');
      }

      // FTS5 tables verified by _verifySchema.
      for (final fts in const [
        'translation_units_fts',
        'translation_versions_fts',
        'translation_memory_fts',
        'workshop_mods_fts',
      ]) {
        expect(tables, contains(fts), reason: 'missing FTS table $fts');
      }

      // Seed data thresholds enforced by _verifySchema.
      final langCount = (await db.rawQuery(
          'SELECT COUNT(*) AS c FROM languages'))
          .first['c'] as int;
      expect(langCount, greaterThanOrEqualTo(6));

      final providerCount = (await db.rawQuery(
          'SELECT COUNT(*) AS c FROM translation_providers'))
          .first['c'] as int;
      expect(providerCount, greaterThanOrEqualTo(3));
    });

    test('is idempotent: a second run short-circuits (already up to date)',
        () async {
      await MigrationService.runMigrations();
      final versionAfterFirst = await DatabaseService.getVersion();

      // Second call hits the `currentVersion == targetVersion` early return
      // and must not throw or alter the version.
      await MigrationService.runMigrations();
      expect(await DatabaseService.getVersion(), versionAfterFirst);
    });

    test('getCurrentVersion reflects the DB version once initialized',
        () async {
      await MigrationService.runMigrations();
      expect(await MigrationService.getCurrentVersion(),
          DatabaseConfig.databaseVersion);
    });
  });

  // --------------------------------------------------------------------------
  // Version mismatch branches.
  // --------------------------------------------------------------------------
  group('runMigrations version mismatch', () {
    late Database db;

    setUp(() async {
      await TestBootstrap.registerFakes();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);
    });

    tearDown(() async {
      await db.close();
      DatabaseService.resetTestDatabase();
    });

    test('throws when stored version is HIGHER than the app version', () async {
      await db.execute('PRAGMA user_version = 99');

      await expectLater(
        MigrationService.runMigrations(),
        throwsA(
          isA<TWMTDatabaseException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('99'),
              contains('higher than app version'),
            ),
          ),
        ),
      );
    });

    // NOTE: the "migration not supported" dead-end branch (an existing,
    // non-fresh database whose version is below the target) is UNREACHABLE
    // with the production config: DatabaseConfig.databaseVersion is frozen at
    // 1, so the only value that is >0 and <target does not exist. Exercising
    // it would require mutating production code/config, which is out of scope.
  });

  // --------------------------------------------------------------------------
  // Error / rollback branch in _initializeSchema.
  // --------------------------------------------------------------------------
  group('runMigrations schema-init failure', () {
    test(
        'wraps a schema-execution failure in TWMTDatabaseException '
        '("Schema initialization failed")', () async {
      await TestBootstrap.registerFakes();

      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);
      await db.execute('PRAGMA user_version = 0');

      // Pre-create a `languages` table that is MISSING the columns the schema's
      // seed INSERTs expect. schema.sql creates tables with `IF NOT EXISTS`, so
      // this stub survives, and the subsequent
      // `INSERT OR IGNORE INTO languages (code, name, native_name, ...)` fails
      // with "no such column" INSIDE the schema transaction — driving the
      // catch/rethrow path in _initializeSchema.
      await db.execute('CREATE TABLE languages (id TEXT PRIMARY KEY)');

      await expectLater(
        MigrationService.runMigrations(),
        throwsA(
          isA<TWMTDatabaseException>().having(
            (e) => e.message,
            'message',
            contains('Schema initialization failed'),
          ),
        ),
      );

      await db.close();
      DatabaseService.resetTestDatabase();
    });
  });

  // --------------------------------------------------------------------------
  // ensurePerformanceIndexes: real registry against a migrated schema.
  // --------------------------------------------------------------------------
  group('ensurePerformanceIndexes', () {
    late Database db;

    setUp(() async {
      await TestBootstrap.registerFakes();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);
      await db.execute('PRAGMA user_version = 0');
      // Build the real schema so the registered migrations have tables to
      // operate on.
      await MigrationService.runMigrations();
    });

    tearDown(() async {
      await db.close();
      DatabaseService.resetTestDatabase();
    });

    test('runs all registered migrations and returns a result per migration',
        () async {
      final results = await MigrationService.ensurePerformanceIndexes();

      expect(results, isNotEmpty);
      // Each result corresponds to a registered migration id.
      expect(
        results.map((r) => r.migrationId).toSet().length,
        results.length,
        reason: 'migration ids should be unique',
      );
    });

    test('a second pass reports migrations as skipped (idempotent)', () async {
      await MigrationService.ensurePerformanceIndexes();
      final second = await MigrationService.ensurePerformanceIndexes();

      // After the first pass every migration is applied, so the second pass
      // should mark at least some as skipped and none should hard-fail.
      expect(second.any((r) => r.skipped), isTrue);
    });
  });

  group('ensurePerformanceIndexes failure handling', () {
    test(
        'captures a throwing migration as an error result and keeps going',
        () async {
      await TestBootstrap.registerFakes();
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);

      // Deliberately do NOT build the schema. Migrations that ALTER/UPDATE
      // real tables will throw "no such table" inside execute(); the service
      // must catch each failure (per-migration try/catch), record a
      // MigrationResult.error and continue with the remaining migrations
      // rather than aborting.
      final results = await MigrationService.ensurePerformanceIndexes();

      expect(results, isNotEmpty);
      expect(
        results.any((r) => !r.success && r.errorMessage != null),
        isTrue,
        reason: 'at least one migration should fail against an empty database',
      );

      await db.close();
      DatabaseService.resetTestDatabase();
    });
  });

  // --------------------------------------------------------------------------
  // splitSqlScriptForTesting passthrough (used to install schema in tests).
  // --------------------------------------------------------------------------
  group('splitSqlScriptForTesting', () {
    test('splits on top-level semicolons and keeps trigger bodies intact', () {
      const script = '''
CREATE TABLE a (id TEXT);
CREATE TRIGGER trg AFTER INSERT ON a BEGIN
  UPDATE a SET id = id;
END;
''';
      final statements = MigrationService.splitSqlScriptForTesting(script)
          .where((s) => s.trim().isNotEmpty)
          .toList();

      expect(statements, hasLength(2));
      expect(statements[0], startsWith('CREATE TABLE a'));
      expect(statements[1], startsWith('CREATE TRIGGER trg'));
      expect(statements[1], endsWith('END'));
    });
  });

  // NOTE: MigrationService.reset() is intentionally NOT exercised here. It
  // resolves a real on-disk database path via DatabaseConfig, and under
  // `flutter test` kDebugMode is true, so DatabaseConfig._getAppDataDirectory
  // returns the user's real installed-app directory (from %APPDATA%) rather
  // than any path-provider override. Running reset() would delete and recreate
  // the developer's actual production database, so it is left uncovered.
}
