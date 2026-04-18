import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  setUp(() async {
    db = await TestDatabase.openMigrated();

    const now = 0;
    for (var i = 0; i < 5; i++) {
      await db.insert('translation_memory', {
        'id': 'tm$i',
        'source_hash': 'h$i',
        'source_language_id': 'lang_en',
        'target_language_id': 'lang_fr',
        'source_text': 'src$i',
        'translated_text': 'tgt$i',
        'usage_count': 0,
        'created_at': now,
        'last_used_at': now,
        'updated_at': now,
      });
    }
    repo = TranslationMemoryRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
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
