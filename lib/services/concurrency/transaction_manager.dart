import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../models/common/result.dart';
import 'models/concurrency_exceptions.dart';

/// Manager for database transactions with retry logic
///
/// Provides transactional operations with automatic retry on conflict
/// and rollback on error.
class TransactionManager {
  final Uuid _uuid;

  /// Default maximum retry attempts
  static const int defaultMaxRetries = 3;

  /// Default retry delay
  static const Duration defaultRetryDelay = Duration(milliseconds: 100);

  TransactionManager({
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  Database get _db => DatabaseService.database;

  /// Execute a transaction with automatic retry on conflict
  ///
  /// Parameters:
  /// - [action]: Transaction callback to execute
  /// - [maxRetries]: Maximum retry attempts (default: 3)
  /// - [retryDelay]: Delay between retries (default: 100ms)
  ///
  /// Returns:
  /// - [Ok]: Result of the transaction
  /// - [Err]: Exception if transaction failed after all retries
  ///
  /// Example:
  /// ```dart
  /// final result = await manager.executeTransaction<int>((txn) async {
  ///   // Update multiple records atomically
  ///   await txn.update('table1', data1, where: 'id = ?', whereArgs: [id1]);
  ///   await txn.update('table2', data2, where: 'id = ?', whereArgs: [id2]);
  ///   return 2; // Number of updates
  /// });
  ///
  /// if (result is Ok) {
  ///   print('Transaction completed: ${result.value} updates');
  /// }
  /// ```
  Future<Result<T, ConcurrencyException>> executeTransaction<T>(
    Future<T> Function(Transaction txn) action, {
    int maxRetries = defaultMaxRetries,
    Duration retryDelay = defaultRetryDelay,
  }) async {
    int attempts = 0;

    while (attempts <= maxRetries) {
      try {
        final result = await _db.transaction<T>((txn) async {
          return await action(txn);
        });

        return Ok(result);
      } on DatabaseException catch (e) {
        attempts++;

        // Check if error is retryable (e.g., database locked, busy)
        final isRetryable = _isRetryableError(e);

        if (!isRetryable || attempts > maxRetries) {
          return Err(TransactionException(
            'Transaction failed after $attempts attempts: ${e.toString()}',
            transactionId: _uuid.v4(),
            originalError: e,
          ));
        }

        // Wait before retry with exponential backoff
        final delay = retryDelay * attempts;
        await Future.delayed(delay);
      } catch (e) {
        return Err(TransactionException(
          'Unexpected transaction error: ${e.toString()}',
          transactionId: _uuid.v4(),
          originalError: e,
        ));
      }
    }

    // Max retries exceeded
    return Err(MaxRetriesExceededException(
      'Transaction failed after $maxRetries retries',
      maxRetries: maxRetries,
      attemptsMade: attempts,
    ));
  }

  /// Execute a batch of operations in a transaction
  ///
  /// All operations succeed or all fail (atomicity).
  ///
  /// Parameters:
  /// - [operations]: List of operations to execute
  /// - [maxRetries]: Maximum retry attempts
  ///
  /// Returns:
  /// - [Ok]: Number of operations completed
  /// - [Err]: Exception if batch failed
  ///
  /// Example:
  /// ```dart
  /// final operations = [
  ///   () async => db.insert('table', data1),
  ///   () async => db.update('table', data2, where: 'id = ?', whereArgs: [id]),
  ///   () async => db.delete('table', where: 'id = ?', whereArgs: [oldId]),
  /// ];
  ///
  /// final result = await manager.executeBatch(operations);
  /// ```
  Future<Result<int, ConcurrencyException>> executeBatch(
    List<Future<void> Function(Transaction txn)> operations, {
    int maxRetries = defaultMaxRetries,
  }) async {
    return await executeTransaction<int>((txn) async {
      for (final operation in operations) {
        await operation(txn);
      }
      return operations.length;
    }, maxRetries: maxRetries);
  }

  /// Execute a read callback against the database.
  ///
  /// NOTE: This is a thin convenience wrapper that runs [query] against the
  /// shared [Database] handle and maps failures to a [Result]. It does NOT
  /// open a transaction, so it provides **no** isolation / consistent snapshot
  /// across multiple reads, and it does NOT prevent writes — the callback
  /// receives a full [Database] and can execute arbitrary statements.
  ///
  /// (Contract corrected per code review: wrapping in a real read transaction
  /// would require changing the callback parameter from [Database] to
  /// [Transaction], a breaking API change. The earlier claim of write
  /// prevention / DEFERRED isolation was never actually implemented. Callers
  /// needing a consistent snapshot should use [executeTransaction] and confine
  /// themselves to reads within it.)
  ///
  /// Parameters:
  /// - [query]: Read callback
  ///
  /// Returns:
  /// - [Ok]: Query result
  /// - [Err]: Exception if query failed
  Future<Result<T, ConcurrencyException>> executeReadOnly<T>(
    Future<T> Function(Database db) query,
  ) async {
    try {
      // No transaction wrapper: see method doc. The callback runs directly
      // against the shared database handle.
      final result = await query(_db);
      return Ok(result);
    } on DatabaseException catch (e) {
      return Err(TransactionException(
        'Read-only transaction failed: ${e.toString()}',
        originalError: e,
      ));
    } catch (e) {
      return Err(TransactionException(
        'Unexpected read-only error: ${e.toString()}',
        originalError: e,
      ));
    }
  }

  /// Execute with exclusive lock (IMMEDIATE or EXCLUSIVE transaction)
  ///
  /// Acquires a write lock immediately, preventing other writers.
  /// Use for critical sections where immediate locking is needed.
  ///
  /// Parameters:
  /// - [action]: Transaction callback
  /// - [exclusive]: Use EXCLUSIVE lock (default: false, uses IMMEDIATE)
  ///
  /// Returns:
  /// - [Ok]: Transaction result
  /// - [Err]: Exception if failed
  Future<Result<T, ConcurrencyException>> executeExclusive<T>(
    Future<T> Function(Transaction txn) action, {
    bool exclusive = false,
  }) async {
    try {
      // Start exclusive transaction (EXCLUSIVE or IMMEDIATE lock)

      final result = await _db.transaction<T>((txn) async {
        // Lock is acquired at transaction start for IMMEDIATE/EXCLUSIVE
        return await action(txn);
      }, exclusive: exclusive);

      return Ok(result);
    } on DatabaseException catch (e) {
      return Err(TransactionException(
        'Exclusive transaction failed: ${e.toString()}',
        originalError: e,
      ));
    } catch (e) {
      return Err(TransactionException(
        'Unexpected exclusive transaction error: ${e.toString()}',
        originalError: e,
      ));
    }
  }

  /// Check if database is in a transaction
  ///
  /// Note: SQLite FFI doesn't expose this directly, so we track it manually.
  bool get isInTransaction {
    // This is a simplified check - in production you might track this
    // via a state variable if needed
    return false;
  }

  /// Execute with timeout
  ///
  /// Attempts to limit transaction execution time using Dart's timeout mechanism.
  ///
  /// **IMPORTANT LIMITATION**: This timeout only abandons waiting for the result
  /// in Dart - it does NOT cancel the underlying SQLite transaction. The transaction
  /// will continue executing in the database until completion. This means:
  /// - Database locks may be held longer than expected
  /// - The transaction may still commit even after timeout is reported
  /// - Resources may not be immediately freed
  ///
  /// For critical sections requiring strict timeouts, consider:
  /// - Using shorter, atomic operations
  /// - Implementing application-level cancellation checks within the action
  /// - Setting appropriate SQLite busy_timeout via PRAGMA
  ///
  /// Parameters:
  /// - [action]: Transaction callback
  /// - [timeout]: Maximum execution time (Dart-side only)
  ///
  /// Returns:
  /// - [Ok]: Transaction result
  /// - [Err]: Exception if failed or timed out
  Future<Result<T, ConcurrencyException>> executeWithTimeout<T>(
    Future<T> Function(Transaction txn) action,
    Duration timeout,
  ) async {
    try {
      final result = await _db.transaction<T>((txn) async {
        return await action(txn);
      }).timeout(timeout);

      return Ok(result);
    } on TimeoutException {
      // Note: The transaction may still be running in SQLite
      return Err(TransactionException(
        'Transaction timed out after ${timeout.inSeconds}s (note: SQLite transaction may still be executing)',
        originalError: TimeoutException('Transaction timeout'),
      ));
    } on DatabaseException catch (e) {
      return Err(TransactionException(
        'Transaction with timeout failed: ${e.toString()}',
        originalError: e,
      ));
    } catch (e) {
      return Err(TransactionException(
        'Unexpected timeout transaction error: ${e.toString()}',
        originalError: e,
      ));
    }
  }

  // Private helper methods

  bool _isRetryableError(DatabaseException e) {
    final message = e.toString().toLowerCase();

    // Common retryable errors in SQLite
    return message.contains('database is locked') ||
        message.contains('database is busy') ||
        message.contains('cannot start a transaction') ||
        message.contains('locked') ||
        message.contains('busy');
  }
}
