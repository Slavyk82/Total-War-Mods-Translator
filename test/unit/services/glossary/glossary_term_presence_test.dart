import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/glossary/glossary_term_presence.dart';

/// Shared case-sensitivity rule used by both checkConsistency implementations.
void main() {
  group('glossaryTermPresentInTarget', () {
    test('case-insensitive: matches regardless of casing', () {
      expect(
        glossaryTermPresentInTarget(
            targetText: 'la Faction est forte',
            targetTerm: 'faction',
            caseSensitive: false),
        isTrue,
      );
    });

    test('case-sensitive: requires the exact prescribed casing', () {
      // Present in the WRONG casing must count as ABSENT for a case-sensitive
      // term — this is the behavior the impl previously ignored.
      expect(
        glossaryTermPresentInTarget(
            targetText: 'la faction est forte',
            targetTerm: 'Faction',
            caseSensitive: true),
        isFalse,
      );
    });

    test('case-sensitive: matches when the casing is exact', () {
      expect(
        glossaryTermPresentInTarget(
            targetText: 'la Faction est forte',
            targetTerm: 'Faction',
            caseSensitive: true),
        isTrue,
      );
    });
  });
}
