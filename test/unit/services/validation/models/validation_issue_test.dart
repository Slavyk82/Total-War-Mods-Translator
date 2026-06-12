import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';

ValidationIssue _issue(ValidationSeverity severity) => ValidationIssue(
      type: ValidationIssueType.emptyTranslation,
      severity: severity,
      description: 'empty value',
      autoFixable: true,
      autoFixValue: 'x',
    );

void main() {
  group('severity getters + iconName', () {
    test('isError / isWarning / isInfo', () {
      expect(_issue(ValidationSeverity.error).isError, isTrue);
      expect(_issue(ValidationSeverity.warning).isWarning, isTrue);
      expect(_issue(ValidationSeverity.info).isInfo, isTrue);
      expect(_issue(ValidationSeverity.info).isError, isFalse);
    });

    test('iconName maps each severity', () {
      expect(_issue(ValidationSeverity.error).iconName, 'error_circle');
      expect(_issue(ValidationSeverity.warning).iconName, 'warning');
      expect(_issue(ValidationSeverity.info).iconName, 'info');
    });
  });

  group('copyWith / equality / json', () {
    test('copyWith overrides only the targeted field', () {
      final i = _issue(ValidationSeverity.error);
      expect(i.copyWith(description: 'new').description, 'new');
      expect(i.copyWith(description: 'new').type,
          ValidationIssueType.emptyTranslation);
    });

    test('value equality + hashCode', () {
      expect(_issue(ValidationSeverity.error),
          equals(_issue(ValidationSeverity.error)));
      expect(_issue(ValidationSeverity.error).hashCode,
          _issue(ValidationSeverity.error).hashCode);
    });

    test('json round-trip', () {
      final restored =
          ValidationIssue.fromJson(_issue(ValidationSeverity.warning).toJson());
      expect(restored.type, ValidationIssueType.emptyTranslation);
      expect(restored.severity, ValidationSeverity.warning);
      expect(restored.autoFixable, isTrue);
      expect(restored.autoFixValue, 'x');
    });
  });
}
