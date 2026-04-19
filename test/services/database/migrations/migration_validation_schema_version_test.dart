import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_validation_schema_version.dart';
import '../../../helpers/test_bootstrap.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    // Minimal table mimicking an existing installation without the new column.
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        validation_issues TEXT
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ValidationSchemaVersionMigration', () {
    test('adds validation_schema_version column with default 0', () async {
      final migration = ValidationSchemaVersionMigration();

      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);
      expect(await migration.isApplied(), isTrue);

      final cols = await db.rawQuery(
          'PRAGMA table_info(translation_versions)');
      final col = cols.firstWhere(
        (c) => c['name'] == 'validation_schema_version',
        orElse: () => <String, Object?>{},
      );
      expect(col['name'], 'validation_schema_version');
      expect(col['dflt_value'], '0');
    });

    test('is idempotent — second execute is a no-op', () async {
      await ValidationSchemaVersionMigration().execute();
      final second = await ValidationSchemaVersionMigration().execute();
      // Returns false when already applied; no exception.
      expect(second, isFalse);
    });

    test('existing rows inherit default 0', () async {
      await db.insert(
        'translation_versions',
        {'id': 'v1', 'validation_issues': null},
      );
      await ValidationSchemaVersionMigration().execute();
      final rows = await db.rawQuery(
        'SELECT validation_schema_version FROM translation_versions WHERE id = ?',
        ['v1'],
      );
      expect(rows.single['validation_schema_version'], 0);
    });
  });
}
