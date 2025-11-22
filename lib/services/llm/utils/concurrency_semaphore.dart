import 'dart:async';

/// Reusable semaphore for controlling concurrency across services
///
/// This utility class provides a thread-safe semaphore implementation
/// for limiting concurrent operations. It's designed to be reused
/// across different services in the application.
///
/// Example usage:
/// ```dart
/// final semaphore = ConcurrencySemaphore(maxConcurrent: 5);
///
/// // Acquire slot before performing operation
/// await semaphore.acquire();
/// try {
///   await performOperation();
/// } finally {
///   semaphore.release();
/// }
/// ```
class ConcurrencySemaphore {
  final int _maxCount;
  int _currentCount = 0;
  final List<Completer<void>> _waiters = [];

  /// Creates a semaphore with specified maximum concurrent operations
  ///
  /// [maxConcurrent] Maximum number of concurrent operations allowed (must be >= 1)
  ConcurrencySemaphore({required int maxConcurrent})
      : assert(maxConcurrent >= 1, 'maxConcurrent must be at least 1'),
        _maxCount = maxConcurrent;

  /// Acquire a semaphore slot
  ///
  /// If a slot is available, returns immediately and increments the count.
  /// If all slots are taken, waits until a slot becomes available.
  ///
  /// Always call [release] after completing the operation to free the slot.
  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  /// Release a semaphore slot
  ///
  /// If there are waiters, immediately assigns the slot to the next waiter.
  /// Otherwise, decrements the current count.
  ///
  /// Should always be called in a finally block after [acquire].
  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }

  /// Get current number of active operations
  int get activeCount => _currentCount;

  /// Get number of operations waiting for a slot
  int get waitingCount => _waiters.length;

  /// Check if all slots are currently occupied
  bool get isAtCapacity => _currentCount >= _maxCount;

  /// Get maximum concurrent operations allowed
  int get maxConcurrent => _maxCount;

  /// Execute a function with automatic semaphore management
  ///
  /// Acquires a slot, executes the function, and releases the slot
  /// in a finally block. This ensures proper cleanup even if the
  /// function throws an error.
  ///
  /// Example:
  /// ```dart
  /// final result = await semaphore.execute(() async {
  ///   return await performOperation();
  /// });
  /// ```
  Future<T> execute<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}
