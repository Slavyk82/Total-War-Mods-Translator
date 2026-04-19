import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/models/common/validation_result.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

void main() {
  group('ValidationResult.issues', () {
    test('derives errors / warnings / allMessages from issues', () {
      const result = ValidationResult(
        isValid: false,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.variables,
            severity: ValidationSeverity.error,
            message: 'Missing variable {0}',
          ),
          ValidationIssueEntry(
            rule: ValidationRule.length,
            severity: ValidationSeverity.warning,
            message: 'Length differs',
          ),
        ],
      );
      expect(result.errors, ['Missing variable {0}']);
      expect(result.warnings, ['Length differs']);
      expect(result.allMessages, ['Missing variable {0}', 'Length differs']);
      expect(result.hasErrors, isTrue);
      expect(result.hasWarnings, isTrue);
    });

    test('combine concatenates issues from both results', () {
      const a = ValidationResult(
        isValid: false,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.encoding,
            severity: ValidationSeverity.error,
            message: 'enc',
          ),
        ],
      );
      const b = ValidationResult(
        isValid: true,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.length,
            severity: ValidationSeverity.warning,
            message: 'len',
          ),
        ],
      );
      final c = a.combine(b);
      expect(c.issues.length, 2);
      expect(c.issues.map((i) => i.rule),
          [ValidationRule.encoding, ValidationRule.length]);
      expect(c.isValid, isFalse);
    });

    test('success factory produces an empty-issues, valid result', () {
      final r = ValidationResult.success();
      expect(r.isValid, isTrue);
      expect(r.issues, isEmpty);
      expect(r.allMessages, isEmpty);
    });
  });
}
