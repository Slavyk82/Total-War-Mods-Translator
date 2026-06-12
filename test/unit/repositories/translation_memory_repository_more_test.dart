// Coverage for TranslationMemoryRepository methods NOT exercised by the sibling
// suites (translation_memory_repository_methods_test.dart,
// translation_memory_repository_export_filters_test.dart, the usage/batch/
// bulk-import/dedup suites, and the mixin suites).
//
// Methods exercised here:
//   getAll, deleteByAge, deleteAllEntries, countCleanupCandidates,
//   getEntriesByLanguage, getWithFilters, findBySourceHash, searchByLike.
// Plus a couple of complementary minUsageCount edge cases on countWithFilters /
// getPage (boundary / empty) that the export-filters suite does not assert.
//
// Schema notes that drive the fixtures:
// - translation_memory has UNIQUE(source_hash, target_language_id) and
//   CHECK (usage_count >= 0); rows are kept DISTINCT on (source_hash, target).
// - *_at columns are Unix SECONDS. deleteByAge / countCleanupCandidates compare
//   COALESCE(last_used_at, 0) against now - unusedDays*86400, so fixtures pin
//   last_used_at to absolute Unix-second timestamps relative to "now".
// - getStatistics in this repo takes only targetLanguageId — there is NO
//   gameCode branch, so it is not testable here (see report).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../helpers/test_database.dart';

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

  // Current time in Unix SECONDS, matching the repo's own clock arithmetic.
  int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  const day = 24 * 60 * 60;

  // Raw insert helper so fixtures stay terse and DISTINCT on the unique key.
  Future<void> seed({
    required String id,
    required String sourceHash,
    String sourceText = 'src',
    String translatedText = 'tgt',
    String sourceLanguageId = 'lang_en',
    String targetLanguageId = 'lang_fr',
    int usageCount = 0,
    int? createdAt,
    int? lastUsedAt,
    int? updatedAt,
  }) async {
    final base = nowSeconds();
    await db.insert('translation_memory', {
      'id': id,
      'source_text': sourceText,
      'source_hash': sourceHash,
      'source_language_id': sourceLanguageId,
      'target_language_id': targetLanguageId,
      'translated_text': translatedText,
      'usage_count': usageCount,
      'created_at': createdAt ?? base,
      'last_used_at': lastUsedAt ?? base,
      'updated_at': updatedAt ?? base,
    });
  }

  group('getAll', () {
    test('returns all rows ordered by last_used_at DESC', () async {
      final base = nowSeconds();
      await seed(id: 'old', sourceHash: 'h-old', lastUsedAt: base - 300);
      await seed(id: 'new', sourceHash: 'h-new', lastUsedAt: base - 10);
      await seed(id: 'mid', sourceHash: 'h-mid', lastUsedAt: base - 100);

      final result = await repo.getAll();

      expect(result.isOk, isTrue);
      expect(
        result.value.map((e) => e.id).toList(),
        equals(['new', 'mid', 'old']),
      );
    });

    test('returns an empty list when the table is empty', () async {
      final result = await repo.getAll();

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('deleteByAge', () {
    test('deletes only rows last used before the cutoff and sums their usage',
        () async {
      final base = nowSeconds();
      // unusedDays = 30 -> cutoff = now - 30 days.
      // Two rows are well past the cutoff (60 / 90 days old) and one is recent.
      await seed(
        id: 'stale-a',
        sourceHash: 'h-a',
        usageCount: 4,
        lastUsedAt: base - (60 * day),
      );
      await seed(
        id: 'stale-b',
        sourceHash: 'h-b',
        usageCount: 6,
        lastUsedAt: base - (90 * day),
      );
      await seed(
        id: 'fresh',
        sourceHash: 'h-c',
        usageCount: 99,
        lastUsedAt: base - (1 * day),
      );

      final result = await repo.deleteByAge(unusedDays: 30);

      expect(result.isOk, isTrue);
      expect(result.value.deletedCount, equals(2));
      expect(result.value.deletedUsageSum, equals(10)); // 4 + 6

      final remaining = await db.query('translation_memory');
      expect(remaining.map((r) => r['id']).toList(), equals(['fresh']));
    });

    test('returns zero and deletes nothing when unusedDays <= 0', () async {
      await seed(id: 'a', sourceHash: 'h-a', lastUsedAt: 0, usageCount: 3);

      final result = await repo.deleteByAge(unusedDays: 0);

      expect(result.isOk, isTrue);
      expect(result.value.deletedCount, equals(0));
      expect(result.value.deletedUsageSum, equals(0));

      // The early-return must not touch the table even though the row is ancient.
      final remaining = await db.query('translation_memory');
      expect(remaining.length, equals(1));
    });

    // NOTE: `last_used_at` is NOT NULL in the schema, so the COALESCE(last_used_at, 0)
    // fallback in deleteByAge is defensive dead code that cannot be exercised
    // through a normal insert — no test for it.
  });

  group('deleteAllEntries', () {
    test('wipes the table and returns the deleted count and usage sum',
        () async {
      await seed(id: 'a', sourceHash: 'h-a', usageCount: 2);
      await seed(id: 'b', sourceHash: 'h-b', usageCount: 5);
      await seed(id: 'c', sourceHash: 'h-c', usageCount: 8);

      final result = await repo.deleteAllEntries();

      expect(result.isOk, isTrue);
      expect(result.value.deletedCount, equals(3));
      expect(result.value.deletedUsageSum, equals(15));

      expect(await db.query('translation_memory'), isEmpty);
    });

    test('returns zero counts on an already-empty table', () async {
      final result = await repo.deleteAllEntries();

      expect(result.isOk, isTrue);
      expect(result.value.deletedCount, equals(0));
      // COALESCE(SUM(...), 0) keeps this an int 0, not null.
      expect(result.value.deletedUsageSum, equals(0));
    });
  });

  group('countCleanupCandidates', () {
    test('counts rows older than the cutoff without deleting them', () async {
      final base = nowSeconds();
      await seed(id: 'stale-a', sourceHash: 'h-a', lastUsedAt: base - (40 * day));
      await seed(id: 'stale-b', sourceHash: 'h-b', lastUsedAt: base - (50 * day));
      await seed(id: 'fresh', sourceHash: 'h-c', lastUsedAt: base - (2 * day));

      final result = await repo.countCleanupCandidates(unusedDays: 30);

      expect(result.isOk, isTrue);
      expect(result.value['willBeDeleted'], equals(2));
      expect(result.value['unusedOnly'], equals(2));

      // Pure preview: nothing was removed.
      expect((await db.query('translation_memory')).length, equals(3));
    });

    test('returns zero counts when unusedDays <= 0', () async {
      await seed(id: 'a', sourceHash: 'h-a', lastUsedAt: 0);

      final result = await repo.countCleanupCandidates(unusedDays: 0);

      expect(result.isOk, isTrue);
      expect(result.value['willBeDeleted'], equals(0));
      expect(result.value['unusedOnly'], equals(0));
    });

    test('returns zero when no row is old enough', () async {
      final base = nowSeconds();
      await seed(id: 'fresh', sourceHash: 'h-c', lastUsedAt: base - (1 * day));

      final result = await repo.countCleanupCandidates(unusedDays: 30);

      expect(result.isOk, isTrue);
      expect(result.value['willBeDeleted'], equals(0));
    });
  });

  group('getEntriesByLanguage', () {
    test('groups counts by target_language_id', () async {
      await seed(id: 'fr1', sourceHash: 'h1', targetLanguageId: 'lang_fr');
      await seed(id: 'fr2', sourceHash: 'h2', targetLanguageId: 'lang_fr');
      await seed(id: 'de1', sourceHash: 'h3', targetLanguageId: 'lang_de');
      await seed(id: 'es1', sourceHash: 'h4', targetLanguageId: 'lang_es');
      await seed(id: 'es2', sourceHash: 'h5', targetLanguageId: 'lang_es');
      await seed(id: 'es3', sourceHash: 'h6', targetLanguageId: 'lang_es');

      final result = await repo.getEntriesByLanguage();

      expect(result.isOk, isTrue);
      expect(result.value['lang_fr'], equals(2));
      expect(result.value['lang_de'], equals(1));
      expect(result.value['lang_es'], equals(3));
      expect(result.value.length, equals(3));
    });

    test('returns an empty map on an empty table', () async {
      final result = await repo.getEntriesByLanguage();

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('getWithFilters', () {
    setUp(() async {
      // usage_count 1..5 for lang_fr (distinct hashes), one lang_de row.
      for (var i = 1; i <= 5; i++) {
        await seed(
          id: 'fr$i',
          sourceHash: 'h-fr$i',
          targetLanguageId: 'lang_fr',
          usageCount: i,
        );
      }
      await seed(
        id: 'de1',
        sourceHash: 'h-de1',
        targetLanguageId: 'lang_de',
        usageCount: 9,
      );
    });

    test('returns all rows ordered by usage_count DESC by default', () async {
      final result = await repo.getWithFilters();

      expect(result.isOk, isTrue);
      // de1 (9) first, then fr5..fr1.
      expect(
        result.value.map((e) => e.id).toList(),
        equals(['de1', 'fr5', 'fr4', 'fr3', 'fr2', 'fr1']),
      );
    });

    test('filters by target language', () async {
      final result = await repo.getWithFilters(targetLanguageId: 'lang_fr');

      expect(result.isOk, isTrue);
      expect(result.value.length, equals(5));
      expect(result.value.every((e) => e.targetLanguageId == 'lang_fr'), isTrue);
      // Still ordered usage_count DESC within the language.
      expect(result.value.first.id, equals('fr5'));
    });

    test('honours limit and offset', () async {
      final result = await repo.getWithFilters(
        targetLanguageId: 'lang_fr',
        limit: 2,
        offset: 1,
      );

      expect(result.isOk, isTrue);
      // Skip fr5, take fr4, fr3.
      expect(result.value.map((e) => e.id).toList(), equals(['fr4', 'fr3']));
    });

    test('supports a custom orderBy clause', () async {
      final result = await repo.getWithFilters(
        targetLanguageId: 'lang_fr',
        orderBy: 'usage_count ASC',
      );

      expect(result.isOk, isTrue);
      expect(
        result.value.map((e) => e.id).toList(),
        equals(['fr1', 'fr2', 'fr3', 'fr4', 'fr5']),
      );
    });

    test('returns an empty list when no row matches the language', () async {
      final result = await repo.getWithFilters(targetLanguageId: 'lang_zz');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('findBySourceHash', () {
    test('returns the matching row for the hash and target language', () async {
      await seed(
        id: 'fr',
        sourceHash: 'shared',
        targetLanguageId: 'lang_fr',
        translatedText: 'Bonjour',
      );
      await seed(
        id: 'de',
        sourceHash: 'shared',
        targetLanguageId: 'lang_de',
        translatedText: 'Hallo',
      );

      final result = await repo.findBySourceHash('shared', 'lang_de');

      expect(result.isOk, isTrue);
      expect(result.value.id, equals('de'));
      expect(result.value.translatedText, equals('Hallo'));
    });

    test('returns Err when the hash is absent', () async {
      await seed(id: 'a', sourceHash: 'present', targetLanguageId: 'lang_fr');

      final result = await repo.findBySourceHash('missing', 'lang_fr');

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });

    test('returns Err when the hash exists but for a different language',
        () async {
      await seed(id: 'a', sourceHash: 'present', targetLanguageId: 'lang_fr');

      final result = await repo.findBySourceHash('present', 'lang_de');

      expect(result.isErr, isTrue);
    });
  });

  group('searchByLike', () {
    setUp(() async {
      await seed(
        id: 'a',
        sourceHash: 'h-a',
        sourceText: 'Attack the enemy',
        translatedText: 'Attaquer l ennemi',
        targetLanguageId: 'lang_fr',
      );
      await seed(
        id: 'b',
        sourceHash: 'h-b',
        sourceText: 'Defend the city',
        translatedText: 'Defendre la ville',
        targetLanguageId: 'lang_fr',
        usageCount: 5,
      );
      await seed(
        id: 'c',
        sourceHash: 'h-c',
        sourceText: 'Attack formation',
        translatedText: 'Formation d attaque',
        targetLanguageId: 'lang_de',
      );
    });

    test('matches on source text when scope is "source"', () async {
      final result = await repo.searchByLike(
        searchText: 'Attack',
        searchScope: 'source',
      );

      expect(result.isOk, isTrue);
      expect(
        result.value.map((e) => e.id).toSet(),
        equals({'a', 'c'}),
      );
    });

    test('matches on translated text when scope is "target"', () async {
      final result = await repo.searchByLike(
        searchText: 'ville',
        searchScope: 'target',
      );

      expect(result.isOk, isTrue);
      expect(result.value.map((e) => e.id).toList(), equals(['b']));
    });

    test('matches source OR target when scope is "both"', () async {
      // LIKE '%attaque%' is case-insensitive and matches BOTH a's target
      // "Attaquer l ennemi" (prefix "Attaque...") and c's target
      // "Formation d attaque" — so the OR clause returns a and c.
      final result = await repo.searchByLike(
        searchText: 'attaque',
        searchScope: 'both',
      );

      expect(result.isOk, isTrue);
      expect(result.value.map((e) => e.id).toSet(), equals({'a', 'c'}));
    });

    test('restricts results by target language when provided', () async {
      final result = await repo.searchByLike(
        searchText: 'Attack',
        searchScope: 'source',
        targetLanguageId: 'lang_fr',
      );

      expect(result.isOk, isTrue);
      // Only a is lang_fr; c is lang_de and is excluded.
      expect(result.value.map((e) => e.id).toList(), equals(['a']));
    });

    test('orders matches by usage_count DESC and respects the limit', () async {
      // Both rows contain "the"; b has the higher usage_count.
      final result = await repo.searchByLike(
        searchText: 'the',
        searchScope: 'source',
        limit: 1,
      );

      expect(result.isOk, isTrue);
      expect(result.value.length, equals(1));
      expect(result.value.first.id, equals('b'));
    });

    test('returns empty when nothing matches', () async {
      final result = await repo.searchByLike(
        searchText: 'zzzznomatch',
        searchScope: 'both',
      );

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('escapes LIKE wildcards so % is treated literally', () async {
      await seed(
        id: 'pct',
        sourceHash: 'h-pct',
        sourceText: '100% complete',
        targetLanguageId: 'lang_fr',
      );

      // The literal "%" must only match the row that actually contains it,
      // not every row (which is what an unescaped % wildcard would do).
      final result = await repo.searchByLike(
        searchText: '100%',
        searchScope: 'source',
      );

      expect(result.isOk, isTrue);
      expect(result.value.map((e) => e.id).toList(), equals(['pct']));
    });
  });

  // Complementary minUsageCount edge cases NOT asserted by the export-filters
  // suite (it covers minUsageCount=3/4 happy paths). Here: the >=0 boundary
  // (matches everything) and a threshold above every row (matches nothing).
  group('minUsageCount boundary branches', () {
    setUp(() async {
      await seed(id: 'u0', sourceHash: 'h0', usageCount: 0);
      await seed(id: 'u1', sourceHash: 'h1', usageCount: 1);
      await seed(id: 'u2', sourceHash: 'h2', usageCount: 2);
    });

    test('countWithFilters minUsageCount=0 still applies the clause and '
        'counts every row', () async {
      final result = await repo.countWithFilters(minUsageCount: 0);

      expect(result.isOk, isTrue);
      expect(result.value, equals(3));
    });

    test('countWithFilters returns 0 when the threshold exceeds every row',
        () async {
      final result = await repo.countWithFilters(minUsageCount: 100);

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });

    test('getPage returns an empty page when the threshold exceeds every row',
        () async {
      final result = await repo.getPage(
        offset: 0,
        pageSize: 100,
        minUsageCount: 100,
      );

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });
}
