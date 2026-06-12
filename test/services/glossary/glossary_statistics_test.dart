import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/utils/glossary_statistics.dart';

GlossaryEntry _entry({
  String id = 'e',
  String sourceTerm = 'Term',
  String targetLanguageCode = 'fr',
}) {
  return GlossaryEntry(
    id: id,
    glossaryId: 'g1',
    targetLanguageCode: targetLanguageCode,
    sourceTerm: sourceTerm,
    targetTerm: 'X',
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  group('calculateStats', () {
    test('reports total and per-language-pair counts', () {
      final stats = GlossaryStatistics.calculateStats([
        _entry(id: '1', targetLanguageCode: 'fr'),
        _entry(id: '2', targetLanguageCode: 'fr'),
        _entry(id: '3', targetLanguageCode: 'de'),
      ]);

      expect(stats['totalEntries'], 3);
      expect(stats['entriesByLanguagePair'], {'fr': 2, 'de': 1});
    });

    test('handles an empty list', () {
      final stats = GlossaryStatistics.calculateStats(const []);
      expect(stats['totalEntries'], 0);
      expect(stats['entriesByLanguagePair'], <String, int>{});
    });
  });

  test('getLanguagePairs returns the distinct codes', () {
    final pairs = GlossaryStatistics.getLanguagePairs([
      _entry(id: '1', targetLanguageCode: 'fr'),
      _entry(id: '2', targetLanguageCode: 'fr'),
      _entry(id: '3', targetLanguageCode: 'de'),
    ]);
    expect(pairs, {'fr', 'de'});
  });

  test('countByLanguagePair counts per code', () {
    final counts = GlossaryStatistics.countByLanguagePair([
      _entry(id: '1', targetLanguageCode: 'fr'),
      _entry(id: '2', targetLanguageCode: 'de'),
      _entry(id: '3', targetLanguageCode: 'de'),
    ]);
    expect(counts, {'fr': 1, 'de': 2});
  });

  group('getMostCommonTerms', () {
    test('groups case-insensitively and sorts by descending count', () {
      final result = GlossaryStatistics.getMostCommonTerms([
        _entry(id: '1', sourceTerm: 'Empire'),
        _entry(id: '2', sourceTerm: 'empire'),
        _entry(id: '3', sourceTerm: 'Dwarfs'),
      ]);

      expect(result.first.key, 'empire');
      expect(result.first.value, 2);
      expect(result.last.key, 'dwarfs');
      expect(result.last.value, 1);
    });

    test('respects the limit', () {
      final entries = [
        for (var i = 0; i < 5; i++) _entry(id: '$i', sourceTerm: 'term$i'),
      ];
      final result = GlossaryStatistics.getMostCommonTerms(entries, limit: 2);
      expect(result, hasLength(2));
    });

    test('returns empty for no entries', () {
      expect(GlossaryStatistics.getMostCommonTerms(const []), isEmpty);
    });
  });
}
