import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_fix_cache_triggers.dart';
import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Full production schema + migrations. The registry runs this migration
    // during setup, which writes the settings marker — clear it so we can
    // exercise a clean first-run below.
    db = await TestDatabase.openMigrated();
    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: ['migration_fix_cache_triggers_applied'],
    );
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('FixCacheTriggersMigration', () {
    test('isApplied() is true after first execute (skipped next startup)',
        () async {
      final migration = FixCacheTriggersMigration();

      // Marker absent → migration must run.
      expect(await migration.isApplied(), isFalse);

      // First run records the marker.
      expect(await migration.execute(), isTrue);

      // Marker present → migration is skipped on the next startup.
      expect(await migration.isApplied(), isTrue);

      final rows = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ?',
        ['migration_fix_cache_triggers_applied'],
      );
      expect(rows, hasLength(1));
    });
  });
}
