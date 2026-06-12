import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';

SimilarityBreakdown _breakdown(double s) => SimilarityBreakdown(
      levenshteinScore: s,
      jaroWinklerScore: s,
      tokenScore: s,
      contextBoost: 0,
      weights: const ScoreWeights(),
    );

TmMatch _match({double score = 0.9, String? category}) => TmMatch(
      entryId: 'e1',
      sourceText: 'Hello',
      targetText: 'Bonjour',
      targetLanguageCode: 'fr',
      similarityScore: score,
      matchType: TmMatchType.fuzzy,
      breakdown: _breakdown(score),
      category: category,
      usageCount: 3,
      lastUsedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('TmMatch quality getters', () {
    test('classify by similarity score', () {
      expect(_match(score: 1.0).isExactMatch, isTrue);
      expect(_match(score: 0.96).isHighQualityMatch, isTrue);
      expect(_match(score: 0.96).isExactMatch, isFalse);
      expect(_match(score: 0.86).isGoodMatch, isTrue);
      expect(_match(score: 0.80).isGoodMatch, isFalse);
    });

    test('hasContextMatch reflects the category', () {
      expect(_match(category: 'ui').hasContextMatch, isTrue);
      expect(_match().hasContextMatch, isFalse);
    });

    test('copyWith + equality (entryId + score)', () {
      final m = _match();
      expect(m.copyWith(usageCount: 9).usageCount, 9);
      expect(m, equals(_match()));
      expect(_match(score: 0.5), isNot(equals(_match(score: 0.9))));
    });
  });

  group('SimilarityBreakdown', () {
    test('combinedScore equals the component score when weights sum to 1', () {
      expect(_breakdown(0.8).combinedScore, closeTo(0.8, 1e-9));
    });

    test('toJson emits a map', () {
      expect(_breakdown(0.5).toJson(), isA<Map<String, dynamic>>());
    });
  });

  group('ScoreWeights', () {
    test('defaults sum to 1 and are valid', () {
      const w = ScoreWeights.defaultWeights;
      expect(w.levenshteinWeight, 0.4);
      expect(w.isValid, isTrue);
    });

    test('weights that do not sum to ~1 are invalid', () {
      const w = ScoreWeights(levenshteinWeight: 0.5, jaroWinklerWeight: 0.5, tokenWeight: 0.5);
      expect(w.isValid, isFalse);
    });

    test('json round-trip', () {
      final restored = ScoreWeights.fromJson(const ScoreWeights().toJson());
      expect(restored.levenshteinWeight, 0.4);
      expect(restored.isValid, isTrue);
    });
  });
}
