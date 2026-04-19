import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'validation_issue_entry.dart';

part 'validation_result.g.dart';

/// Result of a validation operation.
///
/// Canonical state is [issues]: the structured list of validation findings.
/// [errors] / [warnings] / [allMessages] are kept as derived views for
/// consumers that only care about message strings.
@JsonSerializable(explicitToJson: true)
class ValidationResult {
  final bool isValid;
  final List<ValidationIssueEntry> issues;

  const ValidationResult({
    required this.isValid,
    this.issues = const [],
  });

  /// Error messages derived from [issues].
  List<String> get errors => issues
      .where((i) => i.severity == ValidationSeverity.error)
      .map((i) => i.message)
      .toList(growable: false);

  /// Warning messages derived from [issues].
  List<String> get warnings => issues
      .where((i) => i.severity == ValidationSeverity.warning)
      .map((i) => i.message)
      .toList(growable: false);

  /// All messages (errors followed by warnings in [issues] order).
  List<String> get allMessages =>
      issues.map((i) => i.message).toList(growable: false);

  bool get isInvalid => !isValid;
  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  String? get firstError => errors.isEmpty ? null : errors.first;

  ValidationResult combine(ValidationResult other) {
    return ValidationResult(
      isValid: isValid && other.isValid,
      issues: [...issues, ...other.issues],
    );
  }

  factory ValidationResult.success(
      {List<ValidationIssueEntry> issues = const []}) {
    return ValidationResult(isValid: true, issues: issues);
  }

  factory ValidationResult.failure({
    required List<ValidationIssueEntry> issues,
  }) {
    return ValidationResult(isValid: false, issues: issues);
  }

  ValidationResult copyWith({
    bool? isValid,
    List<ValidationIssueEntry>? issues,
  }) {
    return ValidationResult(
      isValid: isValid ?? this.isValid,
      issues: issues ?? this.issues,
    );
  }

  factory ValidationResult.fromJson(Map<String, dynamic> json) =>
      _$ValidationResultFromJson(json);
  Map<String, dynamic> toJson() => _$ValidationResultToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ValidationResult) return false;
    if (isValid != other.isValid) return false;
    if (issues.length != other.issues.length) return false;
    for (var i = 0; i < issues.length; i++) {
      if (issues[i] != other.issues[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(isValid, issues.length);

  @override
  String toString() =>
      'ValidationResult(isValid: $isValid, issues: ${issues.length})';
}

/// Field-specific validation result.
///
/// Used for form validation with multiple fields.
///
/// Example:
/// ```dart
/// final validation = FieldValidationResult({
///   'email': ['Email is required', 'Invalid format'],
///   'password': ['Password too short'],
/// });
///
/// if (!validation.isValid) {
///   print('Errors for email: ${validation.getFieldErrors('email')}');
/// }
/// ```
@JsonSerializable()
class FieldValidationResult {
  final Map<String, List<String>> fieldErrors;
  final List<String> globalErrors;
  final List<String> warnings;

  const FieldValidationResult({
    this.fieldErrors = const {},
    this.globalErrors = const [],
    this.warnings = const [],
  });

  /// Check if validation is valid (no errors)
  bool get isValid => fieldErrors.isEmpty && globalErrors.isEmpty;

  /// Check if validation failed
  bool get isInvalid => !isValid;

  /// Check if there are any errors
  bool get hasErrors => fieldErrors.isNotEmpty || globalErrors.isNotEmpty;

  /// Check if there are any warnings
  bool get hasWarnings => warnings.isNotEmpty;

  /// Check if a specific field has errors
  bool hasFieldError(String field) => fieldErrors.containsKey(field);

  /// Get errors for a specific field
  List<String> getFieldErrors(String field) => fieldErrors[field] ?? [];

  /// Get all error messages (global + field-specific)
  List<String> get allErrors {
    final errors = <String>[...globalErrors];
    for (final fieldErrorList in fieldErrors.values) {
      errors.addAll(fieldErrorList);
    }
    return errors;
  }

  /// Get total error count
  int get errorCount {
    int count = globalErrors.length;
    for (final errorList in fieldErrors.values) {
      count += errorList.length;
    }
    return count;
  }

  /// Add a field error
  FieldValidationResult addFieldError(String field, String error) {
    final newFieldErrors = Map<String, List<String>>.from(fieldErrors);
    newFieldErrors[field] = [...(newFieldErrors[field] ?? []), error];
    return copyWith(fieldErrors: newFieldErrors);
  }

  /// Add a global error
  FieldValidationResult addGlobalError(String error) {
    return copyWith(globalErrors: [...globalErrors, error]);
  }

  /// Add a warning
  FieldValidationResult addWarning(String warning) {
    return copyWith(warnings: [...warnings, warning]);
  }

  /// Create a successful validation result
  factory FieldValidationResult.success({List<String> warnings = const []}) {
    return FieldValidationResult(
      fieldErrors: const {},
      globalErrors: const [],
      warnings: warnings,
    );
  }

  /// Creates a copy with optional new values
  FieldValidationResult copyWith({
    Map<String, List<String>>? fieldErrors,
    List<String>? globalErrors,
    List<String>? warnings,
  }) {
    return FieldValidationResult(
      fieldErrors: fieldErrors ?? this.fieldErrors,
      globalErrors: globalErrors ?? this.globalErrors,
      warnings: warnings ?? this.warnings,
    );
  }

  factory FieldValidationResult.fromJson(Map<String, dynamic> json) =>
      _$FieldValidationResultFromJson(json);

  Map<String, dynamic> toJson() => _$FieldValidationResultToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FieldValidationResult) return false;
    if (fieldErrors.length != other.fieldErrors.length) return false;
    if (globalErrors.length != other.globalErrors.length) return false;
    if (warnings.length != other.warnings.length) return false;
    for (final key in fieldErrors.keys) {
      final errors1 = fieldErrors[key]!;
      final errors2 = other.fieldErrors[key];
      if (errors2 == null || errors1.length != errors2.length) return false;
      for (int i = 0; i < errors1.length; i++) {
        if (errors1[i] != errors2[i]) return false;
      }
    }
    for (int i = 0; i < globalErrors.length; i++) {
      if (globalErrors[i] != other.globalErrors[i]) return false;
    }
    for (int i = 0; i < warnings.length; i++) {
      if (warnings[i] != other.warnings[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(fieldErrors.length, globalErrors.length, warnings.length);

  @override
  String toString() =>
      'FieldValidationResult(fieldErrors: ${fieldErrors.length}, globalErrors: ${globalErrors.length}, warnings: ${warnings.length})';
}
