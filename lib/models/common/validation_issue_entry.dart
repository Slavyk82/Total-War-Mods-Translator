import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';

/// Structured representation of a single validation issue, persisted in
/// `translation_versions.validation_issues` as JSON.
///
/// `rule` is nullable on decode only: JSON written by a future version may
/// reference a rule code this binary does not know yet. In that case the
/// caller is expected to surface the entry with a "legacy" / "unknown"
/// label rather than discard it.
class ValidationIssueEntry {
  final ValidationRule? rule;
  final ValidationSeverity severity;
  final String message;

  const ValidationIssueEntry({
    required this.rule,
    required this.severity,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'rule': rule?.codeName,
        'severity': severity.name,
        'message': message,
      };

  factory ValidationIssueEntry.fromJson(Map<String, dynamic> json) {
    final ruleCode = json['rule'] as String?;
    final severityCode = (json['severity'] as String?) ?? 'warning';
    return ValidationIssueEntry(
      rule: ruleCode == null ? null : ValidationRule.fromCodeName(ruleCode),
      severity: ValidationSeverity.values.firstWhere(
        (s) => s.name == severityCode,
        orElse: () => ValidationSeverity.warning,
      ),
      message: (json['message'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValidationIssueEntry &&
          other.rule == rule &&
          other.severity == severity &&
          other.message == message);

  @override
  int get hashCode => Object.hash(rule, severity, message);

  @override
  String toString() =>
      'ValidationIssueEntry(rule: ${rule?.codeName ?? '<unknown>'}, '
      'severity: ${severity.name}, message: $message)';
}
