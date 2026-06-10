import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/utils/string_similarity.dart';

/// Regression tests for [StringSimilarity.damerauLevenshteinDistance].
///
/// The previous implementation applied the transposition term without
/// checking that the two adjacent characters are actually swapped
/// (s1[i-1] == s2[j-2] && s1[i-2] == s2[j-1]), counting invalid
/// transpositions and underestimating the distance — e.g. it returned 1
/// for 'ab' → 'cd' (two substitutions, correct distance 2).
void main() {
  group('StringSimilarity.damerauLevenshteinDistance (restricted/OSA)', () {
    test('table-driven known distances', () {
      const cases = <(String, String, int)>[
        ('', '', 0),
        ('abc', 'abc', 0),
        ('', 'abc', 3),
        ('abc', '', 3),
        // Single adjacent swap counts as one edit.
        ('ab', 'ba', 1),
        ('abc', 'acb', 1),
        // Classic Levenshtein case, no transpositions involved.
        ('kitten', 'sitting', 3),
        // Insert + adjacent swap.
        ('a cat', 'an act', 2),
        // OSA restriction: no substring is edited more than once, so this
        // is 3 (the unrestricted Damerau-Levenshtein variant would give 2).
        ('ca', 'abc', 3),
      ];

      for (final (source, target, expected) in cases) {
        expect(
          StringSimilarity.damerauLevenshteinDistance(source, target),
          expected,
          reason: "'$source' -> '$target'",
        );
      }
    });

    test('does not count a transposition when characters are not swapped',
        () {
      // The pre-fix implementation returned 1 here (invalid transposition
      // term matrix[0][0] + 1); the correct distance is two substitutions.
      expect(StringSimilarity.damerauLevenshteinDistance('ab', 'cd'), 2);
      // Same shape further into the matrix.
      expect(StringSimilarity.damerauLevenshteinDistance('xxab', 'xxcd'), 2);
    });

    test('respects caseSensitive flag', () {
      expect(
        StringSimilarity.damerauLevenshteinDistance('AB', 'ba'),
        1,
        reason: 'case-insensitive by default: ab vs ba is one swap',
      );
      expect(
        StringSimilarity.damerauLevenshteinDistance('AB', 'ba',
            caseSensitive: true),
        2,
        reason: 'case-sensitive: A!=b and B!=a, no valid transposition',
      );
    });

    test('distance is symmetric', () {
      const pairs = <(String, String)>[
        ('ab', 'ba'),
        ('ca', 'abc'),
        ('kitten', 'sitting'),
        ('well-trained', 'well trained'),
      ];
      for (final (a, b) in pairs) {
        expect(
          StringSimilarity.damerauLevenshteinDistance(a, b),
          StringSimilarity.damerauLevenshteinDistance(b, a),
          reason: "'$a' <-> '$b'",
        );
      }
    });
  });
}
