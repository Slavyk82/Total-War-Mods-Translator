import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';

void main() {
  test('base ConcurrencyException carries message and code', () {
    const e = ConcurrencyException('boom', code: 'X');
    expect(e.message, 'boom');
    expect(e.code, 'X');
  });

  test('each subtype sets its documented code + details', () {
    final cases = <ConcurrencyException, String>{
      ResourceLockedException('m', resourceId: 'r', lockedBy: 'u'):
          'RESOURCE_LOCKED',
      LockNotFoundException('m', lockId: 'l'): 'LOCK_NOT_FOUND',
      LockExpiredException('m', lockId: 'l'): 'LOCK_EXPIRED',
      LockOwnershipException('m', lockId: 'l', actualOwner: 'a'):
          'LOCK_OWNERSHIP_ERROR',
      DeadlockException('m', involvedLocks: ['a', 'b']): 'DEADLOCK_DETECTED',
      VersionConflictException('m', expectedVersion: 1, actualVersion: 2):
          'VERSION_CONFLICT',
      DataConflictException('m', conflictType: 'merge'): 'DATA_CONFLICT',
      BatchReservationException('m', unitId: 'u'): 'BATCH_RESERVATION_CONFLICT',
      TransactionException('m', transactionId: 't'): 'TRANSACTION_ERROR',
      MaxRetriesExceededException('m', maxRetries: 3, attemptsMade: 3):
          'MAX_RETRIES_EXCEEDED',
      ConflictResolutionException('m', conflictId: 'c'):
          'CONFLICT_RESOLUTION_FAILED',
      LockRenewalException('m', lockId: 'l'): 'LOCK_RENEWAL_FAILED',
    };

    cases.forEach((exception, expectedCode) {
      expect(exception.message, 'm');
      expect(exception.code, expectedCode);
      expect(exception.details, isA<Map>());
    });
  });

  test('VersionConflictException records the version delta in details', () {
    final e = VersionConflictException('conflict',
        resourceId: 'r', expectedVersion: 5, actualVersion: 7);
    final details = e.details as Map;
    expect(details['expected_version'], 5);
    expect(details['actual_version'], 7);
  });
}
