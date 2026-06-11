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
    // `rank` may be followed by a deterministic tiebreaker column (`, x.id`),
    // so accept either a comma or end-of-line right after `rank [ASC]`.
    final ascendingRank = RegExp(r'ORDER\s+BY\s+rank\s*(ASC)?\s*[,\n]', caseSensitive: false);

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

  group('FtsQueryBuilder ordinary-word search (no over-zealous injection block)',
      () {
    // The MATCH value is interpolated inside a single-quoted SQL literal with
    // single quotes doubled, so injection via these words is already
    // impossible. They are ordinary English words that legitimately appear in
    // mod text, so a search for them must not be rejected.
    for (final word in ['update', 'create', 'delete', 'insert', 'union']) {
      test('accepts the ordinary search term "$word"', () {
        expect(
          () => FtsQueryBuilder.buildTranslationUnitsQuery(word, limit: 50),
          returnsNormally,
          reason: '"$word" is a normal search term, not an injection',
        );
        final sql = FtsQueryBuilder.buildTranslationUnitsQuery(word, limit: 50);
        expect(sql.toLowerCase(), contains(word));
      });
    }
  });

  group('FtsQueryBuilder date filters use Unix SECONDS (matching *_at columns)',
      () {
    // All *_at columns store Unix timestamps in SECONDS (writers use
    // `DateTime.now().millisecondsSinceEpoch ~/ 1000`). Emitting milliseconds
    // would make minDate exclude every row and maxDate an always-true no-op.
    //
    // Non-zero ms remainders (.123/.456) ensure the ms and seconds values
    // differ in more than trailing zeros, so the isNot(contains(ms))
    // assertions below are meaningful.
    final minDate = DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true);
    final maxDate = DateTime.fromMillisecondsSinceEpoch(1800000000456, isUtc: true);
    final filter = SearchFilter(minDate: minDate, maxDate: maxDate);

    test('translation units query compares created_at in seconds', () {
      final sql = FtsQueryBuilder.buildTranslationUnitsQuery(
        'cavalry',
        filter: filter,
        limit: 10,
      );
      expect(sql, matches(RegExp(r'tu\.created_at >= 1700000000(?!\d)')));
      expect(sql, matches(RegExp(r'tu\.created_at <= 1800000000(?!\d)')));
      expect(sql, isNot(contains('1700000000123')));
      expect(sql, isNot(contains('1800000000456')));
    });

    test('translation versions query compares created_at in seconds', () {
      final sql = FtsQueryBuilder.buildTranslationVersionsQuery(
        'cavalry',
        filter: filter,
        limit: 10,
      );
      expect(sql, matches(RegExp(r'tv\.created_at >= 1700000000(?!\d)')));
      expect(sql, matches(RegExp(r'tv\.created_at <= 1800000000(?!\d)')));
      expect(sql, isNot(contains('1700000000123')));
      expect(sql, isNot(contains('1800000000456')));
    });
  });

  group('FtsQueryBuilder FTS5 column filter is parenthesized', () {
    // Per the FTS5 grammar, `{col} : term1 term2` scopes ONLY term1 to the
    // column; term2 matches ALL indexed columns (including validation_issues),
    // producing false positives. The query must be parenthesized:
    // `{translated_text} : (term1 term2)`.
    test('versions query scopes a multi-term query entirely to translated_text',
        () {
      final sql = FtsQueryBuilder.buildTranslationVersionsQuery(
        'heavy cavalry',
        limit: 10,
      );
      expect(sql, contains("MATCH '{translated_text} : (heavy cavalry)'"));
    });

    test('versions query scopes a single-term query to translated_text', () {
      final sql = FtsQueryBuilder.buildTranslationVersionsQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, contains("MATCH '{translated_text} : (cavalry)'"));
    });
  });

  group('FtsQueryBuilder ORDER BY has a deterministic tiebreaker', () {
    // bm25 rank ties are common for short repeated game strings, and the
    // pagination layer issues separate SQL queries per page (LIMIT/OFFSET).
    // Without a unique tiebreaker, tied rows have unspecified order across
    // queries, so page boundaries can duplicate or drop rows.
    test('translation units query breaks rank ties on tu.id', () {
      final sql = FtsQueryBuilder.buildTranslationUnitsQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, matches(RegExp(r'ORDER\s+BY\s+rank,\s*tu\.id')));
    });

    test('translation versions query breaks rank ties on tv.id', () {
      final sql = FtsQueryBuilder.buildTranslationVersionsQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, matches(RegExp(r'ORDER\s+BY\s+rank,\s*tv\.id')));
    });

    test('translation memory query breaks rank ties on tm.id', () {
      final sql = FtsQueryBuilder.buildTranslationMemoryQuery(
        'cavalry',
        limit: 10,
      );
      expect(sql, matches(RegExp(r'ORDER\s+BY\s+rank,\s*tm\.id')));
    });

    test('glossary query breaks term ties on id (also paginated)', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        'cavalry',
        limit: 10,
        offset: 10,
      );
      expect(sql, matches(RegExp(r'ORDER\s+BY\s+term\s+ASC,\s*id')));
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
