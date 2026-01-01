import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/utils/glossary_matcher.dart';

void main() {
  // Helper function to create test glossary entries
  GlossaryEntry createTestEntry({
    String id = 'entry-1',
    String glossaryId = 'glossary-1',
    String sourceTerm = 'test',
    String targetTerm = 'test_fr',
    String targetLanguageCode = 'fr',
    bool caseSensitive = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      targetLanguageCode: targetLanguageCode,
      sourceTerm: sourceTerm,
      targetTerm: targetTerm,
      caseSensitive: caseSensitive,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('GlossaryMatcher', () {
    // =========================================================================
    // findMatches - Basic Cases
    // =========================================================================
    group('findMatches - basic cases', () {
      test('should find single term match', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        const text = 'The cavalry unit attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.matchedText, 'cavalry');
        expect(result.first.entry.sourceTerm, 'cavalry');
        expect(result.first.startIndex, 4);
        expect(result.first.endIndex, 11);
      });

      test('should find multiple term matches', () {
        // Arrange
        final entries = [
          createTestEntry(id: '1', sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
          createTestEntry(id: '2', sourceTerm: 'infantry', targetTerm: 'infanterie'),
        ];
        const text = 'The cavalry and infantry units attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 2);
        expect(result.any((m) => m.matchedText == 'cavalry'), true);
        expect(result.any((m) => m.matchedText == 'infantry'), true);
      });

      test('should return empty list when no matches found', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'archer', targetTerm: 'archer'),
        ];
        const text = 'The cavalry unit attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.isEmpty, true);
      });

      test('should handle empty text', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        const text = '';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.isEmpty, true);
      });

      test('should handle empty entries list', () {
        // Arrange
        final entries = <GlossaryEntry>[];
        const text = 'The cavalry unit attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.isEmpty, true);
      });
    });

    // =========================================================================
    // findMatches - Whole Word Matching
    // =========================================================================
    group('findMatches - whole word matching', () {
      test('should match whole words only by default', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'war', targetTerm: 'guerre'),
        ];
        const text = 'The warrior went to war.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
          wholeWordOnly: true,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.matchedText, 'war');
        // Should not match 'war' in 'warrior'
        expect(result.first.startIndex, 20);
      });

      test('should match partial words when wholeWordOnly is false', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'war', targetTerm: 'guerre'),
        ];
        const text = 'The warrior went to war.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
          wholeWordOnly: false,
        );

        // Assert
        // Should find both occurrences: in 'warrior' and standalone 'war'
        expect(result.length, 2);
      });

      test('should handle word boundaries correctly', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'unit', targetTerm: 'unite'),
        ];
        const text = 'The unit and units attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
          wholeWordOnly: true,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.matchedText, 'unit');
        // Should not match 'unit' in 'units'
      });

      test('should handle term at start of text', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        const text = 'Cavalry attacks!';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.startIndex, 0);
      });

      test('should handle term at end of text', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        const text = 'Send the cavalry';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.endIndex, 16);
      });
    });

    // =========================================================================
    // findMatches - Case Sensitivity
    // =========================================================================
    group('findMatches - case sensitivity', () {
      test('should match case-insensitively by default', () {
        // Arrange
        final entries = [
          createTestEntry(
            sourceTerm: 'cavalry',
            targetTerm: 'cavalerie',
            caseSensitive: false,
          ),
        ];
        const text = 'The CAVALRY unit attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.matchedText, 'CAVALRY');
      });

      test('should respect case-sensitive entries', () {
        // Arrange
        final entries = [
          createTestEntry(
            sourceTerm: 'Cavalry',
            targetTerm: 'Cavalerie',
            caseSensitive: true,
          ),
        ];
        const text = 'The cavalry unit attacked. Cavalry is powerful.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.matchedText, 'Cavalry');
      });

      test('should not match case-sensitive term with wrong case', () {
        // Arrange
        final entries = [
          createTestEntry(
            sourceTerm: 'CAVALRY',
            targetTerm: 'CAVALERIE',
            caseSensitive: true,
          ),
        ];
        const text = 'The cavalry unit attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.isEmpty, true);
      });
    });

    // =========================================================================
    // findMatches - Overlapping Matches
    // =========================================================================
    group('findMatches - overlapping matches', () {
      test('should prioritize longer matches', () {
        // Arrange
        final entries = [
          createTestEntry(id: '1', sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
          createTestEntry(id: '2', sourceTerm: 'cavalry unit', targetTerm: 'unite de cavalerie'),
        ];
        const text = 'The cavalry unit attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
        expect(result.first.matchedText, 'cavalry unit');
      });

      test('should remove overlapping matches', () {
        // Arrange
        final entries = [
          createTestEntry(id: '1', sourceTerm: 'heavy', targetTerm: 'lourd'),
          createTestEntry(id: '2', sourceTerm: 'heavy cavalry', targetTerm: 'cavalerie lourde'),
          createTestEntry(id: '3', sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        const text = 'The heavy cavalry attacked.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        // Should only return 'heavy cavalry', not 'heavy' and 'cavalry' separately
        expect(result.length, 1);
        expect(result.first.matchedText, 'heavy cavalry');
      });
    });

    // =========================================================================
    // findMatches - Multiple Occurrences
    // =========================================================================
    group('findMatches - multiple occurrences', () {
      test('should find multiple occurrences of same term', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        const text = 'The cavalry attacked. Another cavalry retreated.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 2);
      });
    });

    // =========================================================================
    // applySubstitutions
    // =========================================================================
    group('applySubstitutions', () {
      test('should replace matched terms in target text', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
        ];
        const sourceText = 'The cavalry attacked.';
        const targetText = 'The cavalry attacked.';

        // Act
        final result = GlossaryMatcher.applySubstitutions(
          sourceText: sourceText,
          targetText: targetText,
          matches: matches,
        );

        // Assert
        expect(result, 'The cavalerie attacked.');
      });

      test('should return original text when no matches', () {
        // Arrange
        final matches = <GlossaryMatch>[];
        const sourceText = 'The cavalry attacked.';
        const targetText = 'The cavalry attacked.';

        // Act
        final result = GlossaryMatcher.applySubstitutions(
          sourceText: sourceText,
          targetText: targetText,
          matches: matches,
        );

        // Assert
        expect(result, 'The cavalry attacked.');
      });

      test('should handle multiple substitutions', () {
        // Arrange
        final entry1 = createTestEntry(
          id: '1',
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final entry2 = createTestEntry(
          id: '2',
          sourceTerm: 'infantry',
          targetTerm: 'infanterie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry1,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
          GlossaryMatch(
            entry: entry2,
            startIndex: 16,
            endIndex: 24,
            matchedText: 'infantry',
          ),
        ];
        const sourceText = 'The cavalry and infantry attacked.';
        const targetText = 'The cavalry and infantry attacked.';

        // Act
        final result = GlossaryMatcher.applySubstitutions(
          sourceText: sourceText,
          targetText: targetText,
          matches: matches,
        );

        // Assert
        expect(result, contains('cavalerie'));
        expect(result, contains('infanterie'));
      });

      test('should respect case sensitivity in substitution', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
          caseSensitive: false,
        );
        final matches = [
          GlossaryMatch(
            entry: entry,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'CAVALRY',
          ),
        ];
        const sourceText = 'The CAVALRY attacked.';
        const targetText = 'The CAVALRY attacked.';

        // Act
        final result = GlossaryMatcher.applySubstitutions(
          sourceText: sourceText,
          targetText: targetText,
          matches: matches,
        );

        // Assert
        expect(result, 'The cavalerie attacked.');
      });
    });

    // =========================================================================
    // highlightMatches
    // =========================================================================
    group('highlightMatches', () {
      test('should insert highlight markers around matches', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
        ];
        const text = 'The cavalry attacked.';

        // Act
        final result = GlossaryMatcher.highlightMatches(
          text: text,
          matches: matches,
        );

        // Assert
        expect(result, 'The **cavalry** attacked.');
      });

      test('should use custom highlight markers', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
        ];
        const text = 'The cavalry attacked.';

        // Act
        final result = GlossaryMatcher.highlightMatches(
          text: text,
          matches: matches,
          highlightPrefix: '<mark>',
          highlightSuffix: '</mark>',
        );

        // Assert
        expect(result, 'The <mark>cavalry</mark> attacked.');
      });

      test('should return original text when no matches', () {
        // Arrange
        final matches = <GlossaryMatch>[];
        const text = 'The cavalry attacked.';

        // Act
        final result = GlossaryMatcher.highlightMatches(
          text: text,
          matches: matches,
        );

        // Assert
        expect(result, 'The cavalry attacked.');
      });

      test('should handle multiple highlights', () {
        // Arrange
        final entry1 = createTestEntry(
          id: '1',
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final entry2 = createTestEntry(
          id: '2',
          sourceTerm: 'infantry',
          targetTerm: 'infanterie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry1,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
          GlossaryMatch(
            entry: entry2,
            startIndex: 16,
            endIndex: 24,
            matchedText: 'infantry',
          ),
        ];
        const text = 'The cavalry and infantry attacked.';

        // Act
        final result = GlossaryMatcher.highlightMatches(
          text: text,
          matches: matches,
        );

        // Assert
        expect(result, 'The **cavalry** and **infantry** attacked.');
      });
    });

    // =========================================================================
    // getMatchStatistics
    // =========================================================================
    group('getMatchStatistics', () {
      test('should calculate correct statistics', () {
        // Arrange
        final entry1 = createTestEntry(
          id: '1',
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final entry2 = createTestEntry(
          id: '2',
          sourceTerm: 'infantry',
          targetTerm: 'infanterie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry1,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
          GlossaryMatch(
            entry: entry2,
            startIndex: 16,
            endIndex: 24,
            matchedText: 'infantry',
          ),
        ];
        const text = 'The cavalry and infantry attacked.';

        // Act
        final result = GlossaryMatcher.getMatchStatistics(
          text: text,
          matches: matches,
        );

        // Assert
        expect(result['totalMatches'], 2);
        expect(result['uniqueTerms'], 2);
        expect(result['coveragePercent'], greaterThan(0));
      });

      test('should return zeros for empty text', () {
        // Arrange
        final matches = <GlossaryMatch>[];
        const text = '';

        // Act
        final result = GlossaryMatcher.getMatchStatistics(
          text: text,
          matches: matches,
        );

        // Assert
        expect(result['totalMatches'], 0);
        expect(result['uniqueTerms'], 0);
        expect(result['coveragePercent'], 0.0);
      });

      test('should count unique terms correctly', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final matches = [
          GlossaryMatch(
            entry: entry,
            startIndex: 4,
            endIndex: 11,
            matchedText: 'cavalry',
          ),
          GlossaryMatch(
            entry: entry,
            startIndex: 20,
            endIndex: 27,
            matchedText: 'cavalry',
          ),
        ];
        const text = 'The cavalry. More cavalry.';

        // Act
        final result = GlossaryMatcher.getMatchStatistics(
          text: text,
          matches: matches,
        );

        // Assert
        expect(result['totalMatches'], 2);
        expect(result['uniqueTerms'], 1);
      });
    });

    // =========================================================================
    // GlossaryMatch
    // =========================================================================
    group('GlossaryMatch', () {
      test('should calculate length correctly', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final match = GlossaryMatch(
          entry: entry,
          startIndex: 4,
          endIndex: 11,
          matchedText: 'cavalry',
        );

        // Assert
        expect(match.length, 7);
      });

      test('should have correct toString format', () {
        // Arrange
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );
        final match = GlossaryMatch(
          entry: entry,
          startIndex: 4,
          endIndex: 11,
          matchedText: 'cavalry',
        );

        // Act
        final result = match.toString();

        // Assert
        expect(result, contains('cavalry'));
        expect(result, contains('4-11'));
      });
    });

    // =========================================================================
    // Edge Cases
    // =========================================================================
    group('edge cases', () {
      test('should handle unicode characters in term', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cafe', targetTerm: 'cafe'),
        ];
        const text = 'I love cafe.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
      });

      test('should handle terms with special characters', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'C++', targetTerm: 'C++'),
        ];
        const text = 'I program in C++ language.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
          wholeWordOnly: false,
        );

        // Assert
        expect(result.length, 1);
      });

      test('should handle very long text', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'cavalry', targetTerm: 'cavalerie'),
        ];
        final text = 'text ' * 1000 + 'cavalry' + ' text' * 1000;

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
      });

      test('should handle terms with numbers', () {
        // Arrange
        final entries = [
          createTestEntry(sourceTerm: 'Unit42', targetTerm: 'Unite42'),
        ];
        const text = 'The Unit42 is ready.';

        // Act
        final result = GlossaryMatcher.findMatches(
          text: text,
          entries: entries,
        );

        // Assert
        expect(result.length, 1);
      });
    });
  });
}
