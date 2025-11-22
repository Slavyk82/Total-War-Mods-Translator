import '../../../models/common/service_exception.dart';

/// Base exception for concurrency service errors
class ConcurrencyException extends ServiceException {
  const ConcurrencyException(super.message, {super.code, super.details});
}

/// Resource is already locked by another owner
class ResourceLockedException extends ConcurrencyException {
  ResourceLockedException(
    super.message, {
    String? resourceId,
    String? lockedBy,
    DateTime? expiresAt,
  }) : super(
          code: 'RESOURCE_LOCKED',
          details: {
            'resource_id': resourceId,
            'locked_by': lockedBy,
            'expires_at': expiresAt?.toIso8601String(),
          },
        );
}

/// Lock not found
class LockNotFoundException extends ConcurrencyException {
  LockNotFoundException(super.message, {String? lockId})
      : super(
          code: 'LOCK_NOT_FOUND',
          details: {'lock_id': lockId},
        );
}

/// Lock has expired
class LockExpiredException extends ConcurrencyException {
  LockExpiredException(
    super.message, {
    String? lockId,
    DateTime? expiredAt,
  }) : super(
          code: 'LOCK_EXPIRED',
          details: {
            'lock_id': lockId,
            'expired_at': expiredAt?.toIso8601String(),
          },
        );
}

/// Lock is owned by a different entity
class LockOwnershipException extends ConcurrencyException {
  LockOwnershipException(
    super.message, {
    String? lockId,
    String? actualOwner,
    String? attemptedOwner,
  }) : super(
          code: 'LOCK_OWNERSHIP_ERROR',
          details: {
            'lock_id': lockId,
            'actual_owner': actualOwner,
            'attempted_owner': attemptedOwner,
          },
        );
}

/// Deadlock detected
class DeadlockException extends ConcurrencyException {
  DeadlockException(super.message, {List<String>? involvedLocks})
      : super(
          code: 'DEADLOCK_DETECTED',
          details: {'involved_locks': involvedLocks},
        );
}

/// Version conflict (optimistic locking)
class VersionConflictException extends ConcurrencyException {
  VersionConflictException(
    super.message, {
    String? resourceId,
    int? expectedVersion,
    int? actualVersion,
  }) : super(
          code: 'VERSION_CONFLICT',
          details: {
            'resource_id': resourceId,
            'expected_version': expectedVersion,
            'actual_version': actualVersion,
          },
        );
}

/// Data conflict detected between concurrent modifications
class DataConflictException extends ConcurrencyException {
  DataConflictException(
    super.message, {
    String? resourceId,
    String? conflictType,
  }) : super(
          code: 'DATA_CONFLICT',
          details: {
            'resource_id': resourceId,
            'conflict_type': conflictType,
          },
        );
}

/// Batch reservation conflict
class BatchReservationException extends ConcurrencyException {
  BatchReservationException(
    super.message, {
    String? unitId,
    String? reservedByBatch,
  }) : super(
          code: 'BATCH_RESERVATION_CONFLICT',
          details: {
            'unit_id': unitId,
            'reserved_by_batch': reservedByBatch,
          },
        );
}

/// Transaction failed or rolled back
class TransactionException extends ConcurrencyException {
  TransactionException(
    super.message, {
    String? transactionId,
    Object? originalError,
  }) : super(
          code: 'TRANSACTION_ERROR',
          details: {
            'transaction_id': transactionId,
            'original_error': originalError?.toString(),
          },
        );
}

/// Maximum retry attempts exceeded
class MaxRetriesExceededException extends ConcurrencyException {
  MaxRetriesExceededException(
    super.message, {
    int? maxRetries,
    int? attemptsMade,
  }) : super(
          code: 'MAX_RETRIES_EXCEEDED',
          details: {
            'max_retries': maxRetries,
            'attempts_made': attemptsMade,
          },
        );
}

/// Conflict resolution failed
class ConflictResolutionException extends ConcurrencyException {
  ConflictResolutionException(
    super.message, {
    String? conflictId,
    String? reason,
  }) : super(
          code: 'CONFLICT_RESOLUTION_FAILED',
          details: {
            'conflict_id': conflictId,
            'reason': reason,
          },
        );
}

/// Lock renewal failed
class LockRenewalException extends ConcurrencyException {
  LockRenewalException(
    super.message, {
    String? lockId,
    String? reason,
  }) : super(
          code: 'LOCK_RENEWAL_FAILED',
          details: {
            'lock_id': lockId,
            'reason': reason,
          },
        );
}
