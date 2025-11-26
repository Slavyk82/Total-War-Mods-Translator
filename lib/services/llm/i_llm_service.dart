import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';

/// High-level LLM service interface
///
/// This service orchestrates LLM providers, handles rate limiting,
/// circuit breaking, and provides a unified interface for translation.
abstract class ILlmService {
  /// Translate a batch of texts using the active global provider
  ///
  /// This method:
  /// - Selects the active provider from settings
  /// - Applies rate limiting
  /// - Uses circuit breaker for fault tolerance
  /// - Handles retries on transient failures
  /// - Tracks token usage
  ///
  /// [request] - Translation request with texts and context
  /// [cancelToken] - Optional token to cancel the request
  ///
  /// Returns [Ok(LlmResponse)] on success or [Err(LlmServiceException)] on failure
  Future<Result<LlmResponse, LlmServiceException>> translateBatch(
    LlmRequest request, {
    CancelToken? cancelToken,
  });

  /// Translate multiple batches in parallel
  ///
  /// Respects rate limits and processes batches concurrently up to [maxParallel].
  /// Yields results as they complete.
  ///
  /// [requests] - List of translation requests
  /// [maxParallel] - Maximum concurrent requests (1-10, default 3)
  ///
  /// Returns stream of results (success or error for each batch)
  Stream<Result<BatchTranslationResult, LlmServiceException>>
      translateBatchesParallel(
    List<LlmRequest> requests, {
    int maxParallel = 3,
  });

  /// Estimate tokens for a request
  ///
  /// Calculates total tokens including:
  /// - System prompt
  /// - Game/project context
  /// - Few-shot examples
  /// - Input texts
  /// - Estimated output (1.0x-1.5x input based on language)
  ///
  /// [request] - Translation request to estimate
  ///
  /// Returns [Ok(estimatedTokens)] or [Err(LlmServiceException)]
  Future<Result<int, LlmServiceException>> estimateTokens(
    LlmRequest request,
  );

  /// Validate batch size against token limits
  ///
  /// Checks if the request fits within provider's token limit.
  ///
  /// [request] - Translation request to validate
  ///
  /// Returns [Ok(true)] if valid, [Ok(false)] if too large,
  /// or [Err(LlmServiceException)] on error
  Future<Result<bool, LlmServiceException>> validateBatchSize(
    LlmRequest request,
  );

  /// Adjust batch size automatically if too large
  ///
  /// Splits oversized batches into multiple smaller batches
  /// that fit within token limits.
  ///
  /// [request] - Translation request to adjust
  ///
  /// Returns [Ok(List<LlmRequest>)] with adjusted batches
  /// or [Err(LlmServiceException)] on error
  Future<Result<List<LlmRequest>, LlmServiceException>> adjustBatchSize(
    LlmRequest request,
  );

  /// Validate API key for a specific provider
  ///
  /// Makes a minimal API call to verify the key is valid.
  ///
  /// [providerCode] - Provider to validate ("anthropic", "openai", "deepl")
  /// [apiKey] - API key to validate
  /// [model] - Model to use for validation (required for LLM providers, ignored by DeepL)
  ///
  /// Returns [Ok(true)] if valid or [Err(LlmServiceException)] if invalid
  Future<Result<bool, LlmServiceException>> validateApiKey(
    String providerCode,
    String apiKey, {
    String? model,
  });

  /// Get active provider code from settings
  ///
  /// Returns provider code (e.g., "anthropic", "openai", "deepl")
  Future<String> getActiveProviderCode();

  /// Set active provider
  ///
  /// Updates the global active provider setting.
  ///
  /// [providerCode] - Provider code to activate
  ///
  /// Returns [Ok(void)] or [Err(LlmServiceException)]
  Future<Result<void, LlmServiceException>> setActiveProvider(
    String providerCode,
  );

  /// Check if streaming is supported by active provider
  ///
  /// Returns true if active provider supports streaming responses
  Future<bool> supportsStreaming();

  /// Stream translation with real-time progress
  ///
  /// Only works if active provider supports streaming.
  ///
  /// [request] - Translation request
  ///
  /// Returns stream of partial translation text or errors
  Stream<Result<String, LlmServiceException>> translateStreaming(
    LlmRequest request,
  );

  /// Get provider statistics
  ///
  /// Returns usage stats for a specific provider:
  /// - Total requests
  /// - Total tokens
  /// - Success/failure rate
  /// - Average response time
  ///
  /// [providerCode] - Provider to get stats for
  /// [fromDate] - Start date for stats (optional, defaults to all time)
  /// [toDate] - End date for stats (optional, defaults to now)
  ///
  /// Returns [Ok(ProviderStatistics)] or [Err(LlmServiceException)]
  Future<Result<ProviderStatistics, LlmServiceException>> getProviderStats(
    String providerCode, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  /// Get available providers
  ///
  /// Returns list of all configured provider codes
  List<String> getAvailableProviders();

  /// Check if a provider is available (reachable)
  ///
  /// Makes a lightweight health check request.
  ///
  /// [providerCode] - Provider to check
  ///
  /// Returns [Ok(true)] if available or [Err(LlmServiceException)]
  Future<Result<bool, LlmServiceException>> isProviderAvailable(
    String providerCode,
  );

  /// Get circuit breaker status for a provider
  ///
  /// Returns circuit breaker state (CLOSED, OPEN, HALF_OPEN)
  /// and failure/success counts.
  ///
  /// [providerCode] - Provider to check
  ///
  /// Returns [Ok(CircuitBreakerStatus)] or [Err(LlmServiceException)]
  Future<Result<CircuitBreakerStatus, LlmServiceException>>
      getCircuitBreakerStatus(String providerCode);

  /// Reset circuit breaker for a provider
  ///
  /// Forces circuit breaker to CLOSED state.
  /// Use when you know the provider is back online.
  ///
  /// [providerCode] - Provider to reset
  ///
  /// Returns [Ok(void)] or [Err(LlmServiceException)]
  Future<Result<void, LlmServiceException>> resetCircuitBreaker(
    String providerCode,
  );
}

/// Provider statistics
class ProviderStatistics {
  /// Provider code
  final String providerCode;

  /// Total requests made
  final int totalRequests;

  /// Successful requests
  final int successfulRequests;

  /// Failed requests
  final int failedRequests;

  /// Total input tokens used
  final int totalInputTokens;

  /// Total output tokens generated
  final int totalOutputTokens;

  /// Average response time in milliseconds
  final double averageResponseTimeMs;

  /// Time period start
  final DateTime fromDate;

  /// Time period end
  final DateTime toDate;

  const ProviderStatistics({
    required this.providerCode,
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.averageResponseTimeMs,
    required this.fromDate,
    required this.toDate,
  });

  /// Success rate (0.0-1.0)
  double get successRate =>
      totalRequests > 0 ? successfulRequests / totalRequests : 0.0;

  /// Total tokens used
  int get totalTokens => totalInputTokens + totalOutputTokens;

  @override
  String toString() {
    return 'ProviderStatistics($providerCode: $totalRequests requests, '
        '${(successRate * 100).toStringAsFixed(1)}% success, '
        '$totalTokens tokens)';
  }
}

/// Circuit breaker status
enum CircuitBreakerState {
  /// Circuit is closed, requests are allowed
  closed,

  /// Circuit is open, requests are blocked
  open,

  /// Circuit is half-open, testing if service recovered
  halfOpen,
}

class CircuitBreakerStatus {
  /// Current state
  final CircuitBreakerState state;

  /// Consecutive failures in current state
  final int failureCount;

  /// Consecutive successes in half-open state
  final int successCount;

  /// Time when circuit was opened (null if not open)
  final DateTime? openedAt;

  /// Time when circuit will attempt to close (null if not open)
  final DateTime? willAttemptCloseAt;

  /// Last error that caused a failure (for diagnostics)
  final String? lastErrorMessage;

  /// Last error type (e.g., "LlmRateLimitException", "LlmServerException")
  final String? lastErrorType;

  const CircuitBreakerStatus({
    required this.state,
    required this.failureCount,
    required this.successCount,
    this.openedAt,
    this.willAttemptCloseAt,
    this.lastErrorMessage,
    this.lastErrorType,
  });

  /// Check if circuit is allowing requests
  bool get isAllowingRequests =>
      state == CircuitBreakerState.closed ||
      state == CircuitBreakerState.halfOpen;

  @override
  String toString() {
    return 'CircuitBreakerStatus(state: $state, failures: $failureCount, '
        'successes: $successCount)';
  }
}
