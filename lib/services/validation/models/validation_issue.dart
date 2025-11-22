import 'package:json_annotation/json_annotation.dart';

part 'validation_issue.g.dart';

/// Severity level of a validation issue
enum ValidationSeverity {
  error, // Blocks validation - must be fixed
  warning, // Should be reviewed but doesn't block
  info, // Informational only
}

/// Type of validation check that failed
enum ValidationIssueType {
  emptyTranslation,
  lengthDifference,
  missingVariables,
  whitespaceIssue,
  punctuationMismatch,
  caseMismatch,
  missingNumbers,
}

/// Represents a single validation issue found in a translation
@JsonSerializable()
class ValidationIssue {
  /// Type of issue
  final ValidationIssueType type;

  /// Severity level
  final ValidationSeverity severity;

  /// Human-readable description of the issue
  final String description;

  /// Optional suggestion for fixing the issue
  final String? suggestion;

  /// Whether this issue can be automatically fixed
  final bool autoFixable;

  /// The auto-fix value if available
  final String? autoFixValue;

  /// Additional metadata about the issue
  final Map<String, dynamic>? metadata;

  const ValidationIssue({
    required this.type,
    required this.severity,
    required this.description,
    this.suggestion,
    this.autoFixable = false,
    this.autoFixValue,
    this.metadata,
  });

  /// Returns true if this is an error (blocks validation)
  bool get isError => severity == ValidationSeverity.error;

  /// Returns true if this is a warning
  bool get isWarning => severity == ValidationSeverity.warning;

  /// Returns true if this is informational
  bool get isInfo => severity == ValidationSeverity.info;

  /// Returns the icon name for this severity
  String get iconName {
    switch (severity) {
      case ValidationSeverity.error:
        return 'error_circle';
      case ValidationSeverity.warning:
        return 'warning';
      case ValidationSeverity.info:
        return 'info';
    }
  }

  ValidationIssue copyWith({
    ValidationIssueType? type,
    ValidationSeverity? severity,
    String? description,
    String? suggestion,
    bool? autoFixable,
    String? autoFixValue,
    Map<String, dynamic>? metadata,
  }) {
    return ValidationIssue(
      type: type ?? this.type,
      severity: severity ?? this.severity,
      description: description ?? this.description,
      suggestion: suggestion ?? this.suggestion,
      autoFixable: autoFixable ?? this.autoFixable,
      autoFixValue: autoFixValue ?? this.autoFixValue,
      metadata: metadata ?? this.metadata,
    );
  }

  factory ValidationIssue.fromJson(Map<String, dynamic> json) =>
      _$ValidationIssueFromJson(json);

  Map<String, dynamic> toJson() => _$ValidationIssueToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ValidationIssue &&
        other.type == type &&
        other.severity == severity &&
        other.description == description &&
        other.suggestion == suggestion &&
        other.autoFixable == autoFixable &&
        other.autoFixValue == autoFixValue;
  }

  @override
  int get hashCode =>
      type.hashCode ^
      severity.hashCode ^
      description.hashCode ^
      suggestion.hashCode ^
      autoFixable.hashCode ^
      autoFixValue.hashCode;

  @override
  String toString() =>
      'ValidationIssue(type: $type, severity: $severity, description: $description)';
}
