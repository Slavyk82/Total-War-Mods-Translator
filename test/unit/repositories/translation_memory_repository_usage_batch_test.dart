import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/database/database_service.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    await db.execute('''
      CREATE TABLE translation_memory (
        id TEXT PRIMARY KEY,
        source_hash TEXT NOT NULL,
        source_language_id TEXT NOT NULL,
        target_language_id TEXT NOT NULL,
        source_text TEXT NOT NULL DEFAULT '',
        translated_text TEXT NOT NULL DEFAULT '',
        usage_count INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        UNIQUE(source_hash, target_language_id)
      )
    ''');
    for (var i = 0; i < 5; i++) {
      await db.insert('translation_memory', {
        'id': 'tm$i',
        'source_hash': 'h$i',
        'source_language_id': 'en',
        'target_language_id': 'fr',
        'usage_count': 0,
      });
    }
    repo = TranslationMemoryRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  test('increments usage_count per entry and groups by delta', () async {
    final result = await repo.incrementUsageCountBatch({
      'tm0': 1,
      'tm1': 1,
      'tm2': 1,
      'tm3': 2,
      'tm4': 2,
    });
    expect(result.isOk, isTrue);
    expect(result.unwrap(), 5);

    final rows = await db.query('translation_memory', orderBy: 'id');
    expect(rows.map((r) => r['usage_count']).toList(),
        [1, 1, 1, 2, 2]);
  });

  test('returns Ok(0) for empty input', () async {
    final result = await repo.incrementUsageCountBatch({});
    expect(result.isOk, isTrue);
    expect(result.unwrap(), 0);
  });
}
