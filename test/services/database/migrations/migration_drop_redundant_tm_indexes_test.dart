import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_drop_redundant_tm_indexes.dart';
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

    // Minimal table + legacy indexes that mimic an upgraded database.
    await db.execute('''
      CREATE TABLE translation_memory (
        id TEXT PRIMARY KEY,
        source_hash TEXT NOT NULL,
        source_language_id TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        UNIQUE(source_hash, target_language_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_tm_hash_lang ON translation_memory(source_hash, target_language_id)',
    );
    await db.execute(
      'CREATE INDEX idx_tm_source_hash ON translation_memory(source_hash)',
    );
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('DropRedundantTmIndexesMigration', () {
    test('execute drops both redundant indexes', () async {
      final applied =
          await DropRedundantTmIndexesMigration().execute();
      expect(applied, isTrue);

      final remaining = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='translation_memory'",
      ))
          .map((r) => r['name'] as String)
          .toList();
      expect(remaining, isNot(contains('idx_tm_hash_lang')));
      expect(remaining, isNot(contains('idx_tm_source_hash')));
    });

    test('execute is idempotent (safe when indexes are already gone)',
        () async {
      expect(await DropRedundantTmIndexesMigration().execute(), isTrue);
      expect(await DropRedundantTmIndexesMigration().execute(), isTrue);
    });

    test('UNIQUE auto-index still covers source_hash lookups', () async {
      await DropRedundantTmIndexesMigration().execute();
      final plan = await db.rawQuery(
        "EXPLAIN QUERY PLAN SELECT id FROM translation_memory WHERE source_hash = ?",
        ['abc'],
      );
      final detail = plan.map((r) => r['detail']).join(' ');
      expect(detail.toLowerCase(), contains('using'));
      expect(detail.toLowerCase(), isNot(contains('scan translation_memory')));
    });
  });
}
