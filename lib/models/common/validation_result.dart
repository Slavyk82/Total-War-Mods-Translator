import 'package:json_annotation/json_annotation.dart';

part 'validation_result.g.dart';

/// Result of a validation operation.
///
/// Contains validation status, errors, and warnings.
///
/// Example:
/// ```dart
/// ValidationResult validate(String email) {
///   final errors = <String>[];
///   final warnings = <String>[];
///
///   if (email.isEmpty) {
///     errors.add('Email is required');
///   } else if (!email.contains('@')) {
///     errors.add('Invalid email format');
///   }
///
///   if (email.endsWith('.test')) {
///     warnings.add('Test email detected');
///   }
///
///   return ValidationResult(
///     isValid: errors.isEmpty,
///     errors: errors,
///     warnings: warnings,
///   );
/// }
/// ```
@JsonSerializable()
class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  /// Check if validation failed
  bool get isInvalid => !isValid;

  /// Check if there are any errors
  bool get hasErrors => errors.isNotEmpty;

  /// Check if there are any warnings
  bool get hasWarnings => warnings.isNotEmpty;

  /// Get the first error message, or null if no errors
  String? get firstError => errors.isEmpty ? null : errors.first;

  /// Get all messages (errors + warnings)
  List<String> get allMessages => [...errors, ...warnings];

  /// Combine with another validation result
  ValidationResult combine(ValidationResult other) {
    return ValidationResult(
      isValid: isValid && other.isValid,
      errors: [...errors, ...other.errors],
      warnings: [...warnings, ...other.warnings],
    );
  }

  /// Create a successful validation result
  factory ValidationResult.success({List<String> warnings = const []}) {
    return ValidationResult(
      isValid: true,
      errors: const [],
      warnings: warnings,
    );
  }

  /// Create a failed validation result
  factory ValidationResult.failure({
    required List<String> errors,
    List<String> warnings = const [],
  }) {
    return ValidationResult(
      isValid: false,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Create from a single error message
  factory ValidationResult.error(String error) {
    return ValidationResult(
      isValid: false,
      errors: [error],
      warnings: const [],
    );
  }

  /// Creates a copy with optional new values
  ValidationResult copyWith({
    bool? isValid,
    List<String>? errors,
    List<String>? warnings,
  }) {
    return ValidationResult(
      isValid: isValid ?? this.isValid,
      errors: errors ?? this.errors,
      warnings: warnings ?? this.warnings,
    );
  }

  factory ValidationResult.fromJson(Map<String, dynamic> json) =>
      _$ValidationResultFromJson(json);

  Map<String, dynamic> toJson() => _$ValidationResultToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ValidationResult) return false;
    if (errors.length != other.errors.length) return false;
    if (warnings.length != other.warnings.length) return false;
    for (int i = 0; i < errors.length; i++) {
      if (errors[i] != other.errors[i]) return false;
    }
    for (int i = 0; i < warnings.length; i++) {
      if (warnings[i] != other.warnings[i]) return false;
    }
    return isValid == other.isValid;
  }

  @override
  int get hashCode =>
      Object.hash(isValid, errors.length, warnings.length);

  @override
  String toString() =>
      'ValidationResult(isValid: $isValid, errors: ${errors.length}, warnings: ${warnings.length})';
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
