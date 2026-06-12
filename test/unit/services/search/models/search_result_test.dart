import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/search/models/search_result.dart';

SearchResult _result({String id = 's1', double score = 1.5}) => SearchResult(
      id: id,
      type: SearchResultType.translationUnit,
      matchedField: 'source_text',
      highlightedText: 'hello <mark>world</mark>',
      relevanceScore: score,
      key: 'key_a',
      projectName: 'Proj',
    );

void main() {
  group('SearchResult', () {
    test('copyWith overrides only the targeted field', () {
      final r = _result();
      final updated = r.copyWith(relevanceScore: 9.0);
      expect(updated.relevanceScore, 9.0);
      expect(updated.id, r.id);
      expect(updated, isNot(equals(r)));
    });

    test('value equality and hashCode are field-based', () {
      expect(_result(), equals(_result()));
      expect(_result().hashCode, _result().hashCode);
      expect(_result(id: 'a'), isNot(equals(_result(id: 'b'))));
    });

    test('round-trips through json', () {
      final r = _result();
      final restored = SearchResult.fromJson(r.toJson());
      expect(restored.id, r.id);
      expect(restored.type, SearchResultType.translationUnit);
      expect(restored.relevanceScore, r.relevanceScore);
      expect(restored, equals(r));
    });
  });

  group('SearchFilter', () {
    test('a filter with no fields set is empty', () {
      expect(const SearchFilter().isEmpty, isTrue);
    });

    test('a filter with any field set is not empty', () {
      expect(const SearchFilter(projectIds: ['p1']).isEmpty, isFalse);
      expect(
        SearchFilter(minDate: DateTime(2026, 1, 1)).isEmpty,
        isFalse,
      );
    });

    test('copyWith overrides the targeted field', () {
      const base = SearchFilter(statuses: ['pending']);
      final updated = base.copyWith(minRelevanceScore: 0.5);
      expect(updated.minRelevanceScore, 0.5);
      expect(updated.statuses, ['pending']);
    });

    test('round-trips through json', () {
      const f = SearchFilter(
        languageCodes: ['fr', 'de'],
        types: [SearchResultType.glossaryEntry],
        minRelevanceScore: 0.25,
      );
      final restored = SearchFilter.fromJson(f.toJson());
      expect(restored.languageCodes, ['fr', 'de']);
      expect(restored.types, [SearchResultType.glossaryEntry]);
      expect(restored.minRelevanceScore, 0.25);
    });
  });
}
