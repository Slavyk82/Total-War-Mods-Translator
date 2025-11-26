import 'dart:async';
import 'package:twmt/services/llm/i_llm_service.dart';

/// Circuit breaker for fault tolerance
///
/// Prevents cascading failures by stopping requests to a failing service.
/// States: CLOSED (normal), OPEN (blocking), HALF_OPEN (testing recovery).
class CircuitBreaker {
  /// Service identifier
  final String serviceId;

  /// Failure threshold before opening circuit (default: 5)
  final int failureThreshold;

  /// Success threshold in half-open state before closing (default: 3)
  final int successThreshold;

  /// Timeout before attempting to close (default: 5 minutes)
  final Duration timeout;

  /// Current state
  CircuitBreakerState _state = CircuitBreakerState.closed;

  /// Consecutive failure count
  int _failureCount = 0;

  /// Consecutive success count (in half-open state)
  int _successCount = 0;

  /// Time when circuit was opened
  DateTime? _openedAt;

  /// Timer for automatic state transition
  Timer? _timer;

  /// Last error that caused a failure (for diagnostics)
  Object? _lastError;

  /// Last error type
  String? _lastErrorType;

  CircuitBreaker({
    required this.serviceId,
    this.failureThreshold = 5,
    this.successThreshold = 3,
    this.timeout = const Duration(minutes: 5),
  });

  /// Execute a function with circuit breaker protection
  ///
  /// [fn] - Function to execute
  ///
  /// Returns result of function or throws CircuitBreakerOpenException
  Future<T> execute<T>(Future<T> Function() fn) async {
    // Check if circuit is open
    if (_state == CircuitBreakerState.open) {
      final now = DateTime.now();
      final timeOpen = now.difference(_openedAt!);

      // Check if timeout has passed
      if (timeOpen >= timeout) {
        _transitionToHalfOpen();
      } else {
        throw CircuitBreakerOpenException(
          serviceId: serviceId,
          willAttemptCloseAt: _openedAt!.add(timeout),
          lastErrorMessage: _lastError?.toString(),
          lastErrorType: _lastErrorType,
        );
      }
    }

    try {
      // Execute function
      final result = await fn();

      // Record success
      _onSuccess();

      return result;
    } catch (error) {
      // Record failure with error details
      _onFailure(error);
      rethrow;
    }
  }

  /// Record a success
  void _onSuccess() {
    if (_state == CircuitBreakerState.halfOpen) {
      _successCount++;

      if (_successCount >= successThreshold) {
        _transitionToClosed();
      }
    } else if (_state == CircuitBreakerState.closed) {
      // Reset failure count on success
      _failureCount = 0;
    }
  }

  /// Record a failure with error details
  void _onFailure(Object error) {
    // Store error details for diagnostics
    _lastError = error;
    _lastErrorType = error.runtimeType.toString();

    if (_state == CircuitBreakerState.closed) {
      _failureCount++;

      if (_failureCount >= failureThreshold) {
        _transitionToOpen();
      }
    } else if (_state == CircuitBreakerState.halfOpen) {
      // Any failure in half-open state reopens circuit
      _transitionToOpen();
    }
  }

  /// Transition to OPEN state
  void _transitionToOpen() {
    _state = CircuitBreakerState.open;
    _openedAt = DateTime.now();
    _failureCount = 0;
    _successCount = 0;

    // Schedule transition to half-open after timeout
    _timer?.cancel();
    _timer = Timer(timeout, _transitionToHalfOpen);
  }

  /// Transition to HALF_OPEN state
  void _transitionToHalfOpen() {
    _state = CircuitBreakerState.halfOpen;
    _successCount = 0;
    _failureCount = 0;
  }

  /// Transition to CLOSED state
  void _transitionToClosed() {
    _state = CircuitBreakerState.closed;
    _openedAt = null;
    _failureCount = 0;
    _successCount = 0;
    _timer?.cancel();
  }

  /// Get current status
  CircuitBreakerStatus getStatus() {
    return CircuitBreakerStatus(
      state: _state,
      failureCount: _failureCount,
      successCount: _successCount,
      openedAt: _openedAt,
      willAttemptCloseAt: _openedAt?.add(timeout),
      lastErrorMessage: _lastError?.toString(),
      lastErrorType: _lastErrorType,
    );
  }

  /// Get last error message (for display in UI)
  String? get lastErrorMessage => _lastError?.toString();

  /// Get last error type (for display in UI)
  String? get lastErrorType => _lastErrorType;

  /// Reset circuit breaker to CLOSED state
  void reset() {
    _transitionToClosed();
    // Clear error history on manual reset
    _lastError = null;
    _lastErrorType = null;
  }

  /// Check if requests are allowed
  bool get isAllowingRequests =>
      _state == CircuitBreakerState.closed ||
      _state == CircuitBreakerState.halfOpen;

  /// Dispose circuit breaker
  void dispose() {
    _timer?.cancel();
  }

  @override
  String toString() {
    return 'CircuitBreaker($serviceId: state=$_state, '
        'failures=$_failureCount, successes=$_successCount)';
  }
}

/// Exception thrown when circuit is open
class CircuitBreakerOpenException implements Exception {
  final String serviceId;
  final DateTime willAttemptCloseAt;

  /// Last error that caused the circuit to open (for diagnostics)
  final String? lastErrorMessage;

  /// Last error type
  final String? lastErrorType;

  const CircuitBreakerOpenException({
    required this.serviceId,
    required this.willAttemptCloseAt,
    this.lastErrorMessage,
    this.lastErrorType,
  });

  @override
  String toString() {
    final waitTime = willAttemptCloseAt.difference(DateTime.now());
    final errorInfo = lastErrorMessage != null
        ? ' Last error: $lastErrorMessage'
        : '';
    return 'Circuit breaker is OPEN for $serviceId. '
        'Will attempt to close in ${waitTime.inSeconds}s.$errorInfo';
  }
}

/// Circuit breaker manager for multiple services
class CircuitBreakerManager {
  /// Circuit breakers by service ID
  final Map<String, CircuitBreaker> _breakers = {};

  /// Default configuration
  final int defaultFailureThreshold;
  final int defaultSuccessThreshold;
  final Duration defaultTimeout;

  CircuitBreakerManager({
    this.defaultFailureThreshold = 5,
    this.defaultSuccessThreshold = 3,
    this.defaultTimeout = const Duration(minutes: 5),
  });

  /// Get or create circuit breaker for a service
  CircuitBreaker getBreaker(String serviceId) {
    return _breakers.putIfAbsent(
      serviceId,
      () => CircuitBreaker(
        serviceId: serviceId,
        failureThreshold: defaultFailureThreshold,
        successThreshold: defaultSuccessThreshold,
        timeout: defaultTimeout,
      ),
    );
  }

  /// Execute with circuit breaker protection
  Future<T> execute<T>(String serviceId, Future<T> Function() fn) {
    return getBreaker(serviceId).execute(fn);
  }

  /// Get status for a service
  CircuitBreakerStatus getStatus(String serviceId) {
    final breaker = _breakers[serviceId];
    if (breaker == null) {
      return CircuitBreakerStatus(
        state: CircuitBreakerState.closed,
        failureCount: 0,
        successCount: 0,
      );
    }
    return breaker.getStatus();
  }

  /// Reset circuit breaker for a service
  void reset(String serviceId) {
    _breakers[serviceId]?.reset();
  }

  /// Reset all circuit breakers
  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }

  /// Get all circuit breaker statuses
  Map<String, CircuitBreakerStatus> getAllStatuses() {
    return {
      for (final entry in _breakers.entries)
        entry.key: entry.value.getStatus(),
    };
  }

  /// Dispose all circuit breakers
  void dispose() {
    for (final breaker in _breakers.values) {
      breaker.dispose();
    }
    _breakers.clear();
  }
}
