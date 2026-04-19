import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationRule.label', () {
    test('humanises every rule', () {
      const expected = {
        ValidationRule.completeness: 'Completeness',
        ValidationRule.length: 'Length',
        ValidationRule.variables: 'Variables',
        ValidationRule.markup: 'Markup tags',
        ValidationRule.encoding: 'Encoding',
        ValidationRule.glossary: 'Glossary',
        ValidationRule.security: 'Security',
        ValidationRule.truncation: 'Truncation',
        ValidationRule.repeatedWord: 'Repeated word',
        ValidationRule.endPunctuation: 'Punctuation',
        ValidationRule.numbers: 'Numbers',
      };
      for (final entry in expected.entries) {
        expect(entry.key.label, entry.value,
            reason: 'Label mismatch for ${entry.key}');
      }
      // Guard: if the enum grows, this will fail and force the label update.
      expect(ValidationRule.values.length, expected.length);
    });

    test('codeName is the enum name for JSON persistence', () {
      expect(ValidationRule.variables.codeName, 'variables');
      expect(ValidationRule.repeatedWord.codeName, 'repeatedWord');
    });

    test('fromCodeName round-trips every value', () {
      for (final r in ValidationRule.values) {
        expect(ValidationRule.fromCodeName(r.codeName), r);
      }
    });

    test('fromCodeName returns null for unknown values', () {
      expect(ValidationRule.fromCodeName('no_such_rule'), isNull);
    });
  });
}
