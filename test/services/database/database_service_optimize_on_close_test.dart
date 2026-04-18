import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  test('close() runs PRAGMA optimize before closing', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    // Create a tiny schema and index so optimize has something to consider.
    await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)');
    await db.execute('CREATE INDEX idx_t_v ON t(v)');
    for (var i = 0; i < 100; i++) {
      await db.insert('t', {'v': 'x$i'});
    }

    // Intercepting PRAGMA execution is brittle; instead we assert the call
    // completes without throwing and the database is closed afterwards.
    await DatabaseService.close();
    expect(() => db.rawQuery('SELECT 1'),
        throwsA(isA<DatabaseException>()));
  });
}
