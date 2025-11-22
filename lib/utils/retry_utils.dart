import 'dart:async';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Retry utilities for handling transient failures.
///
/// Provides various retry strategies for operations that may fail temporarily
/// due to network issues, database locks, or other transient conditions.
class RetryUtils {
  // Private constructor to prevent instantiation
  RetryUtils._();

  static final LoggingService _logger = LoggingService.instance;

  /// Execute an operation with exponential backoff retry.
  ///
  /// Retries the operation with increasing delays between attempts.
  /// Delay pattern: initialDelay, initialDelay * 2, initialDelay * 4, ...
  ///
  /// Example:
  /// ```dart
  /// final result = await RetryUtils.withExponentialBackoff(
  ///   () => apiCall(),
  ///   maxRetries: 3,
  ///   initialDelay: Duration(milliseconds: 100),
  /// );
  /// ```
  ///
  /// [operation] - The operation to execute
  /// [maxRetries] - Maximum number of retry attempts (default: 3)
  /// [initialDelay] - Initial delay before first retry (default: 100ms)
  /// [maxDelay] - Maximum delay between retries (default: 10s)
  /// [shouldRetry] - Optional predicate to determine if error should be retried
  ///
  /// Returns the result of the operation or throws the last error
  static Future<T> withExponentialBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    Duration maxDelay = const Duration(seconds: 10),
    bool Function(Object error)? shouldRetry,
  }) async {
    var attempt = 0;
    var delay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (e, stackTrace) {
        attempt++;

        // Check if we should retry this error
        if (shouldRetry != null && !shouldRetry(e)) {
          _logger.debug('Error is not retryable: $e');
          rethrow;
        }

        // Check if we've exhausted retries
        if (attempt > maxRetries) {
          _logger.error(
            'Operation failed after $maxRetries retries',
            e,
            stackTrace,
          );
          rethrow;
        }

        _logger.warning(
          'Operation failed, retrying (attempt $attempt/$maxRetries) after ${delay.inMilliseconds}ms: $e',
        );

        // Wait before retrying
        await Future.delayed(delay);

        // Calculate next delay with exponential backoff
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 2).clamp(
            initialDelay.inMilliseconds,
            maxDelay.inMilliseconds,
          ),
        );
      }
    }
  }

  /// Execute an operation with linear backoff retry.
  ///
  /// Retries the operation with a fixed delay between attempts.
  ///
  /// Example:
  /// ```dart
  /// final result = await RetryUtils.withLinearBackoff(
  ///   () => databaseQuery(),
  ///   maxRetries: 3,
  ///   delay: Duration(seconds: 1),
  /// );
  /// ```
  static Future<T> withLinearBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(Object error)? shouldRetry,
  }) async {
    var attempt = 0;

    while (true) {
      try {
        return await operation();
      } catch (e, stackTrace) {
        attempt++;

        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }

        if (attempt > maxRetries) {
          _logger.error(
            'Operation failed after $maxRetries retries',
            e,
            stackTrace,
          );
          rethrow;
        }

        _logger.warning(
          'Operation failed, retrying (attempt $attempt/$maxRetries) after ${delay.inMilliseconds}ms: $e',
        );

        await Future.delayed(delay);
      }
    }
  }

  /// Execute an operation with Result type and retry on Err.
  ///
  /// This is a retry strategy specifically for operations returning Result types.
  ///
  /// Example:
  /// ```dart
  /// final result = await RetryUtils.withResultRetry(
  ///   () => repository.insert(entity),
  ///   maxRetries: 3,
  /// );
  /// ```
  static Future<Result<T, E>> withResultRetry<T, E>(
    Future<Result<T, E>> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    bool Function(E error)? shouldRetry,
  }) async {
    var attempt = 0;
    var delay = initialDelay;
    Result<T, E>? lastResult;

    while (attempt <= maxRetries) {
      lastResult = await operation();

      if (lastResult.isOk) {
        return lastResult;
      }

      attempt++;

      if (shouldRetry != null && !shouldRetry(lastResult.error)) {
        return lastResult;
      }

      if (attempt <= maxRetries) {
        _logger.warning(
          'Operation returned error, retrying (attempt $attempt/$maxRetries)',
        );

        await Future.delayed(delay);
        delay = Duration(milliseconds: delay.inMilliseconds * 2);
      }
    }

    return lastResult!;
  }

  /// Execute an operation with a fallback if it fails.
  ///
  /// Tries the primary operation first, falls back to the fallback operation if it fails.
  ///
  /// Example:
  /// ```dart
  /// final result = await RetryUtils.withFallback(
  ///   primary: () => fetchFromCache(),
  ///   fallback: () => fetchFromDatabase(),
  /// );
  /// ```
  static Future<T> withFallback<T>(
    Future<T> Function() primary,
    Future<T> Function() fallback,
  ) async {
    try {
      return await primary();
    } catch (e) {
      _logger.warning('Primary operation failed, using fallback: $e');
      return await fallback();
    }
  }

  /// Execute an operation with a Result fallback.
  ///
  /// Similar to [withFallback] but for Result types.
  static Future<Result<T, E>> withResultFallback<T, E>(
    Future<Result<T, E>> Function() primary,
    Future<Result<T, E>> Function() fallback,
  ) async {
    final result = await primary();

    if (result.isOk) {
      return result;
    }

    _logger.warning('Primary operation failed, using fallback');
    return await fallback();
  }

  /// Execute an operation with a timeout.
  ///
  /// Throws a TimeoutException if the operation doesn't complete in time.
  ///
  /// Example:
  /// ```dart
  /// final result = await RetryUtils.withTimeout(
  ///   () => longRunningOperation(),
  ///   timeout: Duration(seconds: 30),
  /// );
  /// ```
  static Future<T> withTimeout<T>(
    Future<T> Function() operation, {
    required Duration timeout,
    String? operationName,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on TimeoutException catch (e, stackTrace) {
      final name = operationName ?? 'Operation';
      _logger.error(
        '$name timed out after ${timeout.inMilliseconds}ms',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Execute an operation with circuit breaker pattern.
  ///
  /// After a certain number of consecutive failures, the circuit "opens"
  /// and subsequent calls fail immediately without trying the operation.
  /// After a timeout period, the circuit tries to "close" by allowing one attempt.
  ///
  /// Example:
  /// ```dart
  /// final breaker = CircuitBreaker(
  ///   failureThreshold: 5,
  ///   resetTimeout: Duration(seconds: 60),
  /// );
  ///
  /// final result = await breaker.execute(() => externalApiCall());
  /// ```
  static CircuitBreaker createCircuitBreaker({
    int failureThreshold = 5,
    Duration resetTimeout = const Duration(seconds: 60),
  }) {
    return CircuitBreaker(
      failureThreshold: failureThreshold,
      resetTimeout: resetTimeout,
    );
  }
}

/// Circuit breaker implementation for preventing cascading failures.
///
/// The circuit breaker has three states:
/// - Closed: Normal operation, requests pass through
/// - Open: Too many failures, requests fail immediately
/// - Half-Open: Testing if service has recovered
class CircuitBreaker {
  final int failureThreshold;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitBreakerState _state = CircuitBreakerState.closed;

  final LoggingService _logger = LoggingService.instance;

  CircuitBreaker({
    required this.failureThreshold,
    required this.resetTimeout,
  });

  CircuitBreakerState get state => _state;
  int get failureCount => _failureCount;

  /// Execute an operation through the circuit breaker.
  Future<T> execute<T>(Future<T> Function() operation) async {
    // Check if circuit should transition to half-open
    if (_state == CircuitBreakerState.open) {
      final timeSinceLastFailure =
          DateTime.now().difference(_lastFailureTime!);

      if (timeSinceLastFailure >= resetTimeout) {
        _logger.info('Circuit breaker transitioning to half-open state');
        _state = CircuitBreakerState.halfOpen;
      } else {
        throw CircuitBreakerOpenException(
          'Circuit breaker is open. Service unavailable.',
        );
      }
    }

    try {
      final result = await operation();

      // Success - reset failure count and close circuit
      if (_state == CircuitBreakerState.halfOpen) {
        _logger.info('Circuit breaker closing after successful attempt');
      }

      _failureCount = 0;
      _state = CircuitBreakerState.closed;

      return result;
    } catch (e, stackTrace) {
      _failureCount++;
      _lastFailureTime = DateTime.now();

      _logger.warning(
        'Circuit breaker recorded failure ($_failureCount/$failureThreshold): $e',
      );

      if (_failureCount >= failureThreshold) {
        _logger.error(
          'Circuit breaker opening after $failureThreshold failures',
          e,
          stackTrace,
        );
        _state = CircuitBreakerState.open;
      }

      rethrow;
    }
  }

  /// Reset the circuit breaker to closed state.
  void reset() {
    _failureCount = 0;
    _lastFailureTime = null;
    _state = CircuitBreakerState.closed;
    _logger.info('Circuit breaker manually reset');
  }
}

/// States of a circuit breaker.
enum CircuitBreakerState {
  /// Normal operation - requests pass through
  closed,

  /// Too many failures - requests fail immediately
  open,

  /// Testing recovery - one request allowed
  halfOpen,
}

/// Exception thrown when circuit breaker is open.
class CircuitBreakerOpenException implements Exception {
  final String message;

  CircuitBreakerOpenException(this.message);

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}
