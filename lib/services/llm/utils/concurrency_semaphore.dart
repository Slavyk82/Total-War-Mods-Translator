import 'dart:async';
import 'dart:collection';

/// Reusable semaphore for controlling concurrency across services
///
/// This utility class provides a thread-safe semaphore implementation
/// for limiting concurrent operations. It's designed to be reused
/// across different services in the application.
///
/// The implementation uses a queue-based approach to prevent race conditions
/// in Dart's async context. All acquire requests are serialized through a
/// queue to ensure proper ordering and prevent counter drift.
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

  /// Queue of waiters for available slots (FIFO order)
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Queue of pending acquire requests to serialize access
  final Queue<Completer<void>> _acquireQueue = Queue<Completer<void>>();

  /// Flag to track if an acquire operation is in progress
  bool _isProcessingAcquire = false;

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
  /// This method serializes all acquire requests to prevent race conditions
  /// where multiple concurrent calls could pass the availability check
  /// before any of them increments the counter.
  ///
  /// Always call [release] after completing the operation to free the slot.
  Future<void> acquire() async {
    // Serialize access to prevent race conditions
    if (_isProcessingAcquire) {
      final waitCompleter = Completer<void>();
      _acquireQueue.add(waitCompleter);
      await waitCompleter.future;
    }

    _isProcessingAcquire = true;
    try {
      if (_currentCount < _maxCount) {
        _currentCount++;
        return;
      }

      // All slots are taken, wait for one to become available
      final completer = Completer<void>();
      _waiters.add(completer);

      // Release the acquire lock while waiting for a slot
      _processNextAcquireRequest();

      await completer.future;
      // When we get here, the slot has been assigned to us by release()
    } finally {
      _processNextAcquireRequest();
    }
  }

  /// Process the next pending acquire request in the queue
  void _processNextAcquireRequest() {
    _isProcessingAcquire = false;
    if (_acquireQueue.isNotEmpty) {
      final next = _acquireQueue.removeFirst();
      next.complete();
    }
  }

  /// Release a semaphore slot
  ///
  /// If there are waiters, immediately assigns the slot to the next waiter.
  /// Otherwise, decrements the current count.
  ///
  /// Should always be called in a finally block after [acquire].
  void release() {
    // Validate that release is called correctly
    if (_currentCount <= 0 && _waiters.isEmpty) {
      // Log warning but don't assert to prevent crashes in production
      // This indicates a bug where release was called without matching acquire
      return;
    }

    if (_waiters.isNotEmpty) {
      // Pass the slot directly to the next waiter
      // The count stays the same since we're transferring the slot
      final completer = _waiters.removeFirst();
      completer.complete();
    } else if (_currentCount > 0) {
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
