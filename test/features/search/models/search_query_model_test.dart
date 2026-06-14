import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/search/models/search_query_model.dart';
import 'package:twmt/services/search/models/search_result.dart';

/// Round-trips a [toJson] map through real JSON encoding so that nested
/// model objects (json_serializable without explicitToJson) become maps.
Map<String, dynamic> _jsonRoundTrip(Map<String, dynamic> map) =>
    jsonDecode(jsonEncode(map)) as Map<String, dynamic>;

void main() {
  group('SearchScope', () {
    test('displayName covers every value', () {
      expect(SearchScope.source.displayName, 'Source Text');
      expect(SearchScope.target.displayName, 'Target Text');
      expect(SearchScope.both.displayName, 'Source & Target');
      expect(SearchScope.key.displayName, 'Translation Key');
      expect(SearchScope.all.displayName, 'All Fields');
    });
  });

  group('SearchOperator', () {
    test('displayName covers every value', () {
      expect(SearchOperator.and.displayName, 'AND (all terms)');
      expect(SearchOperator.or.displayName, 'OR (any term)');
      expect(SearchOperator.not.displayName, 'NOT (exclude)');
    });

    test('ftsOperator covers every value', () {
      expect(SearchOperator.and.ftsOperator, 'AND');
      expect(SearchOperator.or.ftsOperator, 'OR');
      expect(SearchOperator.not.ftsOperator, 'NOT');
    });
  });

  group('SearchOptions', () {
    test('default constructor uses defaults', () {
      const options = SearchOptions();
      expect(options.caseSensitive, false);
      expect(options.wholeWord, false);
      expect(options.phraseSearch, false);
      expect(options.prefixSearch, false);
      expect(options.includeObsolete, false);
      expect(options.resultsPerPage, 50);
    });

    test('defaults() factory equals default constructor', () {
      expect(SearchOptions.defaults().toJson(),
          const SearchOptions().toJson());
    });

    test('explicit constructor sets all fields', () {
      const options = SearchOptions(
        caseSensitive: true,
        wholeWord: true,
        phraseSearch: true,
        prefixSearch: true,
        includeObsolete: true,
        resultsPerPage: 25,
      );
      expect(options.caseSensitive, true);
      expect(options.wholeWord, true);
      expect(options.phraseSearch, true);
      expect(options.prefixSearch, true);
      expect(options.includeObsolete, true);
      expect(options.resultsPerPage, 25);
    });

    test('toJson/fromJson round-trip with defaults', () {
      const options = SearchOptions();
      final restored = SearchOptions.fromJson(options.toJson());
      expect(restored.caseSensitive, options.caseSensitive);
      expect(restored.wholeWord, options.wholeWord);
      expect(restored.phraseSearch, options.phraseSearch);
      expect(restored.prefixSearch, options.prefixSearch);
      expect(restored.includeObsolete, options.includeObsolete);
      expect(restored.resultsPerPage, options.resultsPerPage);
    });

    test('toJson/fromJson round-trip with non-defaults', () {
      const options = SearchOptions(
        caseSensitive: true,
        wholeWord: true,
        phraseSearch: true,
        prefixSearch: true,
        includeObsolete: true,
        resultsPerPage: 10,
      );
      final restored = SearchOptions.fromJson(options.toJson());
      expect(restored.toJson(), options.toJson());
    });

    test('copyWith changes each field individually', () {
      const base = SearchOptions();
      expect(base.copyWith(caseSensitive: true).caseSensitive, true);
      expect(base.copyWith(wholeWord: true).wholeWord, true);
      expect(base.copyWith(phraseSearch: true).phraseSearch, true);
      expect(base.copyWith(prefixSearch: true).prefixSearch, true);
      expect(base.copyWith(includeObsolete: true).includeObsolete, true);
      expect(base.copyWith(resultsPerPage: 99).resultsPerPage, 99);
    });

    test('copyWith with no args preserves all fields', () {
      const base = SearchOptions(
        caseSensitive: true,
        wholeWord: true,
        phraseSearch: true,
        prefixSearch: true,
        includeObsolete: true,
        resultsPerPage: 7,
      );
      final copy = base.copyWith();
      expect(copy.toJson(), base.toJson());
    });
  });

  group('SearchQueryModel', () {
    SearchFilter buildFilter() => const SearchFilter(
          projectIds: ['p1', 'p2'],
          languageCodes: ['en'],
          statuses: ['translated', 'reviewed'],
        );

    test('explicit constructor sets all fields', () {
      final filter = buildFilter();
      const options = SearchOptions(resultsPerPage: 20);
      final query = SearchQueryModel(
        text: 'hello',
        scope: SearchScope.source,
        operator: SearchOperator.or,
        filter: filter,
        options: options,
      );
      expect(query.text, 'hello');
      expect(query.scope, SearchScope.source);
      expect(query.operator, SearchOperator.or);
      expect(query.filter, filter);
      expect(query.options, options);
    });

    test('empty() factory has expected defaults', () {
      final query = SearchQueryModel.empty();
      expect(query.text, '');
      expect(query.scope, SearchScope.all);
      expect(query.operator, SearchOperator.and);
      expect(query.filter, isNull);
      expect(query.options.resultsPerPage, 50);
    });

    test('toJson/fromJson round-trip with null filter', () {
      final query = SearchQueryModel.empty();
      final restored = SearchQueryModel.fromJson(_jsonRoundTrip(query.toJson()));
      expect(restored.text, query.text);
      expect(restored.scope, query.scope);
      expect(restored.operator, query.operator);
      expect(restored.filter, isNull);
      expect(restored.options.resultsPerPage, query.options.resultsPerPage);
    });

    test('toJson/fromJson round-trip with filter set', () {
      final query = SearchQueryModel(
        text: 'world',
        scope: SearchScope.both,
        operator: SearchOperator.not,
        filter: buildFilter(),
        options: const SearchOptions(caseSensitive: true),
      );
      final restored = SearchQueryModel.fromJson(_jsonRoundTrip(query.toJson()));
      expect(restored.text, query.text);
      expect(restored.scope, query.scope);
      expect(restored.operator, query.operator);
      expect(restored.options.caseSensitive, true);
      // SearchFilter uses identity equality on its List fields, so a JSON
      // round-trip yields equal contents but a non-equal object. Compare the
      // re-serialized JSON to confirm the data survives the round-trip.
      expect(jsonEncode(restored.filter!.toJson()),
          jsonEncode(query.filter!.toJson()));
    });

    test('copyWith changes each field individually', () {
      final base = SearchQueryModel.empty();
      expect(base.copyWith(text: 'abc').text, 'abc');
      expect(base.copyWith(scope: SearchScope.key).scope, SearchScope.key);
      expect(base.copyWith(operator: SearchOperator.or).operator,
          SearchOperator.or);
      final filter = buildFilter();
      expect(base.copyWith(filter: filter).filter, filter);
      const options = SearchOptions(resultsPerPage: 5);
      expect(base.copyWith(options: options).options, options);
    });

    test('copyWith with no args preserves all fields', () {
      final base = SearchQueryModel(
        text: 'x',
        scope: SearchScope.target,
        operator: SearchOperator.or,
        filter: buildFilter(),
        options: const SearchOptions(wholeWord: true),
      );
      expect(base.copyWith(), base);
    });

    group('isValid', () {
      test('false for empty text', () {
        expect(SearchQueryModel.empty().isValid, false);
      });

      test('false for whitespace-only text', () {
        expect(SearchQueryModel.empty().copyWith(text: '   ').isValid, false);
      });

      test('false for single character', () {
        expect(SearchQueryModel.empty().copyWith(text: 'a').isValid, false);
      });

      test('true for two or more characters', () {
        expect(SearchQueryModel.empty().copyWith(text: 'ab').isValid, true);
      });
    });

    group('summary', () {
      test('text only, scope all, no filter', () {
        final query = SearchQueryModel.empty().copyWith(text: 'foo');
        expect(query.summary, '"foo"');
      });

      test('includes scope when not all', () {
        final query = SearchQueryModel.empty().copyWith(
          text: 'foo',
          scope: SearchScope.source,
        );
        expect(query.summary, '"foo" in Source Text');
      });

      test('empty filter does not add filter parts', () {
        final query = SearchQueryModel.empty().copyWith(
          text: 'foo',
          filter: const SearchFilter(),
        );
        expect(query.summary, '"foo"');
      });

      test('includes project, language and status counts', () {
        final query = SearchQueryModel(
          text: 'foo',
          scope: SearchScope.all,
          operator: SearchOperator.and,
          filter: const SearchFilter(
            projectIds: ['p1', 'p2'],
            languageCodes: ['en', 'fr', 'de'],
            statuses: ['translated', 'reviewed'],
          ),
          options: SearchOptions.defaults(),
        );
        expect(
          query.summary,
          '"foo" (2 project(s), 3 language(s), status=translated, reviewed)',
        );
      });

      test('filter with non-empty list of one type', () {
        final query = SearchQueryModel(
          text: 'bar',
          scope: SearchScope.all,
          operator: SearchOperator.and,
          filter: const SearchFilter(projectIds: ['only']),
          options: SearchOptions.defaults(),
        );
        expect(query.summary, '"bar" (1 project(s))');
      });

      test('filter not empty but all relevant lists empty/null adds no parens',
          () {
        // filter has minDate set (isEmpty == false) but no project/lang/status
        final query = SearchQueryModel(
          text: 'baz',
          scope: SearchScope.all,
          operator: SearchOperator.and,
          filter: SearchFilter(minDate: DateTime(2020, 1, 1)),
          options: SearchOptions.defaults(),
        );
        expect(query.summary, '"baz"');
      });

      test('handles empty (not null) project/language/status lists', () {
        final query = SearchQueryModel(
          text: 'qux',
          scope: SearchScope.all,
          operator: SearchOperator.and,
          filter: const SearchFilter(
            projectIds: [],
            languageCodes: [],
            statuses: [],
            minDate: null,
            fileNames: ['f'],
          ),
          options: SearchOptions.defaults(),
        );
        // fileNames makes filter non-empty, but the summary only looks at
        // project/language/status which are all empty -> no parens added.
        expect(query.summary, '"qux"');
      });

      test('combines scope and filter', () {
        final query = SearchQueryModel(
          text: 'combo',
          scope: SearchScope.key,
          operator: SearchOperator.and,
          filter: const SearchFilter(statuses: ['draft']),
          options: SearchOptions.defaults(),
        );
        expect(query.summary,
            '"combo" in Translation Key (status=draft)');
      });
    });

    group('equality and hashCode', () {
      test('identical instance equals itself', () {
        final query = SearchQueryModel.empty();
        expect(query == query, true);
      });

      test('equal field values are equal with same hashCode', () {
        final a = SearchQueryModel(
          text: 't',
          scope: SearchScope.source,
          operator: SearchOperator.and,
          filter: buildFilter(),
          options: const SearchOptions(),
        );
        final b = SearchQueryModel(
          text: 't',
          scope: SearchScope.source,
          operator: SearchOperator.and,
          filter: buildFilter(),
          options: const SearchOptions(),
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('differing text is not equal', () {
        final a = SearchQueryModel.empty();
        final b = a.copyWith(text: 'other');
        expect(a == b, false);
      });

      test('differing scope is not equal', () {
        final a = SearchQueryModel.empty();
        final b = a.copyWith(scope: SearchScope.source);
        expect(a == b, false);
      });

      test('not equal to a different type', () {
        // ignore: unrelated_type_equality_checks
        expect(SearchQueryModel.empty() == Object(), false);
      });
    });

    test('toString includes core fields', () {
      final query = SearchQueryModel(
        text: 'hi',
        scope: SearchScope.both,
        operator: SearchOperator.or,
        options: SearchOptions.defaults(),
      );
      expect(
        query.toString(),
        'SearchQueryModel(text: hi, scope: SearchScope.both, '
        'operator: SearchOperator.or)',
      );
    });
  });

  group('SearchResultsModel', () {
    SearchResult buildResult() => const SearchResult(
          id: 'r1',
          type: SearchResultType.translationUnit,
          matchedField: 'source_text',
          highlightedText: '<mark>hi</mark>',
          relevanceScore: 1.5,
        );

    test('explicit constructor sets all fields', () {
      final query = SearchQueryModel.empty();
      final result = buildResult();
      final model = SearchResultsModel(
        results: [result],
        totalCount: 234,
        currentPage: 2,
        pageSize: 50,
        query: query,
      );
      expect(model.results, [result]);
      expect(model.totalCount, 234);
      expect(model.currentPage, 2);
      expect(model.pageSize, 50);
      expect(model.query, query);
    });

    test('empty() factory has expected defaults', () {
      final model = SearchResultsModel.empty();
      expect(model.results, isEmpty);
      expect(model.totalCount, 0);
      expect(model.currentPage, 1);
      expect(model.pageSize, 50);
      expect(model.query.text, '');
    });

    test('toJson/fromJson round-trip empty model', () {
      final model = SearchResultsModel.empty();
      final restored =
          SearchResultsModel.fromJson(_jsonRoundTrip(model.toJson()));
      expect(restored.results, isEmpty);
      expect(restored.totalCount, 0);
      expect(restored.currentPage, 1);
      expect(restored.pageSize, 50);
    });

    test('toJson/fromJson round-trip with results', () {
      final model = SearchResultsModel(
        results: [buildResult()],
        totalCount: 1,
        currentPage: 1,
        pageSize: 10,
        query: SearchQueryModel.empty(),
      );
      final restored =
          SearchResultsModel.fromJson(_jsonRoundTrip(model.toJson()));
      expect(restored.results.length, 1);
      expect(restored.results.first.id, 'r1');
      expect(restored.totalCount, 1);
      expect(restored.pageSize, 10);
    });

    group('totalPages', () {
      test('exact multiple', () {
        final model = SearchResultsModel.empty()
            .copyWith(totalCount: 100, pageSize: 50);
        expect(model.totalPages, 2);
      });

      test('rounds up partial page', () {
        final model = SearchResultsModel.empty()
            .copyWith(totalCount: 234, pageSize: 50);
        expect(model.totalPages, 5);
      });

      test('zero results means zero pages', () {
        final model =
            SearchResultsModel.empty().copyWith(totalCount: 0, pageSize: 50);
        expect(model.totalPages, 0);
      });
    });

    group('hasPreviousPage', () {
      test('false on first page', () {
        expect(SearchResultsModel.empty().copyWith(currentPage: 1)
            .hasPreviousPage, false);
      });

      test('true after first page', () {
        expect(SearchResultsModel.empty().copyWith(currentPage: 2)
            .hasPreviousPage, true);
      });
    });

    group('hasNextPage', () {
      test('true when more pages remain', () {
        final model = SearchResultsModel.empty()
            .copyWith(totalCount: 234, pageSize: 50, currentPage: 1);
        expect(model.hasNextPage, true);
      });

      test('false on last page', () {
        final model = SearchResultsModel.empty()
            .copyWith(totalCount: 234, pageSize: 50, currentPage: 5);
        expect(model.hasNextPage, false);
      });
    });

    group('rangeText', () {
      test('zero results', () {
        final model = SearchResultsModel.empty().copyWith(totalCount: 0);
        expect(model.rangeText, '0 results');
      });

      test('first page range', () {
        final model = SearchResultsModel.empty()
            .copyWith(totalCount: 234, pageSize: 50, currentPage: 1);
        expect(model.rangeText, '1-50 of 234');
      });

      test('last partial page clamps end to total', () {
        final model = SearchResultsModel.empty()
            .copyWith(totalCount: 234, pageSize: 50, currentPage: 5);
        expect(model.rangeText, '201-234 of 234');
      });
    });

    test('copyWith changes each field individually', () {
      final base = SearchResultsModel.empty();
      final result = buildResult();
      expect(base.copyWith(results: [result]).results, [result]);
      expect(base.copyWith(totalCount: 9).totalCount, 9);
      expect(base.copyWith(currentPage: 3).currentPage, 3);
      expect(base.copyWith(pageSize: 25).pageSize, 25);
      final query = SearchQueryModel.empty().copyWith(text: 'qq');
      expect(base.copyWith(query: query).query, query);
    });

    test('copyWith with no args preserves all fields', () {
      final base = SearchResultsModel(
        results: [buildResult()],
        totalCount: 5,
        currentPage: 2,
        pageSize: 20,
        query: SearchQueryModel.empty().copyWith(text: 'z'),
      );
      final copy = base.copyWith();
      expect(copy.results, base.results);
      expect(copy.totalCount, base.totalCount);
      expect(copy.currentPage, base.currentPage);
      expect(copy.pageSize, base.pageSize);
      expect(copy.query, base.query);
    });
  });
}
