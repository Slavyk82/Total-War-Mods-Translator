import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';

import '../../../helpers/test_database.dart';

// Regression tests for TranslationMemoryFtsMixin.searchFts5 column scoping.
//
// Production bug covered here: searchFts5 prefixed the multi-term FTS5 query
// with a column filter via plain string concatenation:
//
//   source_text:"shield"* OR "wall"*
//
// In FTS5 query syntax a 'col:' specifier binds only to the immediately
// following phrase, NOT to the whole OR expression — so every term after the
// first was matched against ALL indexed columns, and scoped searches leaked
// matches from the other column. The fix parenthesizes the expression:
//
//   source_text : ("shield"* OR "wall"*)
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
    required String translatedText,
  }) async {
    await db.insert('translation_memory', {
      'id': id,
      'source_text': sourceText,
      'source_hash': 'hash-$id',
      'source_language_id': 'lang-en',
      'target_language_id': targetLang,
      'translated_text': translatedText,
      'usage_count': 0,
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

    // Matches in source only: contains both search terms in source_text,
    // neither in translated_text.
    await seedEntry(
      id: 'tm-source-only',
      sourceText: 'shield wall formation',
      translatedText: 'formation de la tortue',
    );

    // Matches in target only: the SECOND search term ('wall') appears only
    // in translated_text; source_text contains neither term. With the
    // unparenthesized column filter the second OR term escapes the scope
    // and this row leaks into source-scoped results.
    await seedEntry(
      id: 'tm-target-only',
      sourceText: 'unrelated cavalry charge',
      translatedText: 'the great wall painting',
    );
  });

  tearDown(() => TestDatabase.close(db));

  group('TranslationMemoryFtsMixin.searchFts5 column scoping', () {
    test(
        'source scope does not leak entries whose 2nd term matches only '
        'translated_text', () async {
      final result = await repo.searchFts5(
        searchText: 'shield wall',
        searchScope: 'source',
      );

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      final ids = result.unwrap().map((e) => e.id).toList();
      expect(ids, contains('tm-source-only'));
      expect(ids, isNot(contains('tm-target-only')),
          reason: "scoped to source_text, the term 'wall' must not match "
              'the translated_text column');
    });

    test(
        'target scope does not leak entries whose 2nd term matches only '
        'source_text', () async {
      // 'great' (1st term) appears only in tm-target-only's translated_text;
      // 'cavalry' (2nd term) appears only in tm-target-only's source_text
      // and 'formation' only in tm-source-only's source/translated.
      final result = await repo.searchFts5(
        searchText: 'tortue cavalry',
        searchScope: 'target',
      );

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      final ids = result.unwrap().map((e) => e.id).toList();
      expect(ids, contains('tm-source-only'),
          reason: "'tortue' is in tm-source-only's translated_text");
      expect(ids, isNot(contains('tm-target-only')),
          reason: "scoped to translated_text, the term 'cavalry' must not "
              'match the source_text column');
    });

    test('both scope still matches terms in either column', () async {
      final result = await repo.searchFts5(
        searchText: 'shield wall',
        searchScope: 'both',
      );

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      final ids = result.unwrap().map((e) => e.id).toList();
      expect(ids, contains('tm-source-only'));
      expect(ids, contains('tm-target-only'),
          reason: "'wall' appears in tm-target-only's translated_text and "
              "scope 'both' covers both columns");
    });

    test('single-term scoped search still works after parenthesization',
        () async {
      final result = await repo.searchFts5(
        searchText: 'shield',
        searchScope: 'source',
      );

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      expect(result.unwrap().map((e) => e.id), contains('tm-source-only'));
    });

    test('prefix matching is preserved inside the scoped group', () async {
      final result = await repo.searchFts5(
        searchText: 'shie wal',
        searchScope: 'source',
      );

      expect(result.isOk, isTrue,
          reason: result.isErr ? '${result.unwrapErr()}' : '');
      final ids = result.unwrap().map((e) => e.id).toList();
      expect(ids, contains('tm-source-only'),
          reason: 'prefix tokens ("shie"* and "wal"*) must still match '
              'shield/wall within the source scope');
      expect(ids, isNot(contains('tm-target-only')));
    });

    test('punctuated scoped search returns Ok (no FTS5 syntax error)',
        () async {
      final result = await repo.searchFts5(
        searchText: "shield-wall don't",
        searchScope: 'source',
      );

      expect(result.isOk, isTrue,
          reason: 'punctuated input must not produce an FTS5 syntax error: '
              '${result.isErr ? result.unwrapErr() : ''}');
    });
  });
}
