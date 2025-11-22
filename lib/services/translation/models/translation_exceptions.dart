import 'package:twmt/models/common/service_exception.dart';

/// Base exception for translation services
class TranslationServiceException extends ServiceException {
  const TranslationServiceException(
    super.message, {
    super.error,
    super.stackTrace,
  });
}

/// Exception thrown when translation orchestration fails
class TranslationOrchestrationException extends TranslationServiceException {
  final String? batchId;

  const TranslationOrchestrationException(
    super.message, {
    this.batchId,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final batchInfo = batchId != null ? ' (Batch: $batchId)' : '';
    return 'TranslationOrchestrationException: $message$batchInfo';
  }
}

/// Exception thrown when prompt building fails
class PromptBuildingException extends TranslationServiceException {
  final String? projectId;
  final String? languageCode;

  const PromptBuildingException(
    super.message, {
    this.projectId,
    this.languageCode,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final projectInfo = projectId != null ? ' (Project: $projectId)' : '';
    final langInfo = languageCode != null ? ', Language: $languageCode' : '';
    return 'PromptBuildingException: $message$projectInfo$langInfo';
  }
}

/// Exception thrown when validation fails
class ValidationException extends TranslationServiceException {
  final List<ValidationError> validationErrors;

  const ValidationException(
    super.message,
    this.validationErrors, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final errorList = validationErrors.map((e) => '  - ${e.field}: ${e.message}').join('\n');
    return 'ValidationException: $message\nValidation Errors:\n$errorList';
  }
}

/// Represents a single validation error
class ValidationError {
  final String field;
  final String message;
  final String? value;
  final ValidationSeverity severity;

  const ValidationError({
    required this.field,
    required this.message,
    this.value,
    this.severity = ValidationSeverity.error,
  });

  @override
  String toString() => '$field: $message${value != null ? ' (value: $value)' : ''}';
}

/// Severity level of validation error
enum ValidationSeverity {
  /// Warning - can continue but not recommended
  warning,

  /// Error - must be fixed
  error,

  /// Critical - severe issue
  critical,
}

/// Exception thrown when batch optimization fails
class BatchOptimizationException extends TranslationServiceException {
  final int? requestedBatchSize;
  final int? maxAllowedSize;

  const BatchOptimizationException(
    super.message, [
    String? details,
    this.requestedBatchSize,
    this.maxAllowedSize,
  ]) : super(error: details);

  @override
  String toString() {
    final sizeInfo = requestedBatchSize != null && maxAllowedSize != null
        ? ' (Requested: $requestedBatchSize, Max: $maxAllowedSize)'
        : '';
    return 'BatchOptimizationException: $message$sizeInfo';
  }
}

/// Exception thrown when translation batch is empty
class EmptyBatchException extends TranslationOrchestrationException {
  const EmptyBatchException(
    super.message, {
    super.batchId,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final batchInfo = batchId != null ? ' (Batch: $batchId)' : '';
    return 'EmptyBatchException: $message$batchInfo';
  }
}

/// Exception thrown when batch size exceeds limits
class BatchSizeExceededException extends TranslationServiceException {
  final int batchSize;
  final int maxSize;
  final String? providerCode;

  const BatchSizeExceededException(
    super.message,
    this.batchSize,
    this.maxSize, {
    this.providerCode,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final providerInfo = providerCode != null ? ' for $providerCode' : '';
    return 'BatchSizeExceededException: $message$providerInfo '
        '(Batch size: $batchSize, Max: $maxSize)';
  }
}

/// Exception thrown when translation is paused
class TranslationPausedException extends TranslationServiceException {
  final String batchId;

  const TranslationPausedException(
    super.message,
    this.batchId, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'TranslationPausedException: $message (Batch: $batchId)';
  }
}

/// Exception thrown when translation is cancelled
class TranslationCancelledException extends TranslationServiceException {
  final String batchId;

  const TranslationCancelledException(
    super.message,
    this.batchId, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'TranslationCancelledException: $message (Batch: $batchId)';
  }
}

/// Exception thrown when context is invalid or missing
class InvalidContextException extends TranslationServiceException {
  final String? contextId;
  final String? missingField;

  const InvalidContextException(
    super.message, {
    this.contextId,
    this.missingField,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    final contextInfo = contextId != null ? ' (Context: $contextId)' : '';
    final fieldInfo = missingField != null ? ', Missing: $missingField' : '';
    return 'InvalidContextException: $message$contextInfo$fieldInfo';
  }
}

/// Exception thrown when partial translation batch fails
class PartialTranslationException extends TranslationServiceException {
  final String batchId;
  final int successfulCount;
  final int failedCount;
  final List<String> failedUnitIds;

  const PartialTranslationException(
    super.message,
    this.batchId,
    this.successfulCount,
    this.failedCount,
    this.failedUnitIds, {
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'PartialTranslationException: $message (Batch: $batchId)\n'
        'Successful: $successfulCount, Failed: $failedCount\n'
        'Failed units: ${failedUnitIds.take(5).join(', ')}${failedUnitIds.length > 5 ? '...' : ''}';
  }
}
