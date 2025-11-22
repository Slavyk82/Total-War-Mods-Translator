import 'dart:async';
import 'package:twmt/services/llm/utils/token_bucket.dart';

/// Rate limiter using dual token bucket algorithm
///
/// Implements rate limiting for both requests per minute (RPM)
/// and tokens per minute (TPM) simultaneously.
class RateLimiter {
  /// Requests per minute limit
  final int requestsPerMinute;

  /// Tokens per minute limit (null if not applicable, e.g., DeepL)
  final int? tokensPerMinute;

  /// Token bucket for request rate limiting
  late final TokenBucket _requestBucket;

  /// Token bucket for token rate limiting (null if TPM not applicable)
  TokenBucket? _tokenBucket;

  /// Queue of pending requests
  final List<_PendingRequest> _queue = [];

  /// Timer for processing queue
  Timer? _queueTimer;

  RateLimiter({
    required this.requestsPerMinute,
    this.tokensPerMinute,
  }) {
    // Initialize request bucket (RPM)
    // Refill rate: requestsPerMinute / 60 = requests per second
    _requestBucket = TokenBucket(
      capacity: requestsPerMinute,
      refillRate: requestsPerMinute / 60.0,
    );

    // Initialize token bucket (TPM) if applicable
    if (tokensPerMinute != null) {
      _tokenBucket = TokenBucket(
        capacity: tokensPerMinute!,
        refillRate: tokensPerMinute! / 60.0,
      );
    }

    // Start queue processor
    _startQueueProcessor();
  }

  /// Try to acquire permission to make a request
  ///
  /// Returns immediately if tokens available, otherwise returns false.
  ///
  /// [estimatedTokens] - Estimated tokens for the request (optional if TPM not used)
  ///
  /// Returns true if request can proceed, false if rate limited
  bool tryAcquire({int estimatedTokens = 0}) {
    // Check request bucket
    if (!_requestBucket.tryConsume(1)) {
      return false;
    }

    // Check token bucket if applicable
    if (_tokenBucket != null && estimatedTokens > 0) {
      if (!_tokenBucket!.tryConsume(estimatedTokens)) {
        // Refund request token since we can't proceed
        _requestBucket.tryConsume(-1);
        return false;
      }
    }

    return true;
  }

  /// Wait for permission to make a request (async)
  ///
  /// Returns a Future that completes when request can proceed.
  /// Queues the request and waits for rate limit tokens to be available.
  ///
  /// [estimatedTokens] - Estimated tokens for the request
  ///
  /// Returns Future that completes when request can proceed
  Future<void> acquire({int estimatedTokens = 0}) async {
    final completer = Completer<void>();
    _queue.add(_PendingRequest(
      completer: completer,
      estimatedTokens: estimatedTokens,
    ));
    return completer.future;
  }

  /// Calculate wait time for a request
  ///
  /// Returns Duration to wait before request can proceed.
  ///
  /// [estimatedTokens] - Estimated tokens for the request
  ///
  /// Returns wait duration (zero if can proceed immediately)
  Duration calculateWaitTime({int estimatedTokens = 0}) {
    // Calculate wait for request bucket
    final requestWait = _requestBucket.waitAndConsume(1);

    // Calculate wait for token bucket if applicable
    Duration tokenWait = Duration.zero;
    if (_tokenBucket != null && estimatedTokens > 0) {
      tokenWait = _tokenBucket!.waitAndConsume(estimatedTokens);
    }

    // Refund consumed tokens (this was just a calculation)
    _requestBucket.tryConsume(-1);
    if (_tokenBucket != null && estimatedTokens > 0) {
      _tokenBucket!.tryConsume(-estimatedTokens);
    }

    // Return maximum wait time
    return requestWait > tokenWait ? requestWait : tokenWait;
  }

  /// Reset rate limiter (clear all tokens and queue)
  void reset() {
    _requestBucket.reset();
    _tokenBucket?.reset();
    _queue.clear();
  }

  /// Get current rate limit status
  RateLimitStatus getStatus() {
    return RateLimitStatus(
      availableRequests: _requestBucket.availableTokens.toInt(),
      maxRequests: requestsPerMinute,
      availableTokens: _tokenBucket?.availableTokens.toInt(),
      maxTokens: tokensPerMinute,
      queuedRequests: _queue.length,
    );
  }

  /// Start queue processor
  void _startQueueProcessor() {
    _queueTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _processQueue();
    });
  }

  /// Process queued requests
  void _processQueue() {
    if (_queue.isEmpty) return;

    // Try to process requests from queue
    while (_queue.isNotEmpty) {
      final request = _queue.first;

      // Try to acquire tokens
      if (tryAcquire(estimatedTokens: request.estimatedTokens)) {
        // Remove from queue and complete
        _queue.removeAt(0);
        request.completer.complete();
      } else {
        // Can't process more requests, wait for next tick
        break;
      }
    }
  }

  /// Dispose rate limiter
  void dispose() {
    _queueTimer?.cancel();
    _queue.clear();
  }

  @override
  String toString() {
    return 'RateLimiter(rpm: $requestsPerMinute, tpm: $tokensPerMinute, '
        'queue: ${_queue.length}, status: ${getStatus()})';
  }
}

/// Pending request in queue
class _PendingRequest {
  final Completer<void> completer;
  final int estimatedTokens;

  _PendingRequest({
    required this.completer,
    required this.estimatedTokens,
  });
}

/// Rate limit status
class RateLimitStatus {
  /// Available requests in current window
  final int availableRequests;

  /// Maximum requests per window
  final int maxRequests;

  /// Available tokens in current window (null if TPM not used)
  final int? availableTokens;

  /// Maximum tokens per window (null if TPM not used)
  final int? maxTokens;

  /// Number of requests in queue
  final int queuedRequests;

  const RateLimitStatus({
    required this.availableRequests,
    required this.maxRequests,
    this.availableTokens,
    this.maxTokens,
    required this.queuedRequests,
  });

  /// Request utilization (0.0-1.0)
  double get requestUtilization => 1.0 - (availableRequests / maxRequests);

  /// Token utilization (0.0-1.0) (null if TPM not used)
  double? get tokenUtilization {
    if (availableTokens == null || maxTokens == null) return null;
    return 1.0 - (availableTokens! / maxTokens!);
  }

  /// Check if near rate limit (>90% utilized)
  bool get isNearLimit =>
      requestUtilization > 0.9 ||
      (tokenUtilization != null && tokenUtilization! > 0.9);

  @override
  String toString() {
    final tokenInfo = availableTokens != null
        ? ', tokens: $availableTokens/$maxTokens'
        : '';
    return 'RateLimitStatus(requests: $availableRequests/$maxRequests$tokenInfo, '
        'queued: $queuedRequests)';
  }
}
