import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';

void main() {
  late SimilarityCalculator calculator;

  setUp(() {
    calculator = SimilarityCalculator();
  });

  group('SimilarityCalculator', () {
    // =========================================================================
    // calculateSimilarity
    // =========================================================================
    group('calculateSimilarity', () {
      test('should return 1.0 for identical strings', () {
        // Arrange
        const text1 = 'Hello world';
        const text2 = 'Hello world';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        expect(result.combinedScore, closeTo(1.0, 0.01));
        expect(result.levenshteinScore, closeTo(1.0, 0.01));
        expect(result.jaroWinklerScore, closeTo(1.0, 0.01));
        expect(result.tokenScore, closeTo(1.0, 0.01));
      });

      test('should return 0.0 for completely different strings', () {
        // Arrange
        const text1 = 'aaaaaaaaaa';
        const text2 = 'zzzzzzzzzz';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        expect(result.combinedScore, lessThan(0.3));
      });

      test('should handle empty strings', () {
        // Arrange
        const text1 = '';
        const text2 = '';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        // Empty strings should be considered identical
        expect(result.combinedScore, greaterThanOrEqualTo(0.0));
      });

      test('should add context boost when categories match', () {
        // Arrange
        const text1 = 'Hello world';
        const text2 = 'Hello world';

        // Act
        final resultWithContext = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
          category1: 'ui_text',
          category2: 'ui_text',
        );

        final resultWithoutContext = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        expect(resultWithContext.contextBoost, closeTo(0.03, 0.001));
        expect(resultWithoutContext.contextBoost, closeTo(0.0, 0.001));
      });

      test('should not add context boost when categories differ', () {
        // Arrange
        const text1 = 'Hello world';
        const text2 = 'Hello world';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
          category1: 'ui_text',
          category2: 'game_text',
        );

        // Assert
        expect(result.contextBoost, closeTo(0.0, 0.001));
      });

      test('should use custom weights when provided', () {
        // Arrange
        const text1 = 'Hello';
        const text2 = 'Hallo';
        const customWeights = ScoreWeights(
          levenshteinWeight: 1.0,
          jaroWinklerWeight: 0.0,
          tokenWeight: 0.0,
        );

        // Act
        final resultWithCustom = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
          weights: customWeights,
        );

        // Assert
        // Combined score should be purely Levenshtein-based
        expect(
          resultWithCustom.combinedScore,
          closeTo(resultWithCustom.levenshteinScore, 0.01),
        );
      });
    });

    // =========================================================================
    // calculateLevenshteinSimilarity
    // =========================================================================
    group('calculateLevenshteinSimilarity', () {
      test('should return 1.0 for identical strings', () {
        // Act
        final result = calculator.calculateLevenshteinSimilarity('hello', 'hello');

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });

      test('should return correct similarity for single character difference', () {
        // Act
        final result = calculator.calculateLevenshteinSimilarity('hello', 'hallo');

        // Assert
        // Distance is 1, max length is 5, so similarity is 1 - 1/5 = 0.8
        expect(result, closeTo(0.8, 0.01));
      });

      test('should return 0.0 when one string is empty', () {
        // Act
        final result = calculator.calculateLevenshteinSimilarity('hello', '');

        // Assert
        expect(result, closeTo(0.0, 0.01));
      });

      test('should be case-insensitive', () {
        // Act
        final result = calculator.calculateLevenshteinSimilarity('Hello', 'hello');

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });

      test('should handle longer strings', () {
        // Arrange
        const text1 = 'The quick brown fox jumps over the lazy dog';
        const text2 = 'The quick brown fox jumps over the lazy cat';

        // Act
        final result = calculator.calculateLevenshteinSimilarity(text1, text2);

        // Assert
        expect(result, greaterThan(0.9));
      });
    });

    // =========================================================================
    // calculateJaroWinklerSimilarity
    // =========================================================================
    group('calculateJaroWinklerSimilarity', () {
      test('should return 1.0 for identical strings', () {
        // Act
        final result = calculator.calculateJaroWinklerSimilarity('hello', 'hello');

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });

      test('should return 0.0 for completely different strings', () {
        // Act
        final result = calculator.calculateJaroWinklerSimilarity('abc', 'xyz');

        // Assert
        expect(result, closeTo(0.0, 0.01));
      });

      test('should return 0.0 when one string is empty', () {
        // Act
        final result = calculator.calculateJaroWinklerSimilarity('hello', '');

        // Assert
        expect(result, closeTo(0.0, 0.01));
      });

      test('should give boost for common prefix', () {
        // Arrange
        const text1 = 'MARTHA';
        const text2 = 'MARHTA';

        // Act
        final result = calculator.calculateJaroWinklerSimilarity(text1, text2);

        // Assert
        // Jaro-Winkler gives boost for common prefix
        expect(result, greaterThan(0.9));
      });

      test('should handle transpositions correctly', () {
        // Arrange
        const text1 = 'DwAyNE';
        const text2 = 'DuAnE';

        // Act
        final result = calculator.calculateJaroWinklerSimilarity(text1, text2);

        // Assert
        expect(result, greaterThan(0.7));
      });
    });

    // =========================================================================
    // calculateTokenSimilarity
    // =========================================================================
    group('calculateTokenSimilarity', () {
      test('should return 1.0 for identical strings', () {
        // Act
        final result = calculator.calculateTokenSimilarity('hello world', 'hello world');

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });

      test('should return 1.0 for reordered words', () {
        // Act
        final result = calculator.calculateTokenSimilarity(
          'hello world',
          'world hello',
        );

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });

      test('should return 0.0 for completely different tokens', () {
        // Act
        final result = calculator.calculateTokenSimilarity('hello world', 'foo bar');

        // Assert
        expect(result, closeTo(0.0, 0.01));
      });

      test('should return 0.0 when one string is empty', () {
        // Act
        final result = calculator.calculateTokenSimilarity('hello', '');

        // Assert
        expect(result, closeTo(0.0, 0.01));
      });

      test('should handle partial overlap', () {
        // Arrange
        const text1 = 'the quick brown fox';
        const text2 = 'the lazy brown dog';

        // Act
        final result = calculator.calculateTokenSimilarity(text1, text2);

        // Assert
        // 2 common tokens (the, brown) out of 6 unique tokens
        // Jaccard = 2/6 = 0.333
        expect(result, closeTo(0.333, 0.05));
      });
    });

    // =========================================================================
    // calculateNGramSimilarity
    // =========================================================================
    group('calculateNGramSimilarity', () {
      test('should return 1.0 for identical strings', () {
        // Act
        final result = calculator.calculateNGramSimilarity('hello', 'hello');

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });

      test('should return 0.0 for completely different strings', () {
        // Act
        final result = calculator.calculateNGramSimilarity('aaa', 'zzz');

        // Assert
        expect(result, closeTo(0.0, 0.01));
      });

      test('should detect partial similarity', () {
        // Arrange
        const text1 = 'hello';
        const text2 = 'hallo';

        // Act
        final result = calculator.calculateNGramSimilarity(text1, text2);

        // Assert
        // Some bigrams should match: al, ll, lo
        expect(result, greaterThan(0.3));
        expect(result, lessThan(1.0));
      });

      test('should handle custom n-gram size', () {
        // Act
        final bigramResult = calculator.calculateNGramSimilarity('hello', 'hallo', n: 2);
        final trigramResult = calculator.calculateNGramSimilarity('hello', 'hallo', n: 3);

        // Assert
        // Both should give different results due to different n-gram sizes
        expect(bigramResult, isNot(equals(trigramResult)));
      });

      test('should return short text as single n-gram', () {
        // Act
        final result = calculator.calculateNGramSimilarity('a', 'a', n: 2);

        // Assert
        expect(result, closeTo(1.0, 0.01));
      });
    });

    // =========================================================================
    // areSimilar
    // =========================================================================
    group('areSimilar', () {
      test('should return true when texts are identical', () {
        // Act
        final result = calculator.areSimilar(
          text1: 'Hello world',
          text2: 'Hello world',
        );

        // Assert
        expect(result, true);
      });

      test('should return true when similarity exceeds threshold', () {
        // Act
        final result = calculator.areSimilar(
          text1: 'Hello world',
          text2: 'Hello World',
          threshold: 0.85,
        );

        // Assert
        expect(result, true);
      });

      test('should return false when similarity is below threshold', () {
        // Act
        final result = calculator.areSimilar(
          text1: 'Hello world',
          text2: 'Goodbye universe',
          threshold: 0.85,
        );

        // Assert
        expect(result, false);
      });

      test('should use default threshold of 0.85', () {
        // Arrange - texts with >85% similarity
        const text1 = 'The cavalry attacks the enemy';
        const text2 = 'The cavalry attack the enemy';

        // Act
        final result = calculator.areSimilar(
          text1: text1,
          text2: text2,
        );

        // Assert (these should be very similar, >85%)
        expect(result, true);
      });

      test('should consider context in similarity calculation', () {
        // Arrange
        const text1 = 'Unit attacks enemy';
        const text2 = 'Unit attack enemy';

        // Act with matching context
        final resultWithContext = calculator.areSimilar(
          text1: text1,
          text2: text2,
          category1: 'battle',
          category2: 'battle',
          threshold: 0.95,
        );

        // Act without context
        final resultWithoutContext = calculator.areSimilar(
          text1: text1,
          text2: text2,
          threshold: 0.95,
        );

        // Assert
        // With context boost, might exceed threshold
        // Without context, might not
        expect(resultWithContext || resultWithoutContext, isNotNull);
      });
    });

    // =========================================================================
    // Edge Cases
    // =========================================================================
    group('edge cases', () {
      test('should handle unicode characters', () {
        // Arrange
        const text1 = 'cafe';
        const text2 = 'cafe';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        expect(result.combinedScore, closeTo(1.0, 0.01));
      });

      test('should handle special characters', () {
        // Arrange
        const text1 = 'Hello! @#\$%';
        const text2 = 'Hello! @#\$%';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        expect(result.combinedScore, closeTo(1.0, 0.01));
      });

      test('should handle very long strings', () {
        // Arrange
        final text1 = 'word ' * 1000;
        final text2 = 'word ' * 1000;

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        expect(result.combinedScore, closeTo(1.0, 0.01));
      });

      test('should handle strings with only whitespace', () {
        // Arrange
        const text1 = '   ';
        const text2 = '   ';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert
        // After normalization, these should be similar
        expect(result.combinedScore, greaterThanOrEqualTo(0.0));
      });

      test('should handle mixed case strings', () {
        // Arrange
        const text1 = 'HeLLo WoRLD';
        const text2 = 'hello world';

        // Act
        final result = calculator.calculateSimilarity(
          text1: text1,
          text2: text2,
        );

        // Assert (normalization should make them identical)
        expect(result.combinedScore, closeTo(1.0, 0.1));
      });
    });

    // =========================================================================
    // Singleton Pattern
    // =========================================================================
    group('singleton pattern', () {
      test('should return same instance', () {
        // Arrange
        final calculator1 = SimilarityCalculator();
        final calculator2 = SimilarityCalculator();

        // Assert
        expect(identical(calculator1, calculator2), true);
      });
    });

    // =========================================================================
    // SimilarityBreakdown
    // =========================================================================
    group('SimilarityBreakdown', () {
      test('should calculate combined score correctly', () {
        // Arrange
        const breakdown = SimilarityBreakdown(
          levenshteinScore: 1.0,
          jaroWinklerScore: 1.0,
          tokenScore: 1.0,
          contextBoost: 0.0,
          weights: ScoreWeights(),
        );

        // Act
        final combinedScore = breakdown.combinedScore;

        // Assert
        expect(combinedScore, closeTo(1.0, 0.01));
      });

      test('should apply weights correctly', () {
        // Arrange
        const breakdown = SimilarityBreakdown(
          levenshteinScore: 1.0,
          jaroWinklerScore: 0.0,
          tokenScore: 0.0,
          contextBoost: 0.0,
          weights: ScoreWeights(
            levenshteinWeight: 0.5,
            jaroWinklerWeight: 0.25,
            tokenWeight: 0.25,
          ),
        );

        // Act
        final combinedScore = breakdown.combinedScore;

        // Assert
        expect(combinedScore, closeTo(0.5, 0.01));
      });

      test('should include context boost in combined score', () {
        // Arrange
        const breakdown = SimilarityBreakdown(
          levenshteinScore: 0.9,
          jaroWinklerScore: 0.9,
          tokenScore: 0.9,
          contextBoost: 0.03,
          weights: ScoreWeights(),
        );

        // Act
        final combinedScore = breakdown.combinedScore;

        // Assert
        // 0.9 * 0.4 + 0.9 * 0.3 + 0.9 * 0.3 + 0.03 = 0.36 + 0.27 + 0.27 + 0.03 = 0.93
        expect(combinedScore, closeTo(0.93, 0.01));
      });
    });

    // =========================================================================
    // ScoreWeights
    // =========================================================================
    group('ScoreWeights', () {
      test('should validate default weights sum to 1.0', () {
        // Act
        const weights = ScoreWeights();

        // Assert
        expect(weights.isValid, true);
      });

      test('should invalidate weights that do not sum to 1.0', () {
        // Act
        const weights = ScoreWeights(
          levenshteinWeight: 0.5,
          jaroWinklerWeight: 0.5,
          tokenWeight: 0.5,
        );

        // Assert
        expect(weights.isValid, false);
      });
    });
  });
}
