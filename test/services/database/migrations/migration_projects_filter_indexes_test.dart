import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_projects_filter_indexes.dart';
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

    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        game_installation_id TEXT NOT NULL,
        project_type TEXT NOT NULL DEFAULT 'mod',
        has_mod_update_impact INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ProjectsFilterIndexesMigration', () {
    test('execute creates the three filter indexes', () async {
      final applied = await ProjectsFilterIndexesMigration().execute();
      expect(applied, isTrue);

      final names = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='projects'",
      ))
          .map((r) => r['name'] as String)
          .toSet();
      expect(names, containsAll(<String>[
        'idx_projects_type',
        'idx_projects_game_type',
        'idx_projects_impact',
      ]));
    });

    test('execute is idempotent', () async {
      expect(await ProjectsFilterIndexesMigration().execute(), isTrue);
      expect(await ProjectsFilterIndexesMigration().execute(), isTrue);
    });

    test('idx_projects_impact is a partial index on has_mod_update_impact = 1',
        () async {
      await ProjectsFilterIndexesMigration().execute();
      final row = (await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name='idx_projects_impact'",
      )).first;
      expect((row['sql'] as String).toLowerCase(),
          contains('where has_mod_update_impact = 1'));
    });
  });
}
