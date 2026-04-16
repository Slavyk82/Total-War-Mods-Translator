import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_activity_events.dart';
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
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ActivityEventsMigration', () {
    test('execute creates activity_events table and indexes', () async {
      final migration = ActivityEventsMigration();
      final applied = await migration.execute();
      expect(applied, isTrue);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='activity_events'",
      );
      expect(tables, hasLength(1));

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='activity_events'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_activity_events_ts'));
      expect(indexNames, contains('idx_activity_events_game'));
    });

    test('execute is idempotent', () async {
      final migration = ActivityEventsMigration();
      expect(await migration.execute(), isTrue);
      expect(await migration.execute(), isTrue);
    });

    test('id/type/timestamp/payload are NOT NULL; project_id/game_code nullable', () async {
      await ActivityEventsMigration().execute();
      final cols = await db.rawQuery("PRAGMA table_info(activity_events)");
      final byName = {
        for (final c in cols) (c['name'] as String): c,
      };
      // Note: PRAGMA table_info reports notnull=0 for INTEGER PRIMARY KEY
      // AUTOINCREMENT columns because they are aliases for rowid, which
      // SQLite treats as implicitly non-null without setting the NOT NULL
      // flag. The value is still never null in practice.
      expect(byName['id']!['notnull'], 0);
      expect(byName['type']!['notnull'], 1);
      expect(byName['timestamp']!['notnull'], 1);
      expect(byName['payload']!['notnull'], 1);
      expect(byName['project_id']!['notnull'], 0);
      expect(byName['game_code']!['notnull'], 0);
      // project_id is TEXT (UUID), not INTEGER
      expect((byName['project_id']!['type'] as String).toUpperCase(), 'TEXT');
    });
  });
}
