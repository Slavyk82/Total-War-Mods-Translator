import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';

void main() {
  late TextNormalizer normalizer;

  setUp(() {
    normalizer = TextNormalizer();
  });

  group('TextNormalizer', () {
    // =========================================================================
    // normalize - Default Options
    // =========================================================================
    group('normalize - default options', () {
      test('should normalize whitespace', () {
        // Arrange
        const text = 'Hello    world\t\ntest';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello world test');
      });

      test('should trim leading and trailing whitespace', () {
        // Arrange
        const text = '   Hello world   ';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello world');
      });

      test('should convert to lowercase', () {
        // Arrange
        const text = 'HELLO World';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello world');
      });

      test('should remove XML/HTML tags', () {
        // Arrange
        const text = '<b>Hello</b> <span class="test">world</span>';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello world');
      });

      test('should remove BBCode tags', () {
        // Arrange
        const text = '[b]Hello[/b] [url=test]world[/url]';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello world');
      });

      test('should preserve printf-style placeholders in brackets', () {
        // Arrange
        const text = 'Count: [%s] items, Value: [%d]';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, contains('[%s]'));
        expect(result, contains('[%d]'));
      });

      test('should remove Markdown formatting', () {
        // Arrange
        const text = '**bold** and *italic* and _underline_ and `code`';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'bold and italic and underline and code');
      });

      test('should normalize curly quotes', () {
        // Arrange
        const text = '\u201cHello\u201d and \u2018world\u2019';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, '"hello" and \'world\'');
      });

      test('should normalize dashes', () {
        // Arrange
        const text = 'Hello—world–test';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello-world-test');
      });

      test('should normalize ellipsis', () {
        // Arrange
        const text = 'Hello… world';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello... world');
      });

      test('should remove duplicate punctuation', () {
        // Arrange
        const text = 'Hello!! What??';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello! what?');
      });
    });

    // =========================================================================
    // normalize - Custom Options
    // =========================================================================
    group('normalize - custom options', () {
      test('should preserve case when lowercase is false', () {
        // Arrange
        const text = 'Hello World';
        const options = NormalizationOptions(lowercase: false);

        // Act
        final result = normalizer.normalize(text, options: options);

        // Assert
        expect(result, 'Hello World');
      });

      test('should preserve markup when removeMarkup is false', () {
        // Arrange
        const text = '<b>Hello</b>';
        const options = NormalizationOptions(removeMarkup: false);

        // Act
        final result = normalizer.normalize(text, options: options);

        // Assert
        expect(result, '<b>hello</b>');
      });

      test('should preserve punctuation when normalizePunctuation is false', () {
        // Arrange
        const text = '"Hello"';
        const options = NormalizationOptions(normalizePunctuation: false);

        // Act
        final result = normalizer.normalize(text, options: options);

        // Assert
        expect(result, '"hello"');
      });

      test('should remove numbers when removeNumbers is true', () {
        // Arrange
        const text = 'Hello 123 world 456';
        const options = NormalizationOptions(removeNumbers: true);

        // Act
        final result = normalizer.normalize(text, options: options);

        // Assert
        // Standalone numbers are removed, spaces collapse
        expect(result.contains('123'), false);
        expect(result.contains('456'), false);
        expect(result.contains('hello'), true);
        expect(result.contains('world'), true);
      });

      test('should use lenient options correctly', () {
        // Arrange
        const text = 'Hello 123 World';
        const options = NormalizationOptions.lenientOptions;

        // Act
        final result = normalizer.normalize(text, options: options);

        // Assert
        // Lenient: removeMarkup=true, lowercase=false, normalizePunctuation=false
        expect(result, 'Hello 123 World');
      });

      test('should use strict options correctly', () {
        // Arrange
        const text = 'Hello 123 World';
        const options = NormalizationOptions.strictOptions;

        // Act
        final result = normalizer.normalize(text, options: options);

        // Assert
        // Strict: all normalizations including number removal
        // Numbers are removed as standalone words, leaving extra spaces that get collapsed
        expect(result.contains('123'), false);
        expect(result.contains('hello'), true);
        expect(result.contains('world'), true);
      });
    });

    // =========================================================================
    // tokenize
    // =========================================================================
    group('tokenize', () {
      test('should split text into tokens', () {
        // Arrange
        const text = 'Hello world test';

        // Act
        final result = normalizer.tokenize(text);

        // Assert
        expect(result.length, 3);
        expect(result.contains('hello'), true);
        expect(result.contains('world'), true);
        expect(result.contains('test'), true);
      });

      test('should deduplicate tokens', () {
        // Arrange
        const text = 'hello hello hello world';

        // Act
        final result = normalizer.tokenize(text);

        // Assert
        expect(result.length, 2);
      });

      test('should normalize tokens before tokenizing', () {
        // Arrange
        const text = 'HELLO World';

        // Act
        final result = normalizer.tokenize(text);

        // Assert
        expect(result.contains('hello'), true);
        expect(result.contains('world'), true);
      });

      test('should handle empty text', () {
        // Arrange
        const text = '';

        // Act
        final result = normalizer.tokenize(text);

        // Assert
        expect(result.isEmpty, true);
      });

      test('should handle text with only whitespace', () {
        // Arrange
        const text = '   ';

        // Act
        final result = normalizer.tokenize(text);

        // Assert
        expect(result.isEmpty, true);
      });

      test('should handle single word', () {
        // Arrange
        const text = 'Hello';

        // Act
        final result = normalizer.tokenize(text);

        // Assert
        expect(result.length, 1);
        expect(result.contains('hello'), true);
      });
    });

    // =========================================================================
    // getNGrams
    // =========================================================================
    group('getNGrams', () {
      test('should generate bigrams by default', () {
        // Arrange
        const text = 'hello';

        // Act
        final result = normalizer.getNGrams(text);

        // Assert
        expect(result.length, 4); // he, el, ll, lo
        expect(result.contains('he'), true);
        expect(result.contains('el'), true);
        expect(result.contains('ll'), true);
        expect(result.contains('lo'), true);
      });

      test('should generate trigrams when n=3', () {
        // Arrange
        const text = 'hello';

        // Act
        final result = normalizer.getNGrams(text, n: 3);

        // Assert
        expect(result.length, 3); // hel, ell, llo
        expect(result.contains('hel'), true);
        expect(result.contains('ell'), true);
        expect(result.contains('llo'), true);
      });

      test('should return whole text when text is shorter than n', () {
        // Arrange
        const text = 'hi';

        // Act
        final result = normalizer.getNGrams(text, n: 3);

        // Assert
        expect(result.length, 1);
        expect(result.contains('hi'), true);
      });

      test('should handle empty text', () {
        // Arrange
        const text = '';

        // Act
        final result = normalizer.getNGrams(text);

        // Assert
        expect(result.length, 1);
        expect(result.contains(''), true);
      });

      test('should handle single character', () {
        // Arrange
        const text = 'a';

        // Act
        final result = normalizer.getNGrams(text, n: 2);

        // Assert
        expect(result.length, 1);
        expect(result.contains('a'), true);
      });

      test('should generate unique n-grams', () {
        // Arrange
        const text = 'aaa';

        // Act
        final result = normalizer.getNGrams(text, n: 2);

        // Assert
        expect(result.length, 1); // Only 'aa'
        expect(result.contains('aa'), true);
      });
    });

    // =========================================================================
    // Edge Cases
    // =========================================================================
    group('edge cases', () {
      test('should handle unicode characters', () {
        // Arrange
        const text = 'cafe resume';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result.isNotEmpty, true);
      });

      test('should handle special characters', () {
        // Arrange
        const text = 'Hello @#\$%^&*() world';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result.isNotEmpty, true);
      });

      test('should handle very long text', () {
        // Arrange
        final text = 'Hello world ' * 1000;

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result.isNotEmpty, true);
      });

      test('should handle mixed markup', () {
        // Arrange
        const text = '<b>Bold</b> [b]BBCode[/b] **Markdown**';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        // The BBCode tags are removed, Bold and Markdown stars are removed
        expect(result.contains('bold'), true);
        expect(result.contains('<b>'), false);
      });

      test('should handle nested tags', () {
        // Arrange
        const text = '<div><span>Hello</span></div>';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'hello');
      });

      test('should handle self-closing tags', () {
        // Arrange
        const text = 'Hello<br/>world';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'helloworld');
      });

      test('should handle multiple consecutive spaces in punctuation normalization', () {
        // Arrange
        const text = 'Hello .  World';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result.contains('  '), false);
      });
    });

    // =========================================================================
    // Singleton Pattern
    // =========================================================================
    group('singleton pattern', () {
      test('should return same instance', () {
        // Arrange
        final normalizer1 = TextNormalizer();
        final normalizer2 = TextNormalizer();

        // Assert
        expect(identical(normalizer1, normalizer2), true);
      });
    });

    // =========================================================================
    // NormalizationOptions
    // =========================================================================
    group('NormalizationOptions', () {
      test('should have correct default values', () {
        // Arrange
        const options = NormalizationOptions();

        // Assert
        expect(options.removeMarkup, true);
        expect(options.lowercase, true);
        expect(options.normalizePunctuation, true);
        expect(options.removeNumbers, false);
      });

      test('should have correct defaultOptions values', () {
        // Arrange
        const options = NormalizationOptions.defaultOptions;

        // Assert
        expect(options.removeMarkup, true);
        expect(options.lowercase, true);
        expect(options.normalizePunctuation, true);
        expect(options.removeNumbers, false);
      });

      test('should have correct strictOptions values', () {
        // Arrange
        const options = NormalizationOptions.strictOptions;

        // Assert
        expect(options.removeMarkup, true);
        expect(options.lowercase, true);
        expect(options.normalizePunctuation, true);
        expect(options.removeNumbers, true);
      });

      test('should have correct lenientOptions values', () {
        // Arrange
        const options = NormalizationOptions.lenientOptions;

        // Assert
        expect(options.removeMarkup, true);
        expect(options.lowercase, false);
        expect(options.normalizePunctuation, false);
        expect(options.removeNumbers, false);
      });

      test('should have correct toString format', () {
        // Arrange
        const options = NormalizationOptions();

        // Act
        final result = options.toString();

        // Assert
        expect(result, contains('NormalizationOptions'));
        expect(result, contains('removeMarkup'));
        expect(result, contains('lowercase'));
      });
    });

    // =========================================================================
    // Real-world Scenarios
    // =========================================================================
    group('real-world scenarios', () {
      test('should normalize game tooltip text', () {
        // Arrange
        const text = '<span class="positive">+10%</span> attack bonus';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, '+10% attack bonus');
      });

      test('should normalize BBCode-formatted game text', () {
        // Arrange
        const text = '[color=red]Warning[/color] You need [%s] resources.';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        // BBCode tags are removed, printf placeholder [%s] is preserved
        expect(result.contains('[%s]'), true);
        expect(result.contains('[color=red]'), false);
        expect(result.contains('[/color]'), false);
      });

      test('should handle typical translation text', () {
        // Arrange
        const text = '"The cavalry unit"—with its   mounted warriors—attacks!';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result.contains('"'), true); // Normalized quotes
        expect(result.contains('—'), false); // Em dash normalized
        expect(result.contains('  '), false); // No double spaces
      });

      test('should normalize variable placeholders in game text', () {
        // Arrange
        const text = 'Unit {0} attacks {1} for {2} damage';

        // Act
        final result = normalizer.normalize(text);

        // Assert
        expect(result, 'unit {0} attacks {1} for {2} damage');
      });
    });
  });
}
