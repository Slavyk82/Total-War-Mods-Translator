import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';

/// Interface for LLM providers (Anthropic, OpenAI, DeepL)
abstract class ILlmProvider {
  /// Provider code (e.g., "anthropic", "openai", "deepl")
  String get providerCode;

  /// Provider display name
  String get providerName;

  /// Provider configuration
  LlmProviderConfig get config;

  /// Translate a batch of texts
  ///
  /// [request] - Translation request with texts and context
  /// [apiKey] - API key for authentication
  /// [cancelToken] - Optional token to cancel the request
  ///
  /// Returns [Ok(LlmResponse)] on success or [Err(LlmProviderException)] on failure
  Future<Result<LlmResponse, LlmProviderException>> translate(
    LlmRequest request,
    String apiKey, {
    CancelToken? cancelToken,
  });

  /// Estimate tokens for a given text
  ///
  /// This is provider-specific as different providers use different tokenizers.
  /// For OpenAI/Anthropic: uses tiktoken (cl100k_base encoding)
  /// For DeepL: returns character count (as DeepL is character-based)
  ///
  /// [text] - Text to estimate tokens for
  ///
  /// Returns estimated token count
  int estimateTokens(String text);

  /// Estimate tokens for a complete request
  ///
  /// Includes system prompt, context, input texts, and estimated output.
  ///
  /// [request] - Complete translation request
  ///
  /// Returns estimated total tokens (input + output)
  int estimateRequestTokens(LlmRequest request);

  /// Validate API key
  ///
  /// Makes a minimal API call to verify the key is valid.
  ///
  /// [apiKey] - API key to validate
  /// [model] - Optional model to use for validation (uses default if not provided)
  ///
  /// Returns [Ok(true)] if valid or [Err(LlmProviderException)] if invalid
  Future<Result<bool, LlmProviderException>> validateApiKey(
    String apiKey, {
    String? model,
  });

  /// Check if streaming is supported by this provider
  bool get supportsStreaming;

  /// Translate with streaming response (if supported)
  ///
  /// Yields partial translations as they are generated.
  /// Useful for real-time UI updates.
  ///
  /// [request] - Translation request
  /// [apiKey] - API key for authentication
  ///
  /// Returns stream of partial responses or errors
  Stream<Result<String, LlmProviderException>> translateStreaming(
    LlmRequest request,
    String apiKey,
  );

  /// Calculate retry delay based on rate limit exception
  ///
  /// Uses provider-specific headers (Retry-After, X-RateLimit-Reset, etc.)
  /// to calculate optimal retry delay.
  ///
  /// [exception] - Rate limit exception with provider headers
  ///
  /// Returns delay duration before retry
  Duration calculateRetryDelay(LlmRateLimitException exception);

  /// Check if the provider is available (API reachable)
  ///
  /// Makes a lightweight health check request.
  ///
  /// Returns [Ok(true)] if available or [Err(LlmProviderException)] if unavailable
  Future<Result<bool, LlmProviderException>> isAvailable();

  /// Get current rate limit status
  ///
  /// Returns remaining requests and tokens for the current window.
  /// Returns null if provider doesn't expose rate limit info.
  ///
  /// [apiKey] - API key to check rate limits for
  ///
  /// Returns [Ok(RateLimitStatus)] or [Err(LlmProviderException)]
  Future<Result<RateLimitStatus?, LlmProviderException>> getRateLimitStatus(
    String apiKey,
  );
}

/// Rate limit status information
class RateLimitStatus {
  /// Remaining requests in current window
  final int? remainingRequests;

  /// Remaining tokens in current window
  final int? remainingTokens;

  /// Time when rate limit window resets
  final DateTime? resetTime;

  /// Total request limit per window
  final int? totalRequests;

  /// Total token limit per window
  final int? totalTokens;

  const RateLimitStatus({
    this.remainingRequests,
    this.remainingTokens,
    this.resetTime,
    this.totalRequests,
    this.totalTokens,
  });

  /// Check if we're close to rate limit (< 10% remaining)
  bool get isNearLimit {
    if (remainingRequests != null && totalRequests != null) {
      return (remainingRequests! / totalRequests!) < 0.1;
    }
    if (remainingTokens != null && totalTokens != null) {
      return (remainingTokens! / totalTokens!) < 0.1;
    }
    return false;
  }

  /// Suggested delay before next request (0 if not near limit)
  Duration get suggestedDelay {
    if (!isNearLimit) return Duration.zero;
    if (resetTime != null) {
      final timeUntilReset = resetTime!.difference(DateTime.now());
      if (timeUntilReset.isNegative) return Duration.zero;
      // Distribute remaining requests over remaining time
      if (remainingRequests != null && remainingRequests! > 0) {
        return Duration(
          milliseconds:
              timeUntilReset.inMilliseconds ~/ remainingRequests!,
        );
      }
      return timeUntilReset;
    }
    return Duration(seconds: 1); // Default 1s delay when near limit
  }

  @override
  String toString() {
    return 'RateLimitStatus(requests: $remainingRequests/$totalRequests, '
        'tokens: $remainingTokens/$totalTokens, resetTime: $resetTime)';
  }
}
