import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../../helpers/test_database.dart';

/// Regression test for upsertBatch intra-batch duplicate handling.
///
/// upsertBatch only pre-fetched EXISTING rows from the DB. Two entries in the
/// SAME batch sharing a (source_hash, target_language_id) pair but absent from
/// the DB both took the INSERT branch with ConflictAlgorithm.replace: the second
/// INSERT collided on UNIQUE(source_hash, target_language_id), replaced (deleted
/// + reinserted) the first row, and processedCount was incremented for BOTH —
/// silently losing the first translation and over-stating the count. The
/// aggressive TextNormalizer collapses distinct sources to the same hash, so
/// this happens in practice during rebuildFromTranslations.
void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationMemoryRepository();

    for (final id in ['lang-en', 'lang-fr']) {
      await db.insert('languages', {
        'id': id,
        'code': id,
        'name': id,
        'native_name': id,
        'is_active': 1,
      });
    }
  });

  tearDown(() => TestDatabase.close(db));

  TranslationMemoryEntry entry(String id, String text) => TranslationMemoryEntry(
        id: id,
        sourceText: 'src-$id',
        sourceHash: 'shared-hash',
        sourceLanguageId: 'lang-en',
        targetLanguageId: 'lang-fr',
        translatedText: text,
        usageCount: 0,
        createdAt: 1000,
        lastUsedAt: 1000,
        updatedAt: 1000,
      );

  test('an in-batch duplicate (same hash + target) is deduped first-wins, '
      'not replace-deleted or double-counted', () async {
    final result = await repo.upsertBatch([
      entry('e1', 'first'),
      entry('e2', 'second'),
    ]);

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value, 1,
        reason: 'only one row is actually written; the duplicate must not be '
            'counted');

    final rows = await db.query('translation_memory',
        where: 'source_hash = ?', whereArgs: ['shared-hash']);
    expect(rows, hasLength(1),
        reason: 'the second replace-INSERT must not delete + replace the first');
    expect(rows.single['translated_text'], 'first',
        reason: 'first-wins for an in-batch duplicate');
  });
}
