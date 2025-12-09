import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Handles retry logic for LLM translation requests.
///
/// Responsibilities:
/// - Retry on transient errors (429, 529, network errors)
/// - Exponential backoff with configurable delays
/// - Respect provider-suggested retry-after delays
class LlmRetryHandler {
  final ILlmService _llmService;
  final LoggingService _logger;

  LlmRetryHandler({
    required ILlmService llmService,
    required LoggingService logger,
  })  : _llmService = llmService,
        _logger = logger;

  /// Translate batch with automatic retry for transient errors.
  ///
  /// Retries on:
  /// - LlmServerException (5xx errors including 529 Overloaded)
  /// - LlmRateLimitException (429 Too Many Requests)
  /// - LlmNetworkException (connection errors)
  ///
  /// Uses exponential backoff: 2s, 4s, 8s...
  Future<Result<LlmResponse, LlmServiceException>> translateWithRetry({
    required LlmRequest llmRequest,
    required String batchId,
    required dynamic dioCancelToken,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    LlmServiceException? lastError;

    while (attempt <= maxRetries) {
      final result = await _llmService.translateBatch(
        llmRequest,
        cancelToken: dioCancelToken,
      );

      if (result.isOk) {
        return result;
      }

      final error = result.unwrapErr();
      lastError = error;

      // Check if error is retryable
      final isRetryable = error is LlmServerException ||
          error is LlmRateLimitException ||
          error is LlmNetworkException;

      if (!isRetryable || attempt >= maxRetries) {
        if (attempt >= maxRetries) {
          _logger.error(
            'All retries exhausted for batch $batchId: ${error.message}',
            error,
            error.stackTrace,
          );
        }
        return result;
      }

      // Calculate delay with exponential backoff
      int delaySeconds;
      if (error is LlmRateLimitException && error.retryAfterSeconds != null) {
        // Use provider-suggested delay if available
        delaySeconds = error.retryAfterSeconds!;
      } else {
        // Exponential backoff: 2^attempt * 2 seconds (2s, 4s, 8s)
        delaySeconds = (1 << attempt) * 2;
      }

      _logger.warning(
        'Retry ${attempt + 1}/$maxRetries after ${delaySeconds}s (${error.runtimeType}): ${error.message}',
      );

      await Future.delayed(Duration(seconds: delaySeconds));
      attempt++;
    }

    // Should not reach here, but return last error if it does
    return Err(lastError!);
  }
}
