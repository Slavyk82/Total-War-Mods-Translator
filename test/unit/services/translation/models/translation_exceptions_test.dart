import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationError', () {
    test('stores the rule identifier', () {
      const error = ValidationError(
        rule: ValidationRule.variables,
        field: 'unit.title',
        message: 'Missing variables: {0}',
        severity: ValidationSeverity.error,
      );
      expect(error.rule, ValidationRule.variables);
      expect(error.severity, ValidationSeverity.error);
      expect(error.message, 'Missing variables: {0}');
      expect(error.field, 'unit.title');
    });

    test('toString includes the rule name', () {
      const error = ValidationError(
        rule: ValidationRule.length,
        field: 'unit.body',
        message: 'Translation length differs significantly',
      );
      expect(error.toString(), contains('length'));
      expect(error.toString(), contains('Translation length'));
    });
  });
}
