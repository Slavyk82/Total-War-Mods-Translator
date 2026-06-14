import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/models/common/validation_result.dart';
import 'package:twmt/models/common/validation_rule.dart';

ValidationIssueEntry _error(String message,
        {ValidationRule? rule = ValidationRule.completeness}) =>
    ValidationIssueEntry(
      rule: rule,
      severity: ValidationSeverity.error,
      message: message,
    );

ValidationIssueEntry _warning(String message,
        {ValidationRule? rule = ValidationRule.length}) =>
    ValidationIssueEntry(
      rule: rule,
      severity: ValidationSeverity.warning,
      message: message,
    );

void main() {
  group('ValidationResult', () {
    test('default constructor uses empty issues', () {
      const result = ValidationResult(isValid: true);
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.allMessages, isEmpty);
    });

    test('errors getter filters error-severity issues', () {
      final result = ValidationResult(
        isValid: false,
        issues: [
          _error('e1'),
          _warning('w1'),
          _error('e2'),
        ],
      );
      expect(result.errors, ['e1', 'e2']);
    });

    test('warnings getter filters warning-severity issues', () {
      final result = ValidationResult(
        isValid: true,
        issues: [
          _error('e1'),
          _warning('w1'),
          _warning('w2'),
        ],
      );
      expect(result.warnings, ['w1', 'w2']);
    });

    test('allMessages preserves issue order', () {
      final result = ValidationResult(
        isValid: false,
        issues: [_error('e1'), _warning('w1'), _error('e2')],
      );
      expect(result.allMessages, ['e1', 'w1', 'e2']);
    });

    test('isInvalid is inverse of isValid', () {
      expect(const ValidationResult(isValid: true).isInvalid, isFalse);
      expect(const ValidationResult(isValid: false).isInvalid, isTrue);
    });

    test('hasErrors true only when error issues present', () {
      expect(const ValidationResult(isValid: true).hasErrors, isFalse);
      expect(
        ValidationResult(isValid: true, issues: [_warning('w')]).hasErrors,
        isFalse,
      );
      expect(
        ValidationResult(isValid: false, issues: [_error('e')]).hasErrors,
        isTrue,
      );
    });

    test('hasWarnings true only when warning issues present', () {
      expect(const ValidationResult(isValid: true).hasWarnings, isFalse);
      expect(
        ValidationResult(isValid: false, issues: [_error('e')]).hasWarnings,
        isFalse,
      );
      expect(
        ValidationResult(isValid: true, issues: [_warning('w')]).hasWarnings,
        isTrue,
      );
    });

    test('firstError returns null when no errors, else first error', () {
      expect(const ValidationResult(isValid: true).firstError, isNull);
      expect(
        ValidationResult(isValid: true, issues: [_warning('w')]).firstError,
        isNull,
      );
      expect(
        ValidationResult(
          isValid: false,
          issues: [_error('first'), _error('second')],
        ).firstError,
        'first',
      );
    });

    test('combine merges issues and ANDs validity (valid + valid)', () {
      final a = ValidationResult(isValid: true, issues: [_warning('w1')]);
      final b = ValidationResult(isValid: true, issues: [_warning('w2')]);
      final combined = a.combine(b);
      expect(combined.isValid, isTrue);
      expect(combined.allMessages, ['w1', 'w2']);
    });

    test('combine yields invalid when either side invalid', () {
      final valid = ValidationResult(isValid: true, issues: [_warning('w')]);
      final invalid = ValidationResult(isValid: false, issues: [_error('e')]);
      expect(valid.combine(invalid).isValid, isFalse);
      expect(invalid.combine(valid).isValid, isFalse);
    });

    test('success factory defaults and with issues', () {
      final empty = ValidationResult.success();
      expect(empty.isValid, isTrue);
      expect(empty.issues, isEmpty);

      final withWarn = ValidationResult.success(issues: [_warning('w')]);
      expect(withWarn.isValid, isTrue);
      expect(withWarn.warnings, ['w']);
    });

    test('failure factory sets isValid false', () {
      final result = ValidationResult.failure(issues: [_error('e')]);
      expect(result.isValid, isFalse);
      expect(result.errors, ['e']);
    });

    test('copyWith overrides each field independently', () {
      final original = ValidationResult(
        isValid: true,
        issues: [_warning('w')],
      );
      final unchanged = original.copyWith();
      expect(unchanged.isValid, isTrue);
      expect(unchanged.issues, original.issues);

      final newValid = original.copyWith(isValid: false);
      expect(newValid.isValid, isFalse);
      expect(newValid.issues, original.issues);

      final newIssues = original.copyWith(issues: [_error('e')]);
      expect(newIssues.isValid, isTrue);
      expect(newIssues.errors, ['e']);
    });

    test('toJson / fromJson round-trip with issues', () {
      final result = ValidationResult(
        isValid: false,
        issues: [
          ValidationIssueEntry(
            rule: ValidationRule.encoding,
            severity: ValidationSeverity.critical,
            message: 'bad encoding',
          ),
          _warning('len warning', rule: ValidationRule.length),
        ],
      );
      final json = result.toJson();
      final decoded = ValidationResult.fromJson(json);
      expect(decoded, result);
      expect(decoded.isValid, isFalse);
      expect(decoded.issues.length, 2);
      expect(decoded.issues.first.rule, ValidationRule.encoding);
      expect(decoded.issues.first.severity, ValidationSeverity.critical);
    });

    test('toJson / fromJson round-trip with empty/default issues', () {
      const result = ValidationResult(isValid: true);
      final decoded = ValidationResult.fromJson(result.toJson());
      expect(decoded, result);
      expect(decoded.issues, isEmpty);
    });

    test('equality: identical, equal, and differing instances', () {
      final a = ValidationResult(isValid: true, issues: [_warning('w')]);
      final b = ValidationResult(isValid: true, issues: [_warning('w')]);
      final cDifferentValid =
          ValidationResult(isValid: false, issues: [_warning('w')]);
      final dDifferentLen = ValidationResult(
        isValid: true,
        issues: [_warning('w'), _warning('w2')],
      );
      final eDifferentEntry =
          ValidationResult(isValid: true, issues: [_warning('different')]);

      // identical
      // ignore: prefer_const_constructors
      expect(a == a, isTrue);
      // equal contents
      expect(a, b);
      // differing isValid
      expect(a == cDifferentValid, isFalse);
      // differing issue count
      expect(a == dDifferentLen, isFalse);
      // same length, differing entry
      expect(a == eDifferentEntry, isFalse);
      // different type
      // ignore: unrelated_type_equality_checks
      expect(a == 'not a result', isFalse);
    });

    test('hashCode equal for equal instances', () {
      final a = ValidationResult(isValid: true, issues: [_warning('w')]);
      final b = ValidationResult(isValid: true, issues: [_warning('w')]);
      expect(a.hashCode, b.hashCode);
    });

    test('toString summarizes validity and issue count', () {
      final result = ValidationResult(
        isValid: false,
        issues: [_error('e'), _warning('w')],
      );
      expect(result.toString(),
          'ValidationResult(isValid: false, issues: 2)');
    });
  });

  group('FieldValidationResult', () {
    test('default constructor is valid with empty collections', () {
      const result = FieldValidationResult();
      expect(result.isValid, isTrue);
      expect(result.isInvalid, isFalse);
      expect(result.hasErrors, isFalse);
      expect(result.hasWarnings, isFalse);
      expect(result.fieldErrors, isEmpty);
      expect(result.globalErrors, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.allErrors, isEmpty);
      expect(result.errorCount, 0);
    });

    test('isValid false when field errors present', () {
      const result = FieldValidationResult(fieldErrors: {
        'email': ['required'],
      });
      expect(result.isValid, isFalse);
      expect(result.isInvalid, isTrue);
      expect(result.hasErrors, isTrue);
    });

    test('isValid false when global errors present', () {
      const result = FieldValidationResult(globalErrors: ['boom']);
      expect(result.isValid, isFalse);
      expect(result.hasErrors, isTrue);
    });

    test('warnings do not affect validity', () {
      const result = FieldValidationResult(warnings: ['careful']);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
      expect(result.hasWarnings, isTrue);
    });

    test('hasFieldError checks key presence', () {
      const result = FieldValidationResult(fieldErrors: {
        'email': ['required'],
      });
      expect(result.hasFieldError('email'), isTrue);
      expect(result.hasFieldError('password'), isFalse);
    });

    test('getFieldErrors returns list or empty default', () {
      const result = FieldValidationResult(fieldErrors: {
        'email': ['required', 'invalid'],
      });
      expect(result.getFieldErrors('email'), ['required', 'invalid']);
      expect(result.getFieldErrors('missing'), isEmpty);
    });

    test('allErrors combines global then field errors', () {
      const result = FieldValidationResult(
        globalErrors: ['g1'],
        fieldErrors: {
          'email': ['e1', 'e2'],
          'password': ['p1'],
        },
      );
      expect(result.allErrors, containsAll(['g1', 'e1', 'e2', 'p1']));
      expect(result.allErrors.first, 'g1');
      expect(result.allErrors.length, 4);
    });

    test('errorCount sums global and field errors', () {
      const result = FieldValidationResult(
        globalErrors: ['g1', 'g2'],
        fieldErrors: {
          'email': ['e1'],
          'password': ['p1', 'p2'],
        },
      );
      expect(result.errorCount, 5);
    });

    test('addFieldError appends to existing and creates new', () {
      const start = FieldValidationResult(fieldErrors: {
        'email': ['required'],
      });
      final appended = start.addFieldError('email', 'invalid');
      expect(appended.getFieldErrors('email'), ['required', 'invalid']);

      final created = start.addFieldError('password', 'too short');
      expect(created.getFieldErrors('password'), ['too short']);
      // original is unchanged (immutability)
      expect(start.getFieldErrors('email'), ['required']);
    });

    test('addGlobalError appends a global error', () {
      const start = FieldValidationResult(globalErrors: ['g1']);
      final result = start.addGlobalError('g2');
      expect(result.globalErrors, ['g1', 'g2']);
    });

    test('addWarning appends a warning', () {
      const start = FieldValidationResult(warnings: ['w1']);
      final result = start.addWarning('w2');
      expect(result.warnings, ['w1', 'w2']);
    });

    test('success factory is valid with optional warnings', () {
      final empty = FieldValidationResult.success();
      expect(empty.isValid, isTrue);
      expect(empty.warnings, isEmpty);

      final withWarn = FieldValidationResult.success(warnings: ['w']);
      expect(withWarn.isValid, isTrue);
      expect(withWarn.warnings, ['w']);
    });

    test('copyWith overrides each field independently', () {
      const original = FieldValidationResult(
        fieldErrors: {
          'email': ['required'],
        },
        globalErrors: ['g'],
        warnings: ['w'],
      );
      final unchanged = original.copyWith();
      expect(unchanged.fieldErrors, original.fieldErrors);
      expect(unchanged.globalErrors, original.globalErrors);
      expect(unchanged.warnings, original.warnings);

      final newFields = original.copyWith(fieldErrors: const {});
      expect(newFields.fieldErrors, isEmpty);
      expect(newFields.globalErrors, ['g']);

      final newGlobal = original.copyWith(globalErrors: const []);
      expect(newGlobal.globalErrors, isEmpty);

      final newWarn = original.copyWith(warnings: const ['x']);
      expect(newWarn.warnings, ['x']);
    });

    test('toJson / fromJson round-trip with populated data', () {
      const result = FieldValidationResult(
        fieldErrors: {
          'email': ['required', 'invalid'],
          'password': ['short'],
        },
        globalErrors: ['form invalid'],
        warnings: ['weak password'],
      );
      final decoded = FieldValidationResult.fromJson(result.toJson());
      expect(decoded, result);
      expect(decoded.getFieldErrors('email'), ['required', 'invalid']);
      expect(decoded.globalErrors, ['form invalid']);
      expect(decoded.warnings, ['weak password']);
    });

    test('toJson / fromJson round-trip with defaults/empties', () {
      const result = FieldValidationResult();
      final decoded = FieldValidationResult.fromJson(result.toJson());
      expect(decoded, result);
      expect(decoded.isValid, isTrue);
    });

    test('equality covers all branches', () {
      const a = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      const equal = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );

      // identical
      // ignore: prefer_const_constructors
      expect(a == a, isTrue);
      // equal contents
      expect(a, equal);
      // different type
      // ignore: unrelated_type_equality_checks
      expect(a == 'nope', isFalse);

      // differing fieldErrors length
      const diffFieldLen = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
          'password': ['p1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      expect(a == diffFieldLen, isFalse);

      // differing globalErrors length
      const diffGlobalLen = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1', 'g2'],
        warnings: ['w1'],
      );
      expect(a == diffGlobalLen, isFalse);

      // differing warnings length
      const diffWarnLen = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1', 'w2'],
      );
      expect(a == diffWarnLen, isFalse);

      // same field-key but missing key on other side
      const diffFieldKey = FieldValidationResult(
        fieldErrors: {
          'password': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      expect(a == diffFieldKey, isFalse);

      // same key, differing inner list length
      const diffInnerLen = FieldValidationResult(
        fieldErrors: {
          'email': ['e1', 'e2'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      expect(a == diffInnerLen, isFalse);

      // same key + length, differing inner value
      const diffInnerVal = FieldValidationResult(
        fieldErrors: {
          'email': ['other'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      expect(a == diffInnerVal, isFalse);

      // differing global value (same length)
      const diffGlobalVal = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['other'],
        warnings: ['w1'],
      );
      expect(a == diffGlobalVal, isFalse);

      // differing warning value (same length)
      const diffWarnVal = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['other'],
      );
      expect(a == diffWarnVal, isFalse);
    });

    test('hashCode equal for equal instances', () {
      const a = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      const b = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1'],
        warnings: ['w1'],
      );
      expect(a.hashCode, b.hashCode);
    });

    test('toString summarizes counts', () {
      const result = FieldValidationResult(
        fieldErrors: {
          'email': ['e1'],
        },
        globalErrors: ['g1', 'g2'],
        warnings: ['w1'],
      );
      expect(
        result.toString(),
        'FieldValidationResult(fieldErrors: 1, globalErrors: 2, warnings: 1)',
      );
    });
  });
}
