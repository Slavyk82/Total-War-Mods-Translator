import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_export_history_languages.dart';
import '../../../helpers/test_bootstrap.dart';

/// Legacy `export_history` schema as it exists on databases created before the
/// "unified structure" refactor: one row per language with a NOT NULL
/// `language_code` column and no `languages` column.
const _legacySchema = '''
  CREATE TABLE export_history (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    format TEXT NOT NULL,
    validated_only INTEGER NOT NULL DEFAULT 0,
    output_path TEXT NOT NULL,
    file_size INTEGER,
    entry_count INTEGER NOT NULL,
    exported_at INTEGER NOT NULL
  )
''';

/// Current/canonical schema (fresh installs already have `languages`).
const _currentSchema = '''
  CREATE TABLE export_history (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    languages TEXT NOT NULL,
    format TEXT NOT NULL,
    validated_only INTEGER NOT NULL DEFAULT 0,
    output_path TEXT NOT NULL,
    file_size INTEGER,
    entry_count INTEGER NOT NULL,
    exported_at INTEGER NOT NULL
  )
''';

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
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  Future<Set<String>> columns() async {
    final rows = await db.rawQuery('PRAGMA table_info(export_history)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  group('ExportHistoryLanguagesMigration on a legacy database', () {
    setUp(() async {
      await db.execute(_legacySchema);
      // Legacy index that references language_code — present on real upgraded
      // databases. SQLite blocks DROP COLUMN while this index exists, so the
      // migration must remove it first.
      await db.execute(
        'CREATE INDEX idx_export_project_lang '
        'ON export_history(project_id, language_code, exported_at DESC)',
      );
      await db.insert('export_history', {
        'id': 'e1',
        'project_id': 'p1',
        'language_code': 'fr',
        'format': 'pack',
        'validated_only': 0,
        'output_path': 'C:/out/a.pack',
        'file_size': 123,
        'entry_count': 10,
        'exported_at': 1000,
      });
      await db.insert('export_history', {
        'id': 'e2',
        'project_id': 'p1',
        'language_code': 'pt-BR',
        'format': 'pack',
        'validated_only': 1,
        'output_path': 'C:/out/b.pack',
        'file_size': null,
        'entry_count': 5,
        'exported_at': 2000,
      });
    });

    test('legacy schema is the broken precondition', () async {
      final cols = await columns();
      expect(cols, contains('language_code'));
      expect(cols, isNot(contains('languages')));
    });

    test('execute adds languages, backfills it, and drops language_code',
        () async {
      expect(await ExportHistoryLanguagesMigration().execute(), isTrue);

      final cols = await columns();
      expect(cols, contains('languages'));
      expect(cols, isNot(contains('language_code')));

      // The legacy index that referenced language_code must be gone.
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type='index' AND tbl_name='export_history'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, isNot(contains('idx_export_project_lang')));

      final rows = await db.query('export_history', orderBy: 'exported_at');
      expect(rows[0]['languages'], '["fr"]');
      expect(rows[1]['languages'], '["pt-BR"]');
    });

    test('migrated rows deserialize via ExportHistory.fromJson', () async {
      await ExportHistoryLanguagesMigration().execute();

      final rows = await db.query('export_history',
          where: 'id = ?', whereArgs: ['e1']);
      // Previously this threw "type 'Null' is not a subtype of type 'String'".
      final entry = ExportHistory.fromJson(rows.first);
      expect(entry.languages, '["fr"]');
      expect(entry.languagesList, ['fr']);
    });

    test('inserts that omit language_code succeed after migration', () async {
      await ExportHistoryLanguagesMigration().execute();

      // Mirrors the model's toJson(): no language_code key. Under the legacy
      // schema this would fail the language_code NOT NULL constraint.
      await db.insert('export_history', {
        'id': 'e3',
        'project_id': 'p1',
        'languages': '["de"]',
        'format': 'pack',
        'validated_only': 0,
        'output_path': 'C:/out/c.pack',
        'entry_count': 3,
        'exported_at': 3000,
      });

      final count = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM export_history',
      ))
          .first['c'];
      expect(count, 3);
    });

    test('is idempotent and reports applied after the first run', () async {
      expect(await ExportHistoryLanguagesMigration().isApplied(), isFalse);
      expect(await ExportHistoryLanguagesMigration().execute(), isTrue);
      expect(await ExportHistoryLanguagesMigration().isApplied(), isTrue);
      // A second execute is a safe no-op (isApplied gates it in the runner).
      expect(await ExportHistoryLanguagesMigration().execute(), isFalse);
    });
  });

  group('ExportHistoryLanguagesMigration on a fresh database', () {
    setUp(() async {
      await db.execute(_currentSchema);
    });

    test('is already applied and execute is a no-op', () async {
      expect(await ExportHistoryLanguagesMigration().isApplied(), isTrue);
      expect(await ExportHistoryLanguagesMigration().execute(), isFalse);
      final cols = await columns();
      expect(cols, contains('languages'));
      expect(cols, isNot(contains('language_code')));
    });
  });

  group('ExportHistoryLanguagesMigration with no export_history table', () {
    test('is a no-op (nothing to migrate)', () async {
      expect(await ExportHistoryLanguagesMigration().isApplied(), isTrue);
      expect(await ExportHistoryLanguagesMigration().execute(), isFalse);
    });
  });
}
