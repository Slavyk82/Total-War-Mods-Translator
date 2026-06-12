import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/search/models/search_result.dart';
import 'package:twmt/services/search/utils/query_builder.dart';

void main() {
  group('buildFtsQuery', () {
    test('empty query yields empty string', () {
      expect(FtsQueryBuilder.buildFtsQuery(''), '');
    });

    test('a single word is returned escaped', () {
      expect(FtsQueryBuilder.buildFtsQuery('cavalry'), 'cavalry');
    });

    test('multiple plain words are joined with AND', () {
      expect(FtsQueryBuilder.buildFtsQuery('cavalry unit'), 'cavalry AND unit');
    });

    test('a query already using operators is sanitized, not rewritten', () {
      expect(FtsQueryBuilder.buildFtsQuery('cavalry OR infantry'),
          'cavalry OR infantry');
      // dangerous SQL bits are stripped from an operator query
      expect(FtsQueryBuilder.buildFtsQuery('cavalry AND unit; DROP'),
          isNot(contains(';')));
    });
  });

  group('buildFilterClause', () {
    test('a null or empty filter yields an empty clause', () {
      expect(FtsQueryBuilder.buildFilterClause(null), '');
      expect(FtsQueryBuilder.buildFilterClause(const SearchFilter()), '');
    });

    test('combines IN clauses and date bounds with AND', () {
      final clause = FtsQueryBuilder.buildFilterClause(
        SearchFilter(
          projectIds: const ['p1'],
          statuses: const ['pending'],
          minDate: DateTime.fromMillisecondsSinceEpoch(2000 * 1000),
        ),
      );
      expect(clause, contains("t.project_id IN ('p1')"));
      expect(clause, contains("t.status IN ('pending')"));
      expect(clause, contains('t.created_at >= 2000'));
      expect(clause, contains(' AND '));
    });

    test('escapes single quotes in filter values', () {
      final clause = FtsQueryBuilder.buildFilterClause(
        const SearchFilter(projectIds: ["o'brien"]),
      );
      expect(clause, contains("o''brien"));
    });

    test('translates a positive relevance score into a negative rank bound', () {
      final clause = FtsQueryBuilder.buildFilterClause(
        const SearchFilter(minRelevanceScore: 2.5),
      );
      expect(clause, contains('rank <= -2.5'));
    });
  });

  group('clauses', () {
    test('buildOrderClause defaults to ascending rank', () {
      expect(FtsQueryBuilder.buildOrderClause(), 'rank ASC');
      expect(FtsQueryBuilder.buildOrderClause(orderBy: 'created_at', ascending: false),
          'created_at DESC');
    });

    test('buildLimitClause clamps and adds OFFSET when non-zero', () {
      expect(FtsQueryBuilder.buildLimitClause(limit: 50), 'LIMIT 50');
      expect(FtsQueryBuilder.buildLimitClause(limit: 5000), 'LIMIT 1000'); // clamped
      expect(FtsQueryBuilder.buildLimitClause(limit: 20, offset: 40),
          'LIMIT 20 OFFSET 40');
    });

    test('buildSnippet emits the FTS5 snippet() call', () {
      final s = FtsQueryBuilder.buildSnippet(tableName: 'fts', column: 1);
      expect(s, startsWith('snippet(fts, 1, '));
      expect(s, contains('<mark>'));
    });
  });

  group('escaping + validation', () {
    test('escapeFtsText doubles double-quotes', () {
      expect(FtsQueryBuilder.escapeFtsText('say "hi"'), 'say ""hi""');
    });

    test('validateFtsQuery throws on empty / unbalanced / bad operators', () {
      expect(() => FtsQueryBuilder.validateFtsQuery('  '), throwsArgumentError);
      expect(() => FtsQueryBuilder.validateFtsQuery('a "b'), throwsArgumentError);
      expect(() => FtsQueryBuilder.validateFtsQuery('(a OR b'), throwsArgumentError);
      expect(() => FtsQueryBuilder.validateFtsQuery('a AND AND b'),
          throwsArgumentError);
      expect(() => FtsQueryBuilder.validateFtsQuery('OR a'), throwsArgumentError);
    });

    test('validateFtsQuery returns true for a well-formed query', () {
      expect(FtsQueryBuilder.validateFtsQuery('cavalry AND "unit type"'), isTrue);
    });

    test('buildRegexPattern validates and escapes', () {
      expect(FtsQueryBuilder.buildRegexPattern("a'b"), "a''b");
      expect(() => FtsQueryBuilder.buildRegexPattern('[unclosed'),
          throwsArgumentError);
    });
  });

  group('convertOperators', () {
    test('maps +, | and - to AND, OR and NOT', () {
      expect(FtsQueryBuilder.convertOperators('cavalry + unit'),
          'cavalry AND unit');
      expect(FtsQueryBuilder.convertOperators('cavalry | infantry'),
          'cavalry OR infantry');
      expect(FtsQueryBuilder.convertOperators('cavalry -horse'),
          contains('NOT horse'));
    });
  });
}
