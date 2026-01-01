import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/history/diff_calculator.dart';
import 'package:twmt/models/history/diff_models.dart';

void main() {
  group('DiffCalculator', () {
    // =========================================================================
    // calculateDiff - Basic Cases
    // =========================================================================
    group('calculateDiff - basic cases', () {
      test('should return single unchanged segment for identical strings', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, 1);
        expect(result.first.type, DiffType.unchanged);
        expect(result.first.text, 'Hello world');
      });

      test('should return single added segment for empty old text', () {
        // Arrange
        const oldText = '';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, 1);
        expect(result.first.type, DiffType.added);
        expect(result.first.text, 'Hello world');
      });

      test('should return single removed segment for empty new text', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = '';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, 1);
        expect(result.first.type, DiffType.removed);
        expect(result.first.text, 'Hello world');
      });

      test('should detect added characters', () {
        // Arrange
        const oldText = 'Hello';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added), true);
        expect(result.any((s) => s.type == DiffType.unchanged), true);
      });

      test('should detect removed characters', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = 'Hello';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.removed), true);
        expect(result.any((s) => s.type == DiffType.unchanged), true);
      });

      test('should detect both added and removed characters', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = 'Hello planet';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added), true);
        expect(result.any((s) => s.type == DiffType.removed), true);
        expect(result.any((s) => s.type == DiffType.unchanged), true);
      });
    });

    // =========================================================================
    // calculateDiff - Complex Cases
    // =========================================================================
    group('calculateDiff - complex cases', () {
      test('should handle single character change', () {
        // Arrange
        const oldText = 'cat';
        const newText = 'hat';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        // Should have removed 'c', added 'h', unchanged 'at'
        expect(result.any((s) => s.type == DiffType.removed && s.text.contains('c')), true);
        expect(result.any((s) => s.type == DiffType.added && s.text.contains('h')), true);
      });

      test('should handle insertion in middle of text', () {
        // Arrange
        const oldText = 'Helloworld';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added && s.text.contains(' ')), true);
      });

      test('should handle complete replacement', () {
        // Arrange
        const oldText = 'abc';
        const newText = 'xyz';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.removed), true);
        expect(result.any((s) => s.type == DiffType.added), true);
      });

      test('should handle special characters', () {
        // Arrange
        const oldText = 'Hello!';
        const newText = 'Hello?';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, greaterThan(0));
        expect(result.any((s) => s.type == DiffType.removed && s.text.contains('!')), true);
        expect(result.any((s) => s.type == DiffType.added && s.text.contains('?')), true);
      });

      test('should handle unicode characters', () {
        // Arrange
        const oldText = 'cafe';
        const newText = 'cafe';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert (they might be different depending on accent)
        expect(result.length, greaterThan(0));
      });
    });

    // =========================================================================
    // calculateDiff - Edge Cases
    // =========================================================================
    group('calculateDiff - edge cases', () {
      test('should handle both strings empty', () {
        // Arrange
        const oldText = '';
        const newText = '';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, 1);
        expect(result.first.type, DiffType.unchanged);
        expect(result.first.text, '');
      });

      test('should handle very long identical strings', () {
        // Arrange
        final oldText = 'a' * 1000;
        final newText = 'a' * 1000;

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, 1);
        expect(result.first.type, DiffType.unchanged);
      });

      test('should handle strings with only whitespace changes', () {
        // Arrange
        const oldText = 'Hello World';
        const newText = 'Hello  World';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added), true);
      });

      test('should handle newlines', () {
        // Arrange
        const oldText = 'Hello\nWorld';
        const newText = 'Hello\r\nWorld';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, greaterThan(0));
      });
    });

    // =========================================================================
    // calculateWordDiff
    // =========================================================================
    group('calculateWordDiff', () {
      test('should return single unchanged segment for identical strings', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateWordDiff(oldText, newText);

        // Assert
        expect(result.every((s) => s.type == DiffType.unchanged), true);
      });

      test('should detect added words', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = 'Hello beautiful world';

        // Act
        final result = DiffCalculator.calculateWordDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added), true);
      });

      test('should detect removed words', () {
        // Arrange
        const oldText = 'Hello beautiful world';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateWordDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.removed), true);
      });

      test('should detect changed words', () {
        // Arrange
        const oldText = 'Hello world';
        const newText = 'Hello planet';

        // Act
        final result = DiffCalculator.calculateWordDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.removed), true);
        expect(result.any((s) => s.type == DiffType.added), true);
      });

      test('should handle empty strings', () {
        // Arrange
        const oldText = '';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateWordDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added), true);
      });

      test('should preserve whitespace between words', () {
        // Arrange
        const oldText = 'Hello   world';
        const newText = 'Hello world';

        // Act
        final result = DiffCalculator.calculateWordDiff(oldText, newText);

        // Assert
        // The whitespace difference should be detected
        expect(result.length, greaterThan(0));
      });
    });

    // =========================================================================
    // DiffSegment
    // =========================================================================
    group('DiffSegment', () {
      test('should create segment with correct properties', () {
        // Arrange
        const segment = DiffSegment(
          text: 'Hello',
          type: DiffType.unchanged,
        );

        // Assert
        expect(segment.text, 'Hello');
        expect(segment.type, DiffType.unchanged);
      });

      test('should implement equality correctly', () {
        // Arrange
        const segment1 = DiffSegment(text: 'Hello', type: DiffType.unchanged);
        const segment2 = DiffSegment(text: 'Hello', type: DiffType.unchanged);
        const segment3 = DiffSegment(text: 'World', type: DiffType.unchanged);

        // Assert
        expect(segment1, equals(segment2));
        expect(segment1, isNot(equals(segment3)));
      });

      test('should copy with new values', () {
        // Arrange
        const original = DiffSegment(text: 'Hello', type: DiffType.unchanged);

        // Act
        final copied = original.copyWith(type: DiffType.added);

        // Assert
        expect(copied.text, 'Hello');
        expect(copied.type, DiffType.added);
      });
    });

    // =========================================================================
    // DiffStats
    // =========================================================================
    group('DiffStats', () {
      test('should calculate stats from segments correctly', () {
        // Arrange
        final segments = [
          const DiffSegment(text: 'Hello', type: DiffType.unchanged),
          const DiffSegment(text: ' world', type: DiffType.removed),
          const DiffSegment(text: ' planet', type: DiffType.added),
        ];

        // Act
        final stats = DiffStats.fromSegments(segments);

        // Assert
        expect(stats.charsRemoved, 6); // ' world'
        expect(stats.charsAdded, 7); // ' planet'
        expect(stats.charsChanged, 13);
        expect(stats.wordsRemoved, 1);
        expect(stats.wordsAdded, 1);
      });

      test('should handle empty segments list', () {
        // Arrange
        final segments = <DiffSegment>[];

        // Act
        final stats = DiffStats.fromSegments(segments);

        // Assert
        expect(stats.charsAdded, 0);
        expect(stats.charsRemoved, 0);
        expect(stats.wordsAdded, 0);
        expect(stats.wordsRemoved, 0);
      });

      test('should handle only unchanged segments', () {
        // Arrange
        final segments = [
          const DiffSegment(text: 'Hello world', type: DiffType.unchanged),
        ];

        // Act
        final stats = DiffStats.fromSegments(segments);

        // Assert
        expect(stats.charsAdded, 0);
        expect(stats.charsRemoved, 0);
      });

      test('should count multiple words correctly', () {
        // Arrange
        final segments = [
          const DiffSegment(text: 'one two three', type: DiffType.added),
        ];

        // Act
        final stats = DiffStats.fromSegments(segments);

        // Assert
        expect(stats.wordsAdded, 3);
      });
    });

    // =========================================================================
    // Merge Consecutive Segments
    // =========================================================================
    group('merge consecutive segments', () {
      test('should merge consecutive segments of same type', () {
        // Arrange
        const oldText = 'abc';
        const newText = 'xyz';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        // Should be merged into fewer segments
        expect(result.where((s) => s.type == DiffType.removed).length, lessThanOrEqualTo(1));
        expect(result.where((s) => s.type == DiffType.added).length, lessThanOrEqualTo(1));
      });
    });

    // =========================================================================
    // Real-world Scenarios
    // =========================================================================
    group('real-world scenarios', () {
      test('should handle translation correction', () {
        // Arrange
        const oldText = 'The cavalry unit attacks the enemy.';
        const newText = "L'unite de cavalerie attaque l'ennemi.";

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, greaterThan(0));
        expect(result.any((s) => s.type == DiffType.removed), true);
        expect(result.any((s) => s.type == DiffType.added), true);
      });

      test('should handle minor text edit', () {
        // Arrange
        const oldText = 'The quik brown fox';
        const newText = 'The quick brown fox';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.any((s) => s.type == DiffType.added && s.text.contains('c')), true);
      });

      test('should handle variable placeholder change', () {
        // Arrange
        const oldText = 'Hello {0}, welcome!';
        const newText = 'Hello {name}, welcome!';

        // Act
        final result = DiffCalculator.calculateDiff(oldText, newText);

        // Assert
        expect(result.length, greaterThan(0));
      });
    });
  });
}
