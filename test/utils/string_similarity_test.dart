import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/utils/string_similarity.dart';

void main() {
  // Ensure cache state never leaks between tests.
  setUp(StringSimilarity.disableCache);
  tearDown(StringSimilarity.disableCache);

  group('levenshteinDistance', () {
    test('identical strings return 0', () {
      expect(StringSimilarity.levenshteinDistance('hello', 'hello'), 0);
    });

    test('classic kitten -> sitting is 3', () {
      expect(StringSimilarity.levenshteinDistance('kitten', 'sitting'), 3);
    });

    test('empty source returns target length', () {
      expect(StringSimilarity.levenshteinDistance('', 'abc'), 3);
    });

    test('empty target returns source length', () {
      expect(StringSimilarity.levenshteinDistance('abcd', ''), 4);
    });

    test('both empty returns 0', () {
      expect(StringSimilarity.levenshteinDistance('', ''), 0);
    });

    test('case-insensitive by default treats differing case as equal', () {
      expect(StringSimilarity.levenshteinDistance('HELLO', 'hello'), 0);
    });

    test('case-sensitive substitutions counted correctly', () {
      // HELLO vs hello: every letter differs in case -> 5 substitutions.
      expect(
        StringSimilarity.levenshteinDistance(
          'HELLO',
          'hello',
          caseSensitive: true,
        ),
        5,
      );
    });

    test('longer source than target (deletions path)', () {
      // 'flaw' -> 'lawn': f deleted, n appended -> 2.
      expect(StringSimilarity.levenshteinDistance('flaw', 'lawn'), 2);
    });

    test('shorter source than target (insertion path)', () {
      expect(StringSimilarity.levenshteinDistance('lawn', 'flawn'), 1);
    });

    test('single substitution', () {
      expect(StringSimilarity.levenshteinDistance('cat', 'bat'), 1);
    });

    test('whitespace differences count as edits', () {
      expect(StringSimilarity.levenshteinDistance('a b', 'ab'), 1);
    });

    test('completely different strings of equal length', () {
      expect(StringSimilarity.levenshteinDistance('abc', 'xyz'), 3);
    });
  });

  group('levenshteinDistance with cache', () {
    test('returns same result with cache enabled (cache miss then hit)', () {
      StringSimilarity.enableCache();
      final first = StringSimilarity.levenshteinDistance('kitten', 'sitting');
      // Second call hits the cache and must return the same value.
      final second = StringSimilarity.levenshteinDistance('kitten', 'sitting');
      expect(first, 3);
      expect(second, 3);
      final stats = StringSimilarity.getCacheStats();
      expect(stats, isNotNull);
      expect(stats!.size, 1);
    });

    test('cache hit moves entry to most-recently-used position', () {
      StringSimilarity.enableCache(maxSize: 2);
      StringSimilarity.levenshteinDistance('aa', 'bb'); // entry 1
      StringSimilarity.levenshteinDistance('cc', 'dd'); // entry 2
      // Touch entry 1 so it becomes most-recently used.
      StringSimilarity.levenshteinDistance('aa', 'bb');
      // Insert a third entry -> evicts the LRU (entry 2 'cc'/'dd').
      StringSimilarity.levenshteinDistance('ee', 'ff');
      final stats = StringSimilarity.getCacheStats();
      expect(stats!.size, 2);
    });

    test('eviction respects configured maxSize', () {
      StringSimilarity.enableCache(maxSize: 1);
      StringSimilarity.levenshteinDistance('aa', 'bb');
      StringSimilarity.levenshteinDistance('cc', 'dd');
      final stats = StringSimilarity.getCacheStats();
      expect(stats!.size, 1);
      expect(stats.maxSize, 1);
    });

    test('non-positive maxSize is clamped to 1', () {
      StringSimilarity.enableCache(maxSize: 0);
      final stats = StringSimilarity.getCacheStats();
      expect(stats!.maxSize, 1);
    });

    test('clearCache empties entries but keeps cache enabled', () {
      StringSimilarity.enableCache();
      StringSimilarity.levenshteinDistance('kitten', 'sitting');
      StringSimilarity.clearCache();
      final stats = StringSimilarity.getCacheStats();
      expect(stats, isNotNull);
      expect(stats!.size, 0);
    });

    test('disableCache makes getCacheStats return null', () {
      StringSimilarity.enableCache();
      StringSimilarity.disableCache();
      expect(StringSimilarity.getCacheStats(), isNull);
    });

    test('clearCache is a no-op when cache disabled', () {
      StringSimilarity.disableCache();
      // Should not throw.
      StringSimilarity.clearCache();
      expect(StringSimilarity.getCacheStats(), isNull);
    });

    test('cache key avoids delimiter collisions', () {
      StringSimilarity.enableCache();
      // ('a|b','c') and ('a','b|c') must NOT collide.
      final d1 = StringSimilarity.levenshteinDistance('a|b', 'c');
      final d2 = StringSimilarity.levenshteinDistance('a', 'b|c');
      expect(d1, 3); // a|b -> c : 3 edits
      expect(d2, 3); // a -> b|c : 3 edits
      final stats = StringSimilarity.getCacheStats();
      // Two distinct keys must be stored.
      expect(stats!.size, 2);
    });
  });

  group('similarity', () {
    test('identical strings return 1.0', () {
      expect(StringSimilarity.similarity('hello', 'hello'), 1.0);
    });

    test('empty source returns 0.0', () {
      expect(StringSimilarity.similarity('', 'abc'), 0.0);
    });

    test('empty target returns 0.0', () {
      expect(StringSimilarity.similarity('abc', ''), 0.0);
    });

    test('both empty returns 1.0 (equal short-circuit)', () {
      expect(StringSimilarity.similarity('', ''), 1.0);
    });

    test('kitten vs sitting ~ 0.5714', () {
      expect(
        StringSimilarity.similarity('kitten', 'sitting'),
        closeTo(1.0 - 3 / 7, 1e-9),
      );
    });

    test('completely different equal-length strings return 0.0', () {
      expect(StringSimilarity.similarity('abc', 'xyz'), closeTo(0.0, 1e-9));
    });

    test('case-insensitive identical-up-to-case returns 1.0', () {
      expect(StringSimilarity.similarity('Hello', 'hello'), 1.0);
    });

    test('case-sensitive lowers score for case differences', () {
      // 'Hello' vs 'hello': 1 substitution over length 5.
      expect(
        StringSimilarity.similarity('Hello', 'hello', caseSensitive: true),
        closeTo(1.0 - 1 / 5, 1e-9),
      );
    });

    test('partial overlap hello vs helo', () {
      expect(
        StringSimilarity.similarity('hello', 'helo'),
        closeTo(1.0 - 1 / 5, 1e-9),
      );
    });
  });

  group('normalizedDistance', () {
    test('identical strings return 0.0', () {
      expect(StringSimilarity.normalizedDistance('abc', 'abc'), 0.0);
    });

    test('is inverse of similarity', () {
      const a = 'kitten';
      const b = 'sitting';
      expect(
        StringSimilarity.normalizedDistance(a, b),
        closeTo(1.0 - StringSimilarity.similarity(a, b), 1e-9),
      );
    });

    test('empty vs non-empty returns 1.0', () {
      expect(StringSimilarity.normalizedDistance('', 'abc'), 1.0);
    });
  });

  group('similarityPercentage', () {
    test('identical strings return 100.0', () {
      expect(StringSimilarity.similarityPercentage('abc', 'abc'), 100.0);
    });

    test('kitten vs sitting ~ 57.14%', () {
      expect(
        StringSimilarity.similarityPercentage('kitten', 'sitting'),
        closeTo((1.0 - 3 / 7) * 100.0, 1e-9),
      );
    });

    test('passes caseSensitive through', () {
      expect(
        StringSimilarity.similarityPercentage(
          'Hello',
          'hello',
          caseSensitive: true,
        ),
        closeTo((1.0 - 1 / 5) * 100.0, 1e-9),
      );
    });
  });

  group('areSimilar', () {
    test('identical strings are similar', () {
      expect(StringSimilarity.areSimilar('hello', 'hello'), isTrue);
    });

    test('above threshold returns true', () {
      // hello vs helo similarity = 0.8.
      expect(
        StringSimilarity.areSimilar('hello', 'helo', threshold: 0.8),
        isTrue,
      );
    });

    test('exactly at threshold returns true (>= boundary)', () {
      expect(
        StringSimilarity.areSimilar('hello', 'helo', threshold: 0.8),
        isTrue,
      );
    });

    test('just above threshold returns false', () {
      expect(
        StringSimilarity.areSimilar('hello', 'helo', threshold: 0.81),
        isFalse,
      );
    });

    test('default threshold 0.85 rejects weak match', () {
      expect(StringSimilarity.areSimilar('hello', 'helo'), isFalse);
    });

    test('completely different strings are not similar', () {
      expect(StringSimilarity.areSimilar('abc', 'xyz'), isFalse);
    });

    test('caseSensitive flag affects result', () {
      expect(
        StringSimilarity.areSimilar(
          'HELLO',
          'hello',
          threshold: 0.99,
          caseSensitive: true,
        ),
        isFalse,
      );
      expect(
        StringSimilarity.areSimilar(
          'HELLO',
          'hello',
          threshold: 0.99,
          caseSensitive: false,
        ),
        isTrue,
      );
    });
  });

  group('damerauLevenshteinDistance', () {
    test('identical strings return 0', () {
      expect(StringSimilarity.damerauLevenshteinDistance('abc', 'abc'), 0);
    });

    test('empty source returns target length', () {
      expect(StringSimilarity.damerauLevenshteinDistance('', 'abcd'), 4);
    });

    test('empty target returns source length', () {
      expect(StringSimilarity.damerauLevenshteinDistance('abc', ''), 3);
    });

    test('both empty returns 0', () {
      expect(StringSimilarity.damerauLevenshteinDistance('', ''), 0);
    });

    test('adjacent transposition ab -> ba is 1', () {
      expect(StringSimilarity.damerauLevenshteinDistance('ab', 'ba'), 1);
    });

    test('transposition cheaper than two substitutions', () {
      // 'converse' vs 'covnerse': swap of n/v -> 1.
      expect(
        StringSimilarity.damerauLevenshteinDistance('converse', 'covnerse'),
        1,
      );
    });

    test('restricted OSA: ca -> abc is 3', () {
      expect(StringSimilarity.damerauLevenshteinDistance('ca', 'abc'), 3);
    });

    test('single substitution', () {
      expect(StringSimilarity.damerauLevenshteinDistance('cat', 'bat'), 1);
    });

    test('case-insensitive by default', () {
      expect(StringSimilarity.damerauLevenshteinDistance('AB', 'ba'), 1);
    });

    test('case-sensitive treats case as difference', () {
      expect(
        StringSimilarity.damerauLevenshteinDistance(
          'AB',
          'ba',
          caseSensitive: true,
        ),
        2, // A->b, B->a (no transposition since cases differ)
      );
    });
  });

  group('wordDistance', () {
    test('identical sentences return 0', () {
      expect(
        StringSimilarity.wordDistance('the quick fox', 'the quick fox'),
        0,
      );
    });

    test('two word substitutions', () {
      expect(
        StringSimilarity.wordDistance(
          'the quick brown fox',
          'the slow brown dog',
        ),
        2,
      );
    });

    test('case-insensitive by default', () {
      expect(
        StringSimilarity.wordDistance('The Quick Fox', 'the quick fox'),
        0,
      );
    });

    test('case-sensitive counts case-differing words', () {
      expect(
        StringSimilarity.wordDistance(
          'The Quick Fox',
          'the quick fox',
          caseSensitive: true,
        ),
        3,
      );
    });

    test('collapses runs of whitespace', () {
      expect(
        StringSimilarity.wordDistance('the   quick    fox', 'the quick fox'),
        0,
      );
    });

    test('word insertion', () {
      expect(
        StringSimilarity.wordDistance('the fox', 'the quick fox'),
        1,
      );
    });

    test('word deletion', () {
      expect(
        StringSimilarity.wordDistance('the quick fox', 'the fox'),
        1,
      );
    });
  });

  group('wordSimilarity', () {
    test('identical sentences return 1.0', () {
      expect(
        StringSimilarity.wordSimilarity('the quick fox', 'the quick fox'),
        1.0,
      );
    });

    test('one of four words changed', () {
      expect(
        StringSimilarity.wordSimilarity(
          'the quick brown fox',
          'the quick brown dog',
        ),
        closeTo(1.0 - 1 / 4, 1e-9),
      );
    });

    test('two of four words changed', () {
      expect(
        StringSimilarity.wordSimilarity(
          'the quick brown fox',
          'the slow brown dog',
        ),
        closeTo(1.0 - 2 / 4, 1e-9),
      );
    });

    test('case-sensitive lowers similarity', () {
      expect(
        StringSimilarity.wordSimilarity(
          'The Quick Fox',
          'the quick fox',
          caseSensitive: true,
        ),
        closeTo(0.0, 1e-9),
      );
    });

    test('completely different single words', () {
      expect(
        StringSimilarity.wordSimilarity('cat', 'dog'),
        closeTo(0.0, 1e-9),
      );
    });
  });

  group('CacheStats', () {
    test('utilization computes size/maxSize', () {
      const stats = CacheStats(size: 5, maxSize: 10);
      expect(stats.utilization, 0.5);
    });

    test('utilization is 0.0 when maxSize is 0', () {
      const stats = CacheStats(size: 0, maxSize: 0);
      expect(stats.utilization, 0.0);
    });

    test('toString includes size and utilization percentage', () {
      const stats = CacheStats(size: 5, maxSize: 10);
      final s = stats.toString();
      expect(s, contains('5/10'));
      expect(s, contains('50.0%'));
    });
  });
}
