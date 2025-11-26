import 'package:twmt/models/common/service_exception.dart';

/// Base exception for LLM service errors
class LlmServiceException extends ServiceException {
  const LlmServiceException(
    super.message, {
    super.code,
    super.details,
    super.stackTrace,
  });
}

/// Exception for LLM provider-specific errors
class LlmProviderException extends LlmServiceException {
  final String providerCode;

  const LlmProviderException(
    super.message, {
    required this.providerCode,
    super.code,
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmProviderException(provider: $providerCode, message: $message, '
        'code: $code)';
  }
}

/// Exception for authentication errors (invalid API key)
class LlmAuthenticationException extends LlmProviderException {
  const LlmAuthenticationException(
    super.message, {
    required super.providerCode,
    super.code = 'AUTHENTICATION_ERROR',
    super.details,
    super.stackTrace,
  });
}

/// Exception for rate limit errors
class LlmRateLimitException extends LlmProviderException {
  /// Suggested retry delay in seconds (from provider headers)
  final int? retryAfterSeconds;

  /// Requests per minute limit
  final int? rateLimitRpm;

  /// Tokens per minute limit
  final int? rateLimitTpm;

  const LlmRateLimitException(
    super.message, {
    required super.providerCode,
    this.retryAfterSeconds,
    this.rateLimitRpm,
    this.rateLimitTpm,
    super.code = 'RATE_LIMIT_EXCEEDED',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmRateLimitException(provider: $providerCode, '
        'retryAfter: ${retryAfterSeconds}s, rpm: $rateLimitRpm, tpm: $rateLimitTpm, '
        'message: $message)';
  }
}

/// Exception for quota/billing errors
class LlmQuotaException extends LlmProviderException {
  const LlmQuotaException(
    super.message, {
    required super.providerCode,
    super.code = 'QUOTA_EXCEEDED',
    super.details,
    super.stackTrace,
  });
}

/// Exception for token limit errors (request too large)
class LlmTokenLimitException extends LlmProviderException {
  /// Estimated tokens in request
  final int? estimatedTokens;

  /// Maximum tokens allowed
  final int? maxTokens;

  const LlmTokenLimitException(
    super.message, {
    required super.providerCode,
    this.estimatedTokens,
    this.maxTokens,
    super.code = 'TOKEN_LIMIT_EXCEEDED',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmTokenLimitException(provider: $providerCode, '
        'estimated: $estimatedTokens, max: $maxTokens, message: $message)';
  }
}

/// Exception for invalid request errors
class LlmInvalidRequestException extends LlmProviderException {
  const LlmInvalidRequestException(
    super.message, {
    required super.providerCode,
    super.code = 'INVALID_REQUEST',
    super.details,
    super.stackTrace,
  });
}

/// Exception for network/timeout errors
class LlmNetworkException extends LlmProviderException {
  const LlmNetworkException(
    super.message, {
    required super.providerCode,
    super.code = 'NETWORK_ERROR',
    super.details,
    super.stackTrace,
  });
}

/// Exception for server errors (5xx)
class LlmServerException extends LlmProviderException {
  /// HTTP status code
  final int statusCode;

  const LlmServerException(
    super.message, {
    required super.providerCode,
    required this.statusCode,
    super.code = 'SERVER_ERROR',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmServerException(provider: $providerCode, '
        'statusCode: $statusCode, message: $message)';
  }
}

/// Exception for validation errors
class LlmValidationException extends LlmServiceException {
  /// Field that failed validation
  final String? field;

  /// Validation errors
  final Map<String, String>? validationErrors;

  const LlmValidationException(
    super.message, {
    this.field,
    this.validationErrors,
    super.code = 'VALIDATION_ERROR',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmValidationException(field: $field, message: $message, '
        'errors: $validationErrors)';
  }
}

/// Exception for response parsing errors
class LlmResponseParseException extends LlmProviderException {
  /// Raw response that failed to parse
  final String? rawResponse;

  const LlmResponseParseException(
    super.message, {
    required super.providerCode,
    this.rawResponse,
    super.code = 'RESPONSE_PARSE_ERROR',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmResponseParseException(provider: $providerCode, '
        'message: $message, rawResponse: ${rawResponse?.substring(0, rawResponse!.length > 100 ? 100 : rawResponse!.length)}...)';
  }
}

/// Exception for content filtered by provider's moderation system
///
/// This occurs when the LLM provider refuses to process content due to
/// content policy violations (e.g., OpenAI filtering mature game content).
/// Unlike other errors, this indicates the content itself is problematic,
/// not the request format or service availability.
class LlmContentFilteredException extends LlmProviderException {
  /// The source text(s) that triggered the filter
  final List<String>? filteredTexts;

  /// The finish reason from the API (e.g., "content_filter")
  final String? finishReason;

  const LlmContentFilteredException(
    super.message, {
    required super.providerCode,
    this.filteredTexts,
    this.finishReason,
    super.code = 'CONTENT_FILTERED',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmContentFilteredException(provider: $providerCode, '
        'finishReason: $finishReason, message: $message)';
  }
}

/// Exception for circuit breaker open state
class LlmCircuitBreakerException extends LlmProviderException {
  /// Time when circuit breaker will attempt to close (half-open)
  final DateTime? retryAfter;

  /// Original error that caused the circuit breaker to open
  final String? originalError;

  /// Type of the original error
  final String? originalErrorType;

  const LlmCircuitBreakerException(
    super.message, {
    required super.providerCode,
    this.retryAfter,
    this.originalError,
    this.originalErrorType,
    super.code = 'CIRCUIT_BREAKER_OPEN',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    final errorInfo = originalError != null
        ? ', originalError: $originalError'
        : '';
    return 'LlmCircuitBreakerException(provider: $providerCode, '
        'retryAfter: $retryAfter$errorInfo)';
  }
}

/// Exception for unsupported operations
class LlmUnsupportedOperationException extends LlmServiceException {
  final String operation;

  const LlmUnsupportedOperationException(
    super.message, {
    required this.operation,
    super.code = 'UNSUPPORTED_OPERATION',
    super.details,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'LlmUnsupportedOperationException(operation: $operation, '
        'message: $message)';
  }
}

/// Exception for configuration errors
class LlmConfigurationException extends LlmServiceException {
  const LlmConfigurationException(
    super.message, {
    super.code = 'CONFIGURATION_ERROR',
    super.details,
    super.stackTrace,
  });
}
