import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/search/models/search_result.dart';
import 'package:twmt/services/search/utils/fts_query_builder.dart';

void main() {
  group('FtsQueryBuilder FTS5 rank ordering (bm25 is negative, lower = better)',
      () {
    // SQLite FTS5 `rank` defaults to bm25(), which returns NEGATIVE values
    // where MORE NEGATIVE = MORE relevant. Best-first ordering is therefore
    // ascending (`ORDER BY rank`), never `ORDER BY rank DESC`.
    final descendingRank = RegExp(r'ORDER\s+BY\s+rank\s+DESC', caseSensitive: false);
    final ascendingRank = RegExp(r'ORDER\s+BY\s+rank\s*(ASC)?\s*\n', caseSensitive: false);

    test('translation units query orders rank ascending (best match first)',
        () {
      final sql = FtsQueryBuilder.buildTranslationUnitsQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, isNot(matches(descendingRank)));
      expect(sql, matches(ascendingRank));
    });

    test('translation versions query orders rank ascending (best match first)',
        () {
      final sql = FtsQueryBuilder.buildTranslationVersionsQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, isNot(matches(descendingRank)));
      expect(sql, matches(ascendingRank));
    });

    test('translation memory query orders rank ascending (best match first)',
        () {
      final sql = FtsQueryBuilder.buildTranslationMemoryQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, isNot(matches(descendingRank)));
      expect(sql, matches(ascendingRank));
    });
  });

  group('FtsQueryBuilder minRelevanceScore filter (positive convention)', () {
    // The public convention is `relevanceScore = -rank` (positive, higher =
    // better). A minimum positive score of S therefore maps to the SQL
    // predicate `rank <= -S` on the raw negative bm25 rank.
    test('translation units query maps minRelevanceScore to rank <= -score',
        () {
      final sql = FtsQueryBuilder.buildTranslationUnitsQuery(
        'cavalry',
        filter: const SearchFilter(minRelevanceScore: 2.5),
        limit: 10,
      );
      expect(sql, contains('rank <= -2.5'));
      expect(sql, isNot(contains('rank >=')));
    });

    test('translation versions query maps minRelevanceScore to rank <= -score',
        () {
      final sql = FtsQueryBuilder.buildTranslationVersionsQuery(
        'cavalry',
        filter: const SearchFilter(minRelevanceScore: 2.5),
        limit: 10,
      );
      expect(sql, contains('rank <= -2.5'));
      expect(sql, isNot(contains('rank >=')));
    });
  });

  group('FtsQueryBuilder.buildGlossaryQuery LIKE escaping', () {
    test('escapes percent sign in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        '50%',
        limit: 10,
      );
      // Must escape % and include ESCAPE clause
      expect(sql, contains(r"'%50\%%'"));
      expect(sql.toUpperCase(), contains("ESCAPE '\\'"));
    });

    test('escapes underscore in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        'foo_bar',
        limit: 10,
      );
      expect(sql, contains(r"'%foo\_bar%'"));
    });

    test('escapes backslash in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        r'path\file',
        limit: 10,
      );
      expect(sql, contains(r"'%path\\file%'"));
    });

    test('still escapes single quote', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        "O'Brien",
        limit: 10,
      );
      expect(sql, contains("'%O''Brien%'"));
    });
  });
}
