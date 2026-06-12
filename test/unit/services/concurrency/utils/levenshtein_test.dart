import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/concurrency/utils/levenshtein.dart';

/// Unit tests for [LevenshteinDistance].
///
/// This is a pure (no DB, no setup) facade of static methods that delegate to
/// [StringSimilarity]. The tests assert concrete delegated values so a
/// regression in either the facade or the underlying implementation is caught.
///
/// Note: the underlying [StringSimilarity] is case-insensitive by default, so
/// these helpers normalise case before comparing.
void main() {
  group('LevenshteinDistance.calculate', () {
    test('identical strings have distance 0', () {
      expect(LevenshteinDistance.calculate('hello', 'hello'), equals(0));
    });

    test('one substitution edit has distance 1', () {
      expect(LevenshteinDistance.calculate('hello', 'hallo'), equals(1));
    });

    test('one insertion edit has distance 1', () {
      expect(LevenshteinDistance.calculate('cat', 'cats'), equals(1));
    });

    test('one deletion edit has distance 1', () {
      expect(LevenshteinDistance.calculate('cats', 'cat'), equals(1));
    });

    test('classic kitten/sitting case has distance 3', () {
      expect(LevenshteinDistance.calculate('kitten', 'sitting'), equals(3));
    });

    test('empty source returns target length', () {
      expect(LevenshteinDistance.calculate('', 'abc'), equals(3));
    });

    test('empty target returns source length', () {
      expect(LevenshteinDistance.calculate('abc', ''), equals(0 + 'abc'.length));
    });

    test('both empty returns 0', () {
      expect(LevenshteinDistance.calculate('', ''), equals(0));
    });

    test('is case-insensitive by default', () {
      expect(LevenshteinDistance.calculate('HELLO', 'hello'), equals(0));
    });
  });

  group('LevenshteinDistance.similarity', () {
    test('identical strings have similarity 1.0', () {
      expect(LevenshteinDistance.similarity('hello', 'hello'), equals(1.0));
    });

    test('empty vs non-empty has similarity 0.0', () {
      expect(LevenshteinDistance.similarity('', 'abc'), equals(0.0));
    });

    test('one edit over length 5 gives 0.8', () {
      // distance 1, maxLength 5 -> 1.0 - 1/5 = 0.8
      expect(LevenshteinDistance.similarity('hello', 'hallo'), closeTo(0.8, 1e-9));
    });

    test('result is within 0.0 - 1.0 range', () {
      final value = LevenshteinDistance.similarity('kitten', 'sitting');
      expect(value, inInclusiveRange(0.0, 1.0));
      // distance 3, maxLength 7 -> 1.0 - 3/7
      expect(value, closeTo(1.0 - 3 / 7, 1e-9));
    });
  });

  group('LevenshteinDistance.similarityPercentage', () {
    test('identical strings give 100.0', () {
      expect(
        LevenshteinDistance.similarityPercentage('hello', 'hello'),
        equals(100.0),
      );
    });

    test('one edit over length 5 gives 80.0', () {
      expect(
        LevenshteinDistance.similarityPercentage('hello', 'hallo'),
        closeTo(80.0, 1e-9),
      );
    });

    test('completely disjoint via empty gives 0.0', () {
      expect(
        LevenshteinDistance.similarityPercentage('', 'abc'),
        equals(0.0),
      );
    });
  });

  group('LevenshteinDistance.areSimilar', () {
    test('identical strings are similar with default threshold', () {
      expect(LevenshteinDistance.areSimilar('hello', 'hello'), isTrue);
    });

    test('one-edit strings exceed the 0.8 boundary but fail default 0.85', () {
      // similarity is exactly 0.8 here, which is < default threshold 0.85.
      expect(LevenshteinDistance.areSimilar('hello', 'hallo'), isFalse);
    });

    test('custom lower threshold accepts the same pair', () {
      expect(
        LevenshteinDistance.areSimilar('hello', 'hallo', threshold: 0.8),
        isTrue,
      );
    });

    test('custom high threshold rejects a borderline pair', () {
      expect(
        LevenshteinDistance.areSimilar('hello', 'hallo', threshold: 0.95),
        isFalse,
      );
    });
  });

  group('LevenshteinDistance.normalizedDistance', () {
    test('identical strings have normalized distance 0.0', () {
      expect(
        LevenshteinDistance.normalizedDistance('hello', 'hello'),
        equals(0.0),
      );
    });

    test('is the inverse of similarity', () {
      const a = 'kitten';
      const b = 'sitting';
      final sim = LevenshteinDistance.similarity(a, b);
      expect(
        LevenshteinDistance.normalizedDistance(a, b),
        closeTo(1.0 - sim, 1e-9),
      );
    });

    test('one edit over length 5 gives 0.2', () {
      expect(
        LevenshteinDistance.normalizedDistance('hello', 'hallo'),
        closeTo(0.2, 1e-9),
      );
    });
  });

  group('LevenshteinDistance.calculateDamerauLevenshtein', () {
    test('identical strings have distance 0', () {
      expect(
        LevenshteinDistance.calculateDamerauLevenshtein('abc', 'abc'),
        equals(0),
      );
    });

    test('adjacent transposition counts as a single edit', () {
      // "ab" -> "ba" is 1 with Damerau (transposition) vs 2 with Levenshtein.
      expect(
        LevenshteinDistance.calculateDamerauLevenshtein('ab', 'ba'),
        equals(1),
      );
    });

    test('transposition is cheaper than plain Levenshtein for same pair', () {
      const a = 'abcd';
      const b = 'abdc';
      final damerau =
          LevenshteinDistance.calculateDamerauLevenshtein(a, b);
      final plain = LevenshteinDistance.calculate(a, b);
      // One adjacent swap: Damerau 1, plain Levenshtein 2.
      expect(damerau, equals(1));
      expect(plain, equals(2));
      expect(damerau, lessThan(plain));
    });

    test('empty source returns target length', () {
      expect(
        LevenshteinDistance.calculateDamerauLevenshtein('', 'abc'),
        equals(3),
      );
    });
  });

  group('LevenshteinDistance.wordDistance', () {
    test('identical sentences have word distance 0', () {
      expect(
        LevenshteinDistance.wordDistance('the quick fox', 'the quick fox'),
        equals(0),
      );
    });

    test('two changed words give word distance 2', () {
      expect(
        LevenshteinDistance.wordDistance(
          'the quick brown fox',
          'the slow brown dog',
        ),
        equals(2),
      );
    });

    test('one added word gives word distance 1', () {
      expect(
        LevenshteinDistance.wordDistance('the fox', 'the quick fox'),
        equals(1),
      );
    });
  });

  group('LevenshteinDistance.wordSimilarity', () {
    test('identical sentences have word similarity 1.0', () {
      expect(
        LevenshteinDistance.wordSimilarity('the quick fox', 'the quick fox'),
        equals(1.0),
      );
    });

    test('two of four words changed gives 0.5', () {
      // word distance 2, max word count 4 -> 1.0 - 2/4 = 0.5
      expect(
        LevenshteinDistance.wordSimilarity(
          'the quick brown fox',
          'the slow brown dog',
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('result stays within 0.0 - 1.0 range', () {
      final value = LevenshteinDistance.wordSimilarity(
        'one two three',
        'one two four',
      );
      expect(value, inInclusiveRange(0.0, 1.0));
      // word distance 1, max word count 3 -> 1.0 - 1/3
      expect(value, closeTo(1.0 - 1 / 3, 1e-9));
    });
  });
}
