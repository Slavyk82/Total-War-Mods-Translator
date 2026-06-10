import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../helpers/test_database.dart';

/// Regression tests for bulkImportTmxEntries aborting mid-import when the
/// same (source_hash, target_language_id) pair appears more than once in
/// the imported entry list. The pre-computed existing-row lookup was never
/// updated during the insert loop, so the second duplicate within a chunk
/// hit UNIQUE(source_hash, target_language_id) and rolled the chunk back,
/// leaving the TM half-imported (earlier chunks already committed).
void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationMemoryRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  TranslationMemoryEntry entry({
    required String id,
    required String hash,
    String targetLang = 'lang_fr',
    String sourceText = 'src',
    required String translatedText,
  }) {
    return TranslationMemoryEntry(
      id: id,
      sourceText: sourceText,
      sourceHash: hash,
      sourceLanguageId: 'lang_en',
      targetLanguageId: targetLang,
      translatedText: translatedText,
      createdAt: 100,
      lastUsedAt: 100,
      updatedAt: 100,
    );
  }

  Future<List<Map<String, Object?>>> rowsForHash(String hash) => db.query(
        'translation_memory',
        where: 'source_hash = ?',
        whereArgs: [hash],
      );

  test(
      'within-chunk duplicate (source_hash, target_language_id) does not '
      'abort the import; first entry wins', () async {
    final result = await repo.bulkImportTmxEntries(
      [
        entry(id: 'a', hash: 'dup', translatedText: 'first'),
        entry(id: 'b', hash: 'dup', translatedText: 'second'),
      ],
      overwriteExisting: false,
    );

    expect(result.isOk, isTrue,
        reason: 'duplicate must not abort the chunk: $result');
    expect(result.unwrap().persisted, 1);
    expect(result.unwrap().skipped, 1);

    final rows = await rowsForHash('dup');
    expect(rows, hasLength(1));
    expect(rows.single['translated_text'], 'first',
        reason: 'first-wins, matching TMX tuv convention');
  });

  test(
      'within-chunk duplicate with overwriteExisting=true still follows '
      'first-wins within the same import', () async {
    final result = await repo.bulkImportTmxEntries(
      [
        entry(id: 'a', hash: 'dup', translatedText: 'first'),
        entry(id: 'b', hash: 'dup', translatedText: 'second'),
      ],
      overwriteExisting: true,
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap().persisted, 1);
    expect(result.unwrap().skipped, 1);

    final rows = await rowsForHash('dup');
    expect(rows, hasLength(1));
    expect(rows.single['translated_text'], 'first');
  });

  test(
      'cross-chunk duplicate is skipped (first-wins) even with '
      'overwriteExisting=true', () async {
    // Chunk size is 500: entry 0 lands in chunk 1, the duplicate (index
    // 500) lands in chunk 2. Without run-level tracking, chunk 2 sees the
    // chunk-1 row as "existing" and overwrites it (last-wins).
    final entries = <TranslationMemoryEntry>[
      entry(id: 'e0', hash: 'dup', translatedText: 'first'),
      for (var i = 1; i < 500; i++)
        entry(id: 'e$i', hash: 'h$i', translatedText: 't$i'),
      entry(id: 'e500', hash: 'dup', translatedText: 'second'),
    ];

    final result = await repo.bulkImportTmxEntries(
      entries,
      overwriteExisting: true,
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap().persisted, 500);
    expect(result.unwrap().skipped, 1);

    final rows = await rowsForHash('dup');
    expect(rows, hasLength(1));
    expect(rows.single['translated_text'], 'first');
  });

  test('row that pre-exists in the DB is updated when overwriteExisting=true',
      () async {
    await db.insert('translation_memory', {
      'id': 'pre',
      'source_hash': 'dup',
      'source_language_id': 'lang_en',
      'target_language_id': 'lang_fr',
      'source_text': 'src',
      'translated_text': 'old',
      'usage_count': 7,
      'created_at': 1,
      'last_used_at': 1,
      'updated_at': 1,
    });

    final result = await repo.bulkImportTmxEntries(
      [entry(id: 'a', hash: 'dup', translatedText: 'new')],
      overwriteExisting: true,
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap().persisted, 1);
    expect(result.unwrap().skipped, 0);

    final rows = await rowsForHash('dup');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'pre');
    expect(rows.single['translated_text'], 'new');
    expect(rows.single['usage_count'], 7,
        reason: 'overwrite preserves usage_count');
  });

  test('row that pre-exists in the DB is skipped when overwriteExisting=false',
      () async {
    await db.insert('translation_memory', {
      'id': 'pre',
      'source_hash': 'dup',
      'source_language_id': 'lang_en',
      'target_language_id': 'lang_fr',
      'source_text': 'src',
      'translated_text': 'old',
      'usage_count': 0,
      'created_at': 1,
      'last_used_at': 1,
      'updated_at': 1,
    });

    final result = await repo.bulkImportTmxEntries(
      [entry(id: 'a', hash: 'dup', translatedText: 'new')],
      overwriteExisting: false,
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap().persisted, 0);
    expect(result.unwrap().skipped, 1);

    final rows = await rowsForHash('dup');
    expect(rows.single['translated_text'], 'old');
  });

  test(
      'same source_hash with different target languages is NOT a duplicate',
      () async {
    final result = await repo.bulkImportTmxEntries(
      [
        entry(id: 'a', hash: 'h1', targetLang: 'lang_fr', translatedText: 'fr'),
        entry(id: 'b', hash: 'h1', targetLang: 'lang_de', translatedText: 'de'),
      ],
      overwriteExisting: false,
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap().persisted, 2);
    expect(result.unwrap().skipped, 0);
    expect(await rowsForHash('h1'), hasLength(2));
  });
}
