import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../models/common/result.dart';
import 'models/lock_info.dart';
import 'models/concurrency_exceptions.dart';

/// Manager for pessimistic locks on translation entries
///
/// Prevents concurrent editing of the same entry by multiple users or
/// simultaneous manual editing and batch translation.
///
/// Locks are automatically released after a timeout (default: 5 minutes)
/// to prevent deadlocks from crashed sessions.
class PessimisticLockManager {
  final Uuid _uuid;

  /// Default lock timeout (5 minutes)
  static const Duration defaultTimeout = Duration(minutes: 5);

  /// Maximum lock timeout (30 minutes)
  static const Duration maxTimeout = Duration(minutes: 30);

  PessimisticLockManager({
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  Database get _db => DatabaseService.database;

  /// Acquire a lock on a resource
  ///
  /// Parameters:
  /// - [request]: Lock request with resource info and owner details
  ///
  /// Returns:
  /// - [Ok]: LockInfo if lock acquired successfully
  /// - [Err]: Exception if lock failed
  ///   - [ResourceLockedException]: If resource is already locked
  ///   - [ConcurrencyException]: If database error occurred
  ///
  /// Example:
  /// ```dart
  /// final request = LockRequest(
  ///   resourceId: 'translation_123',
  ///   resourceType: 'translation_version',
  ///   ownerId: 'user_456',
  ///   ownerType: 'user',
  ///   timeout: Duration(minutes: 10),
  /// );
  ///
  /// final result = await manager.acquireLock(request);
  /// if (result is Ok) {
  ///   print('Lock acquired: ${result.value.id}');
  /// }
  /// ```
  Future<Result<LockInfo, ConcurrencyException>> acquireLock(
    LockRequest request,
  ) async {
    try {
      // Clean up expired locks first (outside transaction - separate concern)
      await _cleanupExpiredLocks();

      // Use a transaction to make check-and-insert atomic
      // This prevents race conditions where two processes could both
      // see no lock exists and then both insert a new lock
      final result = await _db.transaction<Result<LockInfo, ConcurrencyException>>(
        (txn) async {
          // Check if resource is already locked (within transaction)
          final existingLockResults = await txn.query(
            'entry_locks',
            where: 'resource_id = ? AND resource_type = ? AND status = ?',
            whereArgs: [
              request.resourceId,
              request.resourceType,
              LockStatus.active.name,
            ],
            limit: 1,
          );

          LockInfo? existingLock;
          if (existingLockResults.isNotEmpty) {
            final parsed = _parseLock(existingLockResults.first);
            if (parsed.isActive) {
              existingLock = parsed;
            }
          }

          if (existingLock != null) {
            // Check if it's the same owner (lock renewal)
            if (existingLock.ownerId == request.ownerId &&
                existingLock.ownerType == request.ownerType) {
              // Renew the lock within the transaction
              final newExpiresAt = DateTime.now().add(_clampDuration(
                request.timeout,
                const Duration(minutes: 1),
                maxTimeout,
              ));

              await txn.update(
                'entry_locks',
                {'expires_at': newExpiresAt.millisecondsSinceEpoch},
                where: 'id = ?',
                whereArgs: [existingLock.id],
              );

              return Ok(existingLock.copyWith(expiresAt: newExpiresAt));
            }

            // Resource is locked by someone else
            if (!request.force) {
              return Err(ResourceLockedException(
                'Resource is already locked by ${existingLock.ownerType}:${existingLock.ownerId}',
                resourceId: request.resourceId,
                lockedBy: existingLock.ownerId,
                expiresAt: existingLock.expiresAt,
              ));
            }

            // Force flag: break existing lock within transaction
            await txn.update(
              'entry_locks',
              {
                'status': LockStatus.broken.name,
                'released_at': DateTime.now().millisecondsSinceEpoch,
                'reason': 'Forced by ${request.ownerId}',
              },
              where: 'id = ?',
              whereArgs: [existingLock.id],
            );
          }

          // Create new lock (within transaction - atomic with check above)
          final lockId = _uuid.v4();
          final now = DateTime.now();
          final timeout = _clampDuration(
            request.timeout,
            const Duration(minutes: 1),
            maxTimeout,
          );
          final expiresAt = now.add(timeout);

          await txn.insert('entry_locks', {
            'id': lockId,
            'lock_type': request.lockType.name,
            'resource_id': request.resourceId,
            'resource_type': request.resourceType,
            'owner_id': request.ownerId,
            'owner_type': request.ownerType,
            'status': LockStatus.active.name,
            'acquired_at': now.millisecondsSinceEpoch,
            'expires_at': expiresAt.millisecondsSinceEpoch,
            'reason': request.reason,
          });

          final lock = LockInfo(
            id: lockId,
            lockType: request.lockType,
            resourceId: request.resourceId,
            resourceType: request.resourceType,
            ownerId: request.ownerId,
            ownerType: request.ownerType,
            status: LockStatus.active,
            acquiredAt: now,
            expiresAt: expiresAt,
            reason: request.reason,
          );

          return Ok(lock);
        },
      );

      return result;
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to acquire lock: ${e.toString()}',
        code: 'LOCK_ACQUIRE_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error acquiring lock: ${e.toString()}',
        code: 'LOCK_ACQUIRE_ERROR',
      ));
    }
  }

  /// Release a lock
  ///
  /// Parameters:
  /// - [lockId]: Lock ID to release
  /// - [ownerId]: Owner ID (for validation)
  ///
  /// Returns:
  /// - [Ok]: true if lock released successfully
  /// - [Err]: Exception if release failed
  Future<Result<bool, ConcurrencyException>> releaseLock(
    String lockId,
    String ownerId,
  ) async {
    try {
      // Get lock info
      final lockResult = await getLockInfo(lockId);
      if (lockResult is Err) {
        return Err(lockResult.error);
      }

      final lock = (lockResult as Ok<LockInfo, ConcurrencyException>).value;

      // Verify ownership
      if (lock.ownerId != ownerId) {
        return Err(LockOwnershipException(
          'Lock is owned by ${lock.ownerId}, cannot be released by $ownerId',
          lockId: lockId,
          actualOwner: lock.ownerId,
          attemptedOwner: ownerId,
        ));
      }

      // Release lock
      final count = await _db.update(
        'entry_locks',
        {
          'status': LockStatus.released.name,
          'released_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [lockId],
      );

      return Ok(count > 0);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to release lock: ${e.toString()}',
        code: 'LOCK_RELEASE_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error releasing lock: ${e.toString()}',
        code: 'LOCK_RELEASE_ERROR',
      ));
    }
  }

  /// Renew a lock (extend expiration time)
  ///
  /// Parameters:
  /// - [lockId]: Lock ID to renew
  /// - [extension]: Additional time to add (default: 5 minutes)
  ///
  /// Returns:
  /// - [Ok]: Updated LockInfo
  /// - [Err]: Exception if renewal failed
  Future<Result<LockInfo, ConcurrencyException>> renewLock(
    String lockId,
    Duration extension,
  ) async {
    return await _renewLock(lockId, extension);
  }

  /// Get information about a lock
  ///
  /// Parameters:
  /// - [lockId]: Lock ID
  ///
  /// Returns:
  /// - [Ok]: LockInfo if found
  /// - [Err]: [LockNotFoundException] if not found
  Future<Result<LockInfo, ConcurrencyException>> getLockInfo(
    String lockId,
  ) async {
    try {
      final results = await _db.query(
        'entry_locks',
        where: 'id = ?',
        whereArgs: [lockId],
      );

      if (results.isEmpty) {
        return Err(LockNotFoundException(
          'Lock not found',
          lockId: lockId,
        ));
      }

      final lock = _parseLock(results.first);
      return Ok(lock);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get lock info: ${e.toString()}',
        code: 'LOCK_INFO_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting lock info: ${e.toString()}',
        code: 'LOCK_INFO_ERROR',
      ));
    }
  }

  /// Check if a resource is locked
  ///
  /// Parameters:
  /// - [resourceId]: Resource ID
  /// - [resourceType]: Resource type
  ///
  /// Returns:
  /// - [Ok]: LockInfo if locked, null if not locked
  /// - [Err]: Exception if check failed
  Future<Result<LockInfo?, ConcurrencyException>> checkLock(
    String resourceId,
    String resourceType,
  ) async {
    try {
      await _cleanupExpiredLocks();

      final lock = await _getActiveLock(resourceId, resourceType);
      return Ok(lock);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to check lock: ${e.toString()}',
        code: 'LOCK_CHECK_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error checking lock: ${e.toString()}',
        code: 'LOCK_CHECK_ERROR',
      ));
    }
  }

  /// Get all active locks for an owner
  ///
  /// Useful for cleanup when a user session ends.
  Future<Result<List<LockInfo>, ConcurrencyException>> getOwnerLocks(
    String ownerId,
    String ownerType,
  ) async {
    try {
      await _cleanupExpiredLocks();

      final results = await _db.query(
        'entry_locks',
        where: 'owner_id = ? AND owner_type = ? AND status = ?',
        whereArgs: [ownerId, ownerType, LockStatus.active.name],
      );

      final locks = results.map(_parseLock).toList();
      return Ok(locks);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to get owner locks: ${e.toString()}',
        code: 'OWNER_LOCKS_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error getting owner locks: ${e.toString()}',
        code: 'OWNER_LOCKS_ERROR',
      ));
    }
  }

  /// Release all locks for an owner
  ///
  /// Called when a user session ends or batch completes.
  Future<Result<int, ConcurrencyException>> releaseOwnerLocks(
    String ownerId,
    String ownerType,
  ) async {
    try {
      final count = await _db.update(
        'entry_locks',
        {
          'status': LockStatus.released.name,
          'released_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'owner_id = ? AND owner_type = ? AND status = ?',
        whereArgs: [ownerId, ownerType, LockStatus.active.name],
      );

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to release owner locks: ${e.toString()}',
        code: 'OWNER_LOCKS_RELEASE_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error releasing owner locks: ${e.toString()}',
        code: 'OWNER_LOCKS_RELEASE_ERROR',
      ));
    }
  }

  /// Clean up expired locks
  ///
  /// Called periodically to mark expired locks as such.
  Future<Result<int, ConcurrencyException>> cleanupExpiredLocks() async {
    return await _cleanupExpiredLocks();
  }

  /// Break a lock (force release)
  ///
  /// Should only be used in exceptional circumstances (e.g., admin action).
  Future<Result<bool, ConcurrencyException>> breakLock(
    String lockId,
    String reason,
  ) async {
    return await _breakLock(lockId, reason);
  }

  // Private helper methods

  Future<LockInfo?> _getActiveLock(
    String resourceId,
    String resourceType,
  ) async {
    final results = await _db.query(
      'entry_locks',
      where: 'resource_id = ? AND resource_type = ? AND status = ?',
      whereArgs: [resourceId, resourceType, LockStatus.active.name],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final lock = _parseLock(results.first);
    return lock.isActive ? lock : null;
  }

  Future<Result<LockInfo, ConcurrencyException>> _renewLock(
    String lockId,
    Duration extension,
  ) async {
    try {
      final lockResult = await getLockInfo(lockId);
      if (lockResult is Err) {
        return Err(lockResult.error);
      }

      final lock = (lockResult as Ok<LockInfo, ConcurrencyException>).value;

      if (lock.isExpired) {
        return Err(LockExpiredException(
          'Lock has expired',
          lockId: lockId,
          expiredAt: lock.expiresAt,
        ));
      }

      final newExpiresAt = DateTime.now().add(_clampDuration(
        extension,
        const Duration(minutes: 1),
        maxTimeout,
      ));

      await _db.update(
        'entry_locks',
        {'expires_at': newExpiresAt.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [lockId],
      );

      return Ok(lock.copyWith(expiresAt: newExpiresAt));
    } on DatabaseException catch (e) {
      return Err(LockRenewalException(
        'Failed to renew lock: ${e.toString()}',
        lockId: lockId,
        reason: e.toString(),
      ));
    } catch (e) {
      return Err(LockRenewalException(
        'Unexpected error renewing lock: ${e.toString()}',
        lockId: lockId,
        reason: e.toString(),
      ));
    }
  }

  Future<Result<int, ConcurrencyException>> _cleanupExpiredLocks() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final count = await _db.update(
        'entry_locks',
        {'status': LockStatus.expired.name},
        where: 'status = ? AND expires_at < ?',
        whereArgs: [LockStatus.active.name, now],
      );

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to cleanup expired locks: ${e.toString()}',
        code: 'LOCK_CLEANUP_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error cleaning up locks: ${e.toString()}',
        code: 'LOCK_CLEANUP_ERROR',
      ));
    }
  }

  Future<Result<bool, ConcurrencyException>> _breakLock(
    String lockId,
    String reason,
  ) async {
    try {
      final count = await _db.update(
        'entry_locks',
        {
          'status': LockStatus.broken.name,
          'released_at': DateTime.now().millisecondsSinceEpoch,
          'reason': reason,
        },
        where: 'id = ?',
        whereArgs: [lockId],
      );

      return Ok(count > 0);
    } on DatabaseException catch (e) {
      return Err(ConcurrencyException(
        'Failed to break lock: ${e.toString()}',
        code: 'LOCK_BREAK_FAILED',
      ));
    } catch (e) {
      return Err(ConcurrencyException(
        'Unexpected error breaking lock: ${e.toString()}',
        code: 'LOCK_BREAK_ERROR',
      ));
    }
  }

  LockInfo _parseLock(Map<String, dynamic> row) {
    return LockInfo(
      id: row['id'] as String,
      lockType: LockType.values.firstWhere(
        (t) => t.name == row['lock_type'],
        orElse: () => LockType.pessimistic,
      ),
      resourceId: row['resource_id'] as String,
      resourceType: row['resource_type'] as String,
      ownerId: row['owner_id'] as String,
      ownerType: row['owner_type'] as String,
      status: LockStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => LockStatus.active,
      ),
      acquiredAt: DateTime.fromMillisecondsSinceEpoch(row['acquired_at'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row['expires_at'] as int),
      releasedAt: row['released_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['released_at'] as int)
          : null,
      reason: row['reason'] as String?,
    );
  }

  /// Helper to clamp Duration values
  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
