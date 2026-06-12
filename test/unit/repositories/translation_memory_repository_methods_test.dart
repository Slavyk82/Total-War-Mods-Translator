// Coverage for TranslationMemoryRepository's OWN CRUD/query methods plus the
// TranslationMemoryMigrationMixin it hosts.
//
// OWN methods exercised here: getById, insert, update, delete, findByHash,
// getStatistics, countWithFilters, getPage, deleteByLanguageId.
// MIGRATION mixin methods: getEntriesWithLegacyHashes, countLegacyHashes,
// updateHash, updateHashesBatch.
//
// Intentionally NOT re-tested (covered elsewhere): incrementUsageCountBatch,
// the minUsageCount export-filter cases on getPage/countWithFilters, the batch
// upsert mixin, and the FTS mixin.
//
// Schema notes that drive the fixtures:
// - translation_memory has UNIQUE(source_hash, target_language_id) and
//   CHECK (usage_count >= 0). It has NO created_at <= updated_at constraint,
//   but other tables do, so timestamps are kept sane regardless.
// - *_at columns are Unix SECONDS; small base timestamps are used.
// - The migration mixin treats source_hash with length < 64 as "legacy"; a
//   full SHA-256 is 64 hex chars and counts as "modern". Both kinds are seeded
//   so the legacy filters can be asserted with exact counts.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  // A genuine 64-char SHA-256-shaped hash ("modern"). Anything shorter is
  // treated as a legacy hash by the migration mixin.
  const modernHash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationMemoryRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  TranslationMemoryEntry makeEntry({
    String id = 'tm-1',
    String sourceText = 'Hello',
    String sourceHash = 'h-1',
    String sourceLanguageId = 'lang_en',
    String targetLanguageId = 'lang_fr',
    String translatedText = 'Bonjour',
    String? translationProviderId,
    int usageCount = 0,
    int createdAt = 1000,
    int lastUsedAt = 1000,
    int updatedAt = 1000,
  }) {
    return TranslationMemoryEntry(
      id: id,
      sourceText: sourceText,
      sourceHash: sourceHash,
      sourceLanguageId: sourceLanguageId,
      targetLanguageId: targetLanguageId,
      translatedText: translatedText,
      translationProviderId: translationProviderId,
      usageCount: usageCount,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      updatedAt: updatedAt,
    );
  }

  // Raw insert helper for tests that need many rows without going through the
  // repository (keeps fixtures terse and avoids over-asserting insert()).
  Future<void> seed({
    required String id,
    required String sourceHash,
    String sourceLanguageId = 'lang_en',
    String targetLanguageId = 'lang_fr',
    int usageCount = 0,
    int lastUsedAt = 1000,
  }) async {
    await db.insert('translation_memory', {
      'id': id,
      'source_text': 'src-$id',
      'source_hash': sourceHash,
      'source_language_id': sourceLanguageId,
      'target_language_id': targetLanguageId,
      'translated_text': 'tgt-$id',
      'usage_count': usageCount,
      'created_at': 1000,
      'last_used_at': lastUsedAt,
      'updated_at': 1000,
    });
  }

  group('insert', () {
    test('inserts an entry and persists every field', () async {
      final entry = makeEntry(
        translationProviderId: 'provider_deepl',
        usageCount: 3,
      );

      final result = await repo.insert(entry);

      expect(result.isOk, isTrue);
      expect(result.value, equals(entry));

      final rows =
          await db.query('translation_memory', where: 'id = ?', whereArgs: ['tm-1']);
      expect(rows.length, equals(1));
      expect(rows.first['source_text'], equals('Hello'));
      expect(rows.first['translated_text'], equals('Bonjour'));
      expect(rows.first['translation_provider_id'], equals('provider_deepl'));
      expect(rows.first['usage_count'], equals(3));
    });

    test('fails on duplicate (source_hash, target_language_id) unique key',
        () async {
      await repo.insert(makeEntry(id: 'a', sourceHash: 'dup'));

      // Same hash + same target language violates UNIQUE; ConflictAlgorithm.abort.
      final result =
          await repo.insert(makeEntry(id: 'b', sourceHash: 'dup'));

      expect(result.isErr, isTrue);
    });

    test('fails on duplicate primary key id', () async {
      await repo.insert(makeEntry(id: 'same', sourceHash: 'h-a'));

      final result =
          await repo.insert(makeEntry(id: 'same', sourceHash: 'h-b'));

      expect(result.isErr, isTrue);
    });
  });

  group('getById', () {
    test('returns the entry when present', () async {
      await repo.insert(makeEntry(id: 'tm-x'));

      final result = await repo.getById('tm-x');

      expect(result.isOk, isTrue);
      expect(result.value.id, equals('tm-x'));
      expect(result.value.translatedText, equals('Bonjour'));
    });

    test('returns Err when id is missing', () async {
      final result = await repo.getById('nope');

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('update', () {
    test('updates an existing entry', () async {
      await repo.insert(makeEntry(id: 'tm-u', translatedText: 'old'));

      final updated = makeEntry(
        id: 'tm-u',
        translatedText: 'new',
        usageCount: 7,
        updatedAt: 2000,
      );
      final result = await repo.update(updated);

      expect(result.isOk, isTrue);
      expect(result.value.translatedText, equals('new'));

      final reread = await repo.getById('tm-u');
      expect(reread.value.translatedText, equals('new'));
      expect(reread.value.usageCount, equals(7));
    });

    test('returns Err when updating a non-existent id', () async {
      final result = await repo.update(makeEntry(id: 'ghost'));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('delete', () {
    test('deletes an existing entry', () async {
      await repo.insert(makeEntry(id: 'tm-d'));

      final result = await repo.delete('tm-d');

      expect(result.isOk, isTrue);
      final reread = await repo.getById('tm-d');
      expect(reread.isErr, isTrue);
    });

    test('returns Err when deleting a non-existent id', () async {
      final result = await repo.delete('absent');

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('findByHash', () {
    test('returns the entry matching hash and target language', () async {
      await repo.insert(makeEntry(
        id: 'fr',
        sourceHash: 'shared',
        targetLanguageId: 'lang_fr',
      ));
      await repo.insert(makeEntry(
        id: 'de',
        sourceHash: 'shared',
        targetLanguageId: 'lang_de',
      ));

      final result = await repo.findByHash('shared', 'lang_de');

      expect(result.isOk, isTrue);
      expect(result.value.id, equals('de'));
    });

    test('returns Err when no row matches', () async {
      await repo.insert(makeEntry(sourceHash: 'present'));

      final result = await repo.findByHash('missing', 'lang_fr');

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('getStatistics', () {
    test('aggregates totals across all languages when unfiltered', () async {
      await seed(id: 'a', sourceHash: 'ha', targetLanguageId: 'lang_fr', usageCount: 2);
      await seed(id: 'b', sourceHash: 'hb', targetLanguageId: 'lang_fr', usageCount: 3);
      await seed(id: 'c', sourceHash: 'hc', targetLanguageId: 'lang_de', usageCount: 5);

      final result = await repo.getStatistics();

      expect(result.isOk, isTrue);
      expect(result.value['total_entries'], equals(3));
      expect(result.value['total_usage'], equals(10));
    });

    test('filters totals by target language', () async {
      await seed(id: 'a', sourceHash: 'ha', targetLanguageId: 'lang_fr', usageCount: 2);
      await seed(id: 'b', sourceHash: 'hb', targetLanguageId: 'lang_fr', usageCount: 3);
      await seed(id: 'c', sourceHash: 'hc', targetLanguageId: 'lang_de', usageCount: 5);

      final result = await repo.getStatistics(targetLanguageId: 'lang_fr');

      expect(result.isOk, isTrue);
      expect(result.value['total_entries'], equals(2));
      expect(result.value['total_usage'], equals(5));
    });

    test('returns zero totals on an empty table', () async {
      final result = await repo.getStatistics();

      expect(result.isOk, isTrue);
      expect(result.value['total_entries'], equals(0));
      // COALESCE(SUM(...), 0) keeps this an int 0, not null.
      expect(result.value['total_usage'], equals(0));
    });
  });

  group('countWithFilters', () {
    // minUsageCount combinations are covered in the export-filters test; here
    // we exercise the unfiltered count, the language filter, and the empty case.
    setUp(() async {
      await seed(id: 'a', sourceHash: 'ha', targetLanguageId: 'lang_fr', usageCount: 1);
      await seed(id: 'b', sourceHash: 'hb', targetLanguageId: 'lang_fr', usageCount: 4);
      await seed(id: 'c', sourceHash: 'hc', targetLanguageId: 'lang_de', usageCount: 9);
    });

    test('counts all rows when unfiltered', () async {
      final result = await repo.countWithFilters();

      expect(result.isOk, isTrue);
      expect(result.value, equals(3));
    });

    test('counts rows for a single target language', () async {
      final result = await repo.countWithFilters(targetLanguageId: 'lang_fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));
    });

    test('returns 0 when the language has no rows', () async {
      final result = await repo.countWithFilters(targetLanguageId: 'lang_es');

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('getPage', () {
    // Pages order by id ASC. minUsageCount paging is covered in the export
    // test; here we focus on the language filter, ordering, and offset/limit.
    setUp(() async {
      await seed(id: 'tm1', sourceHash: 'h1', targetLanguageId: 'lang_fr');
      await seed(id: 'tm2', sourceHash: 'h2', targetLanguageId: 'lang_fr');
      await seed(id: 'tm3', sourceHash: 'h3', targetLanguageId: 'lang_fr');
      await seed(id: 'tm4', sourceHash: 'h4', targetLanguageId: 'lang_de');
    });

    test('returns rows for the language ordered by id ASC', () async {
      final result =
          await repo.getPage(offset: 0, pageSize: 100, targetLanguageId: 'lang_fr');

      expect(result.isOk, isTrue);
      expect(result.value.map((e) => e.id).toList(), equals(['tm1', 'tm2', 'tm3']));
    });

    test('respects offset and pageSize within the filtered set', () async {
      final result =
          await repo.getPage(offset: 1, pageSize: 1, targetLanguageId: 'lang_fr');

      expect(result.isOk, isTrue);
      expect(result.value.map((e) => e.id).toList(), equals(['tm2']));
    });

    test('returns an empty page when the offset is past the end', () async {
      final result = await repo.getPage(offset: 50, pageSize: 10);

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('deleteByLanguageId', () {
    test('deletes rows referencing the language as source OR target', () async {
      // Target = lang_fr
      await seed(id: 'a', sourceHash: 'ha', targetLanguageId: 'lang_fr');
      // Source = lang_fr (target is something else)
      await seed(
        id: 'b',
        sourceHash: 'hb',
        sourceLanguageId: 'lang_fr',
        targetLanguageId: 'lang_de',
      );
      // Unrelated to lang_fr entirely
      await seed(
        id: 'c',
        sourceHash: 'hc',
        sourceLanguageId: 'lang_en',
        targetLanguageId: 'lang_de',
      );

      final result = await repo.deleteByLanguageId('lang_fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final remaining = await db.query('translation_memory');
      expect(remaining.map((r) => r['id']).toList(), equals(['c']));
    });

    test('returns 0 when no row references the language', () async {
      await seed(id: 'a', sourceHash: 'ha');

      final result = await repo.deleteByLanguageId('lang_zz');

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('migration mixin: getEntriesWithLegacyHashes', () {
    setUp(() async {
      // Two legacy (short) hashes and one modern (64-char) hash.
      await seed(id: 'legacy-1', sourceHash: 'abc');
      await seed(id: 'legacy-2', sourceHash: 'def456');
      await seed(id: 'modern-1', sourceHash: modernHash);
    });

    test('returns only entries whose source_hash is shorter than 64 chars',
        () async {
      final result = await repo.getEntriesWithLegacyHashes();

      expect(result.isOk, isTrue);
      // Ordered by id; both legacy rows, never the modern one.
      expect(
        result.value.map((e) => e.id).toList(),
        equals(['legacy-1', 'legacy-2']),
      );
    });

    test('honours limit and offset (ordered by id)', () async {
      final firstPage =
          await repo.getEntriesWithLegacyHashes(limit: 1, offset: 0);
      final secondPage =
          await repo.getEntriesWithLegacyHashes(limit: 1, offset: 1);

      expect(firstPage.value.map((e) => e.id).toList(), equals(['legacy-1']));
      expect(secondPage.value.map((e) => e.id).toList(), equals(['legacy-2']));
    });

    test('returns empty when every hash is modern', () async {
      await db.delete('translation_memory',
          where: 'id IN (?, ?)', whereArgs: ['legacy-1', 'legacy-2']);

      final result = await repo.getEntriesWithLegacyHashes();

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('migration mixin: countLegacyHashes', () {
    test('counts only legacy (short) hashes', () async {
      await seed(id: 'legacy-1', sourceHash: 'abc');
      await seed(id: 'legacy-2', sourceHash: 'short-hash');
      await seed(id: 'modern-1', sourceHash: modernHash);

      final result = await repo.countLegacyHashes();

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));
    });

    test('returns 0 when there are no legacy hashes', () async {
      await seed(id: 'modern-1', sourceHash: modernHash);

      final result = await repo.countLegacyHashes();

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('migration mixin: updateHash', () {
    test('replaces the source_hash for an entry', () async {
      await seed(id: 'tm-h', sourceHash: 'legacy');

      final result = await repo.updateHash('tm-h', modernHash);

      expect(result.isOk, isTrue);

      final rows = await db.query('translation_memory',
          where: 'id = ?', whereArgs: ['tm-h']);
      expect(rows.first['source_hash'], equals(modernHash));
    });

    test('is a no-op Ok when the id does not exist', () async {
      // update() on a missing row affects 0 rows but does not throw.
      final result = await repo.updateHash('absent', modernHash);

      expect(result.isOk, isTrue);
      final rows = await db.query('translation_memory');
      expect(rows, isEmpty);
    });
  });

  group('migration mixin: updateHashesBatch', () {
    test('updates each entry in the batch and returns the count', () async {
      await seed(id: 'a', sourceHash: 'old-a');
      await seed(id: 'b', sourceHash: 'old-b');

      // Two DISTINCT 64-char hashes. Appending then truncating to 64 would
      // collapse both back to modernHash and trip
      // UNIQUE(source_hash, target_language_id); replace the last 2 chars.
      final result = await repo.updateHashesBatch([
        (id: 'a', newHash: '${modernHash.substring(0, 62)}aa'),
        (id: 'b', newHash: '${modernHash.substring(0, 62)}bb'),
      ]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final rows = await db.query('translation_memory', orderBy: 'id');
      // Both rows now carry 64-char (modern) hashes.
      expect((rows[0]['source_hash'] as String).length, equals(64));
      expect((rows[1]['source_hash'] as String).length, equals(64));
    });

    test('returns Ok(0) for an empty batch', () async {
      final result = await repo.updateHashesBatch([]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });
}
