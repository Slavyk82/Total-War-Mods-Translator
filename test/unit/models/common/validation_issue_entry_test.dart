import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationIssueEntry', () {
    test('toJson produces canonical shape', () {
      const entry = ValidationIssueEntry(
        rule: ValidationRule.variables,
        severity: ValidationSeverity.error,
        message: 'Missing variables: {0}',
      );
      expect(entry.toJson(), {
        'rule': 'variables',
        'severity': 'error',
        'message': 'Missing variables: {0}',
      });
    });

    test('fromJson round-trips a known entry', () {
      final json = {
        'rule': 'markup',
        'severity': 'warning',
        'message': 'Source text has unbalanced markup tags',
      };
      final entry = ValidationIssueEntry.fromJson(json);
      expect(entry.rule, ValidationRule.markup);
      expect(entry.severity, ValidationSeverity.warning);
      expect(entry.message, 'Source text has unbalanced markup tags');
      expect(entry.toJson(), json);
    });

    test('fromJson surfaces an unknown rule as null', () {
      final entry = ValidationIssueEntry.fromJson({
        'rule': 'future_rule_code',
        'severity': 'warning',
        'message': 'unknown',
      });
      expect(entry.rule, isNull);
      expect(entry.severity, ValidationSeverity.warning);
      expect(entry.message, 'unknown');
    });

    test('equality is value-based', () {
      const a = ValidationIssueEntry(
        rule: ValidationRule.length,
        severity: ValidationSeverity.warning,
        message: 'Too long',
      );
      const b = ValidationIssueEntry(
        rule: ValidationRule.length,
        severity: ValidationSeverity.warning,
        message: 'Too long',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
