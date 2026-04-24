import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/data_migrations/validation_issues_json_data_migration.dart';
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
    // Minimal table — the service uses only these columns.
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        translated_text TEXT,
        validation_issues TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ValidationIssuesJsonDataMigration.isApplied', () {
    test('returns true on empty DB (nothing to migrate, marker written)',
        () async {
      final migration = ValidationIssuesJsonDataMigration();
      expect(await migration.isApplied(), isTrue);
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });

    test('returns true if marker is already present', () async {
      await db.execute('''
        CREATE TABLE _migration_markers (
          id TEXT PRIMARY KEY,
          applied_at INTEGER NOT NULL
        )
      ''');
      await db.insert('_migration_markers',
          {'id': 'validation_issues_json', 'applied_at': 1});
      expect(await ValidationIssuesJsonDataMigration().isApplied(), isTrue);
    });

    test('returns false when a legacy-shaped row exists', () async {
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy message]',
        'updated_at': 0,
      });
      expect(await ValidationIssuesJsonDataMigration().isApplied(), isFalse);
    });

    test('returns true (and writes marker) when all rows are already JSON',
        () async {
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '["msg1"]',
        'updated_at': 0,
      });
      final migration = ValidationIssuesJsonDataMigration();
      expect(await migration.isApplied(), isTrue);
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });
  });
}
