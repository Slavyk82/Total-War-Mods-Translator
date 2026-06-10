// SQL-level coverage for the minUsageCount filter added to
// TranslationMemoryRepository.getPage / countWithFilters (2026-06-10 review,
// LOW / L14: the TMX export dialog's "Frequently used only (>5 times)" scope
// is implemented as usage_count >= 6 pushed down to these queries).
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
    // usage_count 0..5 for lang_fr, plus one frequently-used lang_de row.
    for (var i = 0; i < 6; i++) {
      await db.insert('translation_memory', {
        'id': 'tm$i',
        'source_hash': 'h$i',
        'source_language_id': 'lang_en',
        'target_language_id': 'lang_fr',
        'source_text': 'src$i',
        'translated_text': 'tgt$i',
        'usage_count': i,
        'created_at': now,
        'last_used_at': now,
        'updated_at': now,
      });
    }
    await db.insert('translation_memory', {
      'id': 'tm_de',
      'source_hash': 'h_de',
      'source_language_id': 'lang_en',
      'target_language_id': 'lang_de',
      'source_text': 'src_de',
      'translated_text': 'tgt_de',
      'usage_count': 9,
      'created_at': now,
      'last_used_at': now,
      'updated_at': now,
    });
    repo = TranslationMemoryRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  test('getPage applies minUsageCount together with the language filter',
      () async {
    final result = await repo.getPage(
      offset: 0,
      pageSize: 100,
      targetLanguageId: 'lang_fr',
      minUsageCount: 4,
    );
    expect(result.isOk, isTrue);
    expect(
      result.unwrap().map((e) => e.id).toList(),
      ['tm4', 'tm5'],
      reason: 'only lang_fr rows with usage_count >= 4, ordered by id',
    );
  });

  test('getPage without minUsageCount keeps legacy behavior', () async {
    final result = await repo.getPage(
      offset: 0,
      pageSize: 100,
      targetLanguageId: 'lang_fr',
    );
    expect(result.isOk, isTrue);
    expect(result.unwrap().length, 6);
  });

  test('getPage paging offsets stay consistent with the filter', () async {
    final firstPage = await repo.getPage(
      offset: 0,
      pageSize: 2,
      minUsageCount: 3,
    );
    final secondPage = await repo.getPage(
      offset: 2,
      pageSize: 2,
      minUsageCount: 3,
    );
    expect(firstPage.unwrap().map((e) => e.id).toList(), ['tm3', 'tm4']);
    expect(secondPage.unwrap().map((e) => e.id).toList(), ['tm5', 'tm_de']);
  });

  test('countWithFilters matches getPage filtering', () async {
    final all = await repo.countWithFilters();
    expect(all.unwrap(), 7);

    final frequent = await repo.countWithFilters(minUsageCount: 4);
    expect(frequent.unwrap(), 3, reason: 'tm4, tm5 and tm_de');

    final frequentFr = await repo.countWithFilters(
      targetLanguageId: 'lang_fr',
      minUsageCount: 4,
    );
    expect(frequentFr.unwrap(), 2);
  });
}
