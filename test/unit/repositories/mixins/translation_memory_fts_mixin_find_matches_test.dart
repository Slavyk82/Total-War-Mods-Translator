import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../../helpers/test_database.dart';

// Regression tests for TranslationMemoryFtsMixin.findMatches.
//
// Two production bugs are covered here:
//
// 1. _buildFts5Query joined raw lowercased words with ' OR ' without quoting
//    them. FTS5 barewords may only contain alphanumerics/underscore, so any
//    ordinary game text with punctuation threw an FTS5 syntax error:
//      'Increases melee attack.' -> fts5: syntax error near "."
//      "don't"                   -> fts5: syntax error near "'"
//      'well-trained'            -> no such column: trained
//    The error was swallowed into Err by executeQuery, so fuzzy TM matching
//    silently returned 'no match' (dead feature).
//
// 2. The findMatches SQL ordered candidates with `ORDER BY bm25(fts)` where
//    `fts` is the join alias. bm25() requires the actual FTS5 table name, so
//    the statement failed to prepare for ALL inputs ('no such column: fts').
//
// These tests run against the real production schema (lib/database/schema.sql)
// on an in-memory SQLite database, including the FTS5 virtual table and its
// sync triggers.
void main() {
  late Database db;
  late TranslationMemoryRepository repo;

  const targetLang = 'lang-fr';
  const now = 1700000000000;

  Future<void> seedEntry({
    required String id,
    required String sourceText,
    String translatedText = 'texte traduit',
    int usageCount = 0,
  }) async {
    await db.insert('translation_memory', {
      'id': id,
      'source_text': sourceText,
      'source_hash': 'hash-$id',
      'source_language_id': 'lang-en',
      'target_language_id': targetLang,
      'translated_text': translatedText,
      'usage_count': usageCount,
      'created_at': now,
      'last_used_at': now,
      'updated_at': now,
    });
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationMemoryRepository();
  });

  tearDown(() => TestDatabase.close(db));

  group('TranslationMemoryFtsMixin.findMatches', () {
    test('returns Ok and finds match for text ending with a period', () async {
      await seedEntry(id: 'tm-1', sourceText: 'Increases melee attack.');

      final result = await repo.findMatches(
        'Increases melee attack.',
        targetLang,
      );

      expect(result.isOk, isTrue,
          reason: 'punctuated input must not produce an FTS5 syntax error: '
              '${result.isErr ? result.unwrapErr() : ''}');
      final matches = result.unwrap();
      expect(matches.map((m) => m.id), contains('tm-1'));
    });

    test('returns Ok and finds match for text with an apostrophe', () async {
      await seedEntry(id: 'tm-2', sourceText: "don't attack the gates");

      final result = await repo.findMatches(
        "don't attack the gates",
        targetLang,
      );

      expect(result.isOk, isTrue,
          reason: 'apostrophe input must not produce an FTS5 syntax error: '
              '${result.isErr ? result.unwrapErr() : ''}');
      final matches = result.unwrap();
      expect(matches.map((m) => m.id), contains('tm-2'));
    });

    test('returns Ok and finds match for hyphenated text', () async {
      await seedEntry(id: 'tm-3', sourceText: 'well-trained soldiers');

      final result = await repo.findMatches(
        'well-trained soldiers',
        targetLang,
      );

      expect(result.isOk, isTrue,
          reason: 'hyphenated input must not produce an FTS5 error: '
              '${result.isErr ? result.unwrapErr() : ''}');
      final matches = result.unwrap();
      expect(matches.map((m) => m.id), contains('tm-3'));
    });

    test('finds a close (non-identical) seeded match above the threshold',
        () async {
      await seedEntry(id: 'tm-4', sourceText: 'Increases melee attack by 5.');

      final result = await repo.findMatches(
        'Increases melee attack.',
        targetLang,
        minConfidence: 0.7,
      );

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      final matches = result.unwrap();
      expect(matches.map((m) => m.id), contains('tm-4'));
    });

    test('filters out candidates below the similarity threshold', () async {
      await seedEntry(id: 'tm-5', sourceText: 'Increases melee attack.');
      await seedEntry(
        id: 'tm-6',
        sourceText: 'Attack of the completely unrelated entry text here.',
      );

      final result = await repo.findMatches(
        'Increases melee attack.',
        targetLang,
      );

      expect(result.isOk, isTrue);
      final ids = result.unwrap().map((m) => m.id).toList();
      expect(ids, contains('tm-5'));
      expect(ids, isNot(contains('tm-6')));
    });

    test('does not return entries for a different target language', () async {
      await seedEntry(id: 'tm-7', sourceText: 'Increases melee attack.');

      final result = await repo.findMatches(
        'Increases melee attack.',
        'lang-de',
      );

      expect(result.isOk, isTrue);
      expect(result.unwrap(), isEmpty);
    });

    test('finds a match for a short input below the token length filter',
        () async {
      // "No" (2 chars) yields no token passing the min-length filter; the
      // tokenizer must fall back to the whole input as one quoted phrase
      // instead of silently returning no results.
      await seedEntry(id: 'tm-short', sourceText: 'No');

      final result = await repo.findMatches('No', targetLang);

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap().map((m) => m.id), contains('tm-short'));
    });

    test('returns Ok with empty list for empty input', () async {
      await seedEntry(id: 'tm-8', sourceText: 'Increases melee attack.');

      final result = await repo.findMatches('', targetLang);

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap(), isEmpty);
    });

    test('returns Ok with empty list for whitespace-only input', () async {
      final result = await repo.findMatches('   \t  ', targetLang);

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap(), isEmpty);
    });

    test('returns Ok for punctuation-only input (no usable tokens)', () async {
      final result = await repo.findMatches('... !! ::', targetLang);

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap(), isEmpty);
    });

    // Regression: a fuzzy query that includes an ultra-common stopword like
    // "the" used to MATCH essentially every row in translation_memory, and the
    // `ORDER BY bm25(...) LIMIT n` then forced SQLite to score the whole table
    // — so on a large TM the query effectively never returned and froze the
    // whole batch translation (2026-06-14). _buildFts5Query now strips English
    // stopwords so the MATCH set only contains rows with the discriminative
    // terms.
    test('an all-stopword input issues no MATCH and returns empty', () async {
      // Seed an entry IDENTICAL to the query: without stopword filtering the
      // FTS query `"the" OR "and" OR "you" OR "are"` would match it (and a
      // large real table besides). With filtering the query is empty, so
      // findMatches short-circuits before issuing the catastrophic MATCH.
      await seedEntry(id: 'tm-stop', sourceText: 'the and you are');

      final result = await repo.findMatches('the and you are', targetLang);

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap(), isEmpty,
          reason: 'a stopword-only fuzzy query must not run an all-rows MATCH');
    });

    test('still finds an entry by its discriminative terms when the query '
        'also contains stopwords', () async {
      // "the" is dropped from the FTS query, but the rare terms ("gravewind",
      // "mandate") still retrieve the entry — stopword filtering must not cause
      // false negatives for ordinary text.
      await seedEntry(id: 'tm-rare', sourceText: 'the gravewind mandate');

      final result = await repo.findMatches('the gravewind mandate', targetLang);

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap().map((m) => m.id), contains('tm-rare'));
    });
  });
}
