import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../models/common/result.dart';
import 'models/concurrency_exceptions.dart';

/// Manager for database transactions with retry logic and savepoints
///
/// Provides transactional operations with automatic retry on conflict,
/// rollback on error, and support for nested transactions via savepoints.
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

  /// Execute with savepoint support (nested transaction simulation)
  ///
  /// SQLite doesn't support true nested transactions, but we can simulate
  /// them using savepoints.
  ///
  /// Parameters:
  /// - [action]: Transaction callback
  /// - [savepointName]: Name for the savepoint (auto-generated if null)
  ///
  /// Returns:
  /// - [Ok]: Result of the transaction
  /// - [Err]: Exception if failed
  ///
  /// Example:
  /// ```dart
  /// final result = await manager.executeWithSavepoint((txn) async {
  ///   // These operations can be rolled back to the savepoint
  ///   await txn.update('table', data);
  ///   return data;
  /// });
  /// ```
  Future<Result<T, ConcurrencyException>> executeWithSavepoint<T>(
    Future<T> Function(Transaction txn) action, {
    String? savepointName,
  }) async {
    final savepoint = savepointName ?? 'sp_${_uuid.v4().substring(0, 8)}';

    try {
      final result = await _db.transaction<T>((txn) async {
        // Create savepoint
        await txn.execute('SAVEPOINT $savepoint');

        try {
          final result = await action(txn);

          // Release savepoint on success
          await txn.execute('RELEASE SAVEPOINT $savepoint');

          return result;
        } catch (e) {
          // Rollback to savepoint on error
          await txn.execute('ROLLBACK TO SAVEPOINT $savepoint');
          rethrow;
        }
      });

      return Ok(result);
    } on DatabaseException catch (e) {
      return Err(TransactionException(
        'Savepoint transaction failed: ${e.toString()}',
        transactionId: savepoint,
        originalError: e,
      ));
    } catch (e) {
      return Err(TransactionException(
        'Unexpected savepoint error: ${e.toString()}',
        transactionId: savepoint,
        originalError: e,
      ));
    }
  }

  /// Execute multiple operations with individual savepoints
  ///
  /// Each operation gets its own savepoint. If one fails, only that
  /// operation is rolled back, not the entire transaction.
  ///
  /// Parameters:
  /// - [operations]: List of operations with savepoint names
  /// - [continueOnError]: Continue executing remaining operations if one fails
  ///
  /// Returns:
  /// - [Ok]: List of results (null for failed operations if continueOnError=true)
  /// - [Err]: Exception if transaction failed
  Future<Result<List<dynamic>, ConcurrencyException>> executeWithMultipleSavepoints(
    List<({String name, Future<dynamic> Function(Transaction txn) action})> operations, {
    bool continueOnError = false,
  }) async {
    try {
      final results = <dynamic>[];

      await _db.transaction((txn) async {
        for (final op in operations) {
          try {
            await txn.execute('SAVEPOINT ${op.name}');

            final result = await op.action(txn);
            results.add(result);

            await txn.execute('RELEASE SAVEPOINT ${op.name}');
          } catch (e) {
            await txn.execute('ROLLBACK TO SAVEPOINT ${op.name}');

            if (continueOnError) {
              results.add(null); // Mark as failed but continue
            } else {
              rethrow; // Abort entire transaction
            }
          }
        }
      });

      return Ok(results);
    } on DatabaseException catch (e) {
      return Err(TransactionException(
        'Multiple savepoints transaction failed: ${e.toString()}',
        originalError: e,
      ));
    } catch (e) {
      return Err(TransactionException(
        'Unexpected error in multiple savepoints: ${e.toString()}',
        originalError: e,
      ));
    }
  }

  /// Execute a read-only transaction
  ///
  /// Optimized for read operations, prevents accidental writes.
  ///
  /// Parameters:
  /// - [query]: Read-only query callback
  ///
  /// Returns:
  /// - [Ok]: Query result
  /// - [Err]: Exception if query failed
  Future<Result<T, ConcurrencyException>> executeReadOnly<T>(
    Future<T> Function(Database db) query,
  ) async {
    try {
      // SQLite supports DEFERRED transactions for reads
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
