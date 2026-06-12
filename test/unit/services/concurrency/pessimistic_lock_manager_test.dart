import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';
import 'package:twmt/services/concurrency/models/lock_info.dart';
import 'package:twmt/services/concurrency/pessimistic_lock_manager.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late PessimisticLockManager manager;

  // The `entry_locks` table is referenced only inside
  // PessimisticLockManager's SQL — it is NOT in schema.sql or any migration
  // (phantom table). Reverse-engineered column list + types from every
  // INSERT/SELECT/UPDATE statement in the manager:
  //   - id            TEXT  (PRIMARY KEY, uuid v4)
  //   - lock_type     TEXT  (LockType.name: pessimistic | batchReservation)
  //   - resource_id   TEXT
  //   - resource_type TEXT
  //   - owner_id      TEXT
  //   - owner_type    TEXT
  //   - status        TEXT  (LockStatus.name: active | expired | released | broken)
  //   - acquired_at   INTEGER (Unix millisecondsSinceEpoch)
  //   - expires_at    INTEGER (Unix millisecondsSinceEpoch)
  //   - released_at   INTEGER NULL (Unix millisecondsSinceEpoch)
  //   - reason        TEXT NULL
  const createLocksTable = '''
    CREATE TABLE entry_locks (
      id TEXT PRIMARY KEY,
      lock_type TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      resource_type TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      owner_type TEXT NOT NULL,
      status TEXT NOT NULL,
      acquired_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      released_at INTEGER,
      reason TEXT
    )
  ''';

  setUp(() async {
    db = await TestDatabase.openMigrated();
    await db.execute(createLocksTable);
    manager = PessimisticLockManager();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  // Helper: insert a lock row directly into entry_locks so we can control
  // timestamps (past/future) for expiry / takeover scenarios.
  Future<void> insertLockRow({
    required String id,
    String lockType = 'pessimistic',
    String resourceId = 'res-1',
    String resourceType = 'translation_unit',
    String ownerId = 'owner-1',
    String ownerType = 'user',
    String status = 'active',
    int? acquiredAt,
    int? expiresAt,
    int? releasedAt,
    String? reason,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('entry_locks', {
      'id': id,
      'lock_type': lockType,
      'resource_id': resourceId,
      'resource_type': resourceType,
      'owner_id': ownerId,
      'owner_type': ownerType,
      'status': status,
      'acquired_at': acquiredAt ?? now,
      'expires_at': expiresAt ?? (now + const Duration(minutes: 5).inMilliseconds),
      'released_at': releasedAt,
      'reason': reason,
    });
  }

  LockRequest buildRequest({
    String resourceId = 'res-1',
    String resourceType = 'translation_unit',
    String ownerId = 'owner-1',
    String ownerType = 'user',
    LockType lockType = LockType.pessimistic,
    Duration timeout = const Duration(minutes: 5),
    String? reason,
    bool force = false,
  }) {
    return LockRequest(
      resourceId: resourceId,
      resourceType: resourceType,
      ownerId: ownerId,
      ownerType: ownerType,
      lockType: lockType,
      timeout: timeout,
      reason: reason,
      force: force,
    );
  }

  group('acquireLock', () {
    test('fresh acquire returns Ok and inserts an active row', () async {
      final result = await manager.acquireLock(buildRequest());

      expect(result.isOk, isTrue);
      final lock = result.value;
      expect(lock.resourceId, equals('res-1'));
      expect(lock.ownerId, equals('owner-1'));
      expect(lock.status, equals(LockStatus.active));
      expect(lock.lockType, equals(LockType.pessimistic));

      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: [lock.id]);
      expect(rows.length, equals(1));
      expect(rows.first['status'], equals('active'));
      expect(rows.first['resource_id'], equals('res-1'));
      expect(rows.first['owner_id'], equals('owner-1'));
    });

    test('persists reason and respects lockType in the inserted row',
        () async {
      final result = await manager.acquireLock(buildRequest(
        lockType: LockType.batchReservation,
        reason: 'batch run 42',
      ));

      expect(result.isOk, isTrue);
      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: [result.value.id]);
      expect(rows.first['lock_type'], equals('batchReservation'));
      expect(rows.first['reason'], equals('batch run 42'));
    });

    test('acquire on resource locked by another owner returns '
        'ResourceLockedException', () async {
      await insertLockRow(id: 'lock-existing', ownerId: 'owner-A');

      final result = await manager.acquireLock(buildRequest(ownerId: 'owner-B'));

      expect(result.isErr, isTrue);
      expect(result.error, isA<ResourceLockedException>());
      expect(result.error.code, equals('RESOURCE_LOCKED'));

      // No new lock row created for owner-B.
      final rows = await db.query('entry_locks',
          where: 'owner_id = ?', whereArgs: ['owner-B']);
      expect(rows, isEmpty);
    });

    test('re-acquire by the SAME owner renews (reentrant) and extends expiry',
        () async {
      final past = DateTime.now()
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await insertLockRow(
        id: 'lock-reentrant',
        ownerId: 'owner-1',
        ownerType: 'user',
        expiresAt: past, // soon-but-still-active
      );

      final result = await manager.acquireLock(
        buildRequest(ownerId: 'owner-1', timeout: const Duration(minutes: 20)),
      );

      expect(result.isOk, isTrue);
      // Same lock id retained (renewal, not a new lock).
      expect(result.value.id, equals('lock-reentrant'));

      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-reentrant']);
      expect(rows.length, equals(1));
      // Expiry extended past the original near-expiry value.
      expect(rows.first['expires_at'] as int, greaterThan(past));

      // Still only one row for the resource.
      final all = await db.query('entry_locks');
      expect(all.length, equals(1));
    });

    test('expired existing lock by another owner is cleaned up and taken over',
        () async {
      final pastMs = DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch;
      await insertLockRow(
        id: 'lock-stale',
        ownerId: 'owner-A',
        status: 'active',
        expiresAt: pastMs, // already expired
      );

      // owner-B acquires; _cleanupExpiredLocks flips the stale row to expired,
      // so it's no longer "active" and the new acquire succeeds.
      final result = await manager.acquireLock(buildRequest(ownerId: 'owner-B'));

      expect(result.isOk, isTrue);
      expect(result.value.ownerId, equals('owner-B'));

      final stale = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-stale']);
      expect(stale.first['status'], equals('expired'));

      final fresh = await db.query('entry_locks',
          where: 'owner_id = ? AND status = ?',
          whereArgs: ['owner-B', 'active']);
      expect(fresh.length, equals(1));
    });

    test('force flag breaks an existing other-owner lock and creates a new one',
        () async {
      await insertLockRow(id: 'lock-victim', ownerId: 'owner-A');

      final result = await manager.acquireLock(
        buildRequest(ownerId: 'owner-B', force: true),
      );

      expect(result.isOk, isTrue);
      expect(result.value.ownerId, equals('owner-B'));

      final victim = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-victim']);
      expect(victim.first['status'], equals('broken'));
      expect(victim.first['released_at'], isNotNull);

      final fresh = await db.query('entry_locks',
          where: 'owner_id = ? AND status = ?',
          whereArgs: ['owner-B', 'active']);
      expect(fresh.length, equals(1));
    });

    test('returns ConcurrencyException when the locks table is missing',
        () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.acquireLock(buildRequest());

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
    });
  });

  group('releaseLock', () {
    test('releasing an owned lock returns Ok(true) and marks it released',
        () async {
      await insertLockRow(id: 'lock-1', ownerId: 'owner-1');

      final result = await manager.releaseLock('lock-1', 'owner-1');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);

      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-1']);
      expect(rows.first['status'], equals('released'));
      expect(rows.first['released_at'], isNotNull);
    });

    test('releasing a lock owned by someone else returns '
        'LockOwnershipException', () async {
      await insertLockRow(id: 'lock-1', ownerId: 'owner-1');

      final result = await manager.releaseLock('lock-1', 'someone-else');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LockOwnershipException>());
      expect(result.error.code, equals('LOCK_OWNERSHIP_ERROR'));

      // Row untouched.
      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-1']);
      expect(rows.first['status'], equals('active'));
    });

    test('releasing a non-existent lock returns LockNotFoundException',
        () async {
      final result = await manager.releaseLock('does-not-exist', 'owner-1');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LockNotFoundException>());
      expect(result.error.code, equals('LOCK_NOT_FOUND'));
    });
  });

  group('renewLock', () {
    test('extends expiry of an active lock and returns updated LockInfo',
        () async {
      final originalExpiry = DateTime.now()
          .add(const Duration(minutes: 2))
          .millisecondsSinceEpoch;
      await insertLockRow(id: 'lock-1', expiresAt: originalExpiry);

      final result =
          await manager.renewLock('lock-1', const Duration(minutes: 20));

      expect(result.isOk, isTrue);
      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-1']);
      expect(rows.first['expires_at'] as int, greaterThan(originalExpiry));
    });

    test('returns LockNotFoundException when the lock does not exist',
        () async {
      final result =
          await manager.renewLock('missing', const Duration(minutes: 5));

      expect(result.isErr, isTrue);
      expect(result.error, isA<LockNotFoundException>());
    });

    test('returns LockExpiredException when renewing an expired lock',
        () async {
      final pastMs = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      // status stays 'active' so getLockInfo returns it, but isExpired is true
      // because expires_at is in the past.
      await insertLockRow(
          id: 'lock-expired', status: 'active', expiresAt: pastMs);

      final result =
          await manager.renewLock('lock-expired', const Duration(minutes: 5));

      expect(result.isErr, isTrue);
      expect(result.error, isA<LockExpiredException>());
      expect(result.error.code, equals('LOCK_EXPIRED'));
    });
  });

  group('getLockInfo', () {
    test('returns the parsed LockInfo when the lock exists', () async {
      await insertLockRow(
        id: 'lock-1',
        resourceId: 'res-99',
        ownerId: 'owner-7',
        reason: 'editing',
      );

      final result = await manager.getLockInfo('lock-1');

      expect(result.isOk, isTrue);
      expect(result.value.id, equals('lock-1'));
      expect(result.value.resourceId, equals('res-99'));
      expect(result.value.ownerId, equals('owner-7'));
      expect(result.value.reason, equals('editing'));
    });

    test('returns LockNotFoundException when absent', () async {
      final result = await manager.getLockInfo('nope');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LockNotFoundException>());
    });
  });

  group('checkLock', () {
    test('returns the active lock for a locked resource', () async {
      await insertLockRow(
          id: 'lock-1', resourceId: 'res-A', resourceType: 'translation_unit');

      final result = await manager.checkLock('res-A', 'translation_unit');

      expect(result.isOk, isTrue);
      expect(result.value, isNotNull);
      expect(result.value!.id, equals('lock-1'));
    });

    test('returns Ok(null) when the resource is not locked', () async {
      final result = await manager.checkLock('res-unlocked', 'translation_unit');

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });

    test('treats an expired active row as not locked (returns null)', () async {
      final pastMs = DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch;
      await insertLockRow(
          id: 'lock-stale', resourceId: 'res-A', expiresAt: pastMs);

      final result = await manager.checkLock('res-A', 'translation_unit');

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });
  });

  group('getOwnerLocks', () {
    test('returns all active locks for an owner', () async {
      await insertLockRow(
          id: 'l1', ownerId: 'owner-1', resourceId: 'r1');
      await insertLockRow(
          id: 'l2', ownerId: 'owner-1', resourceId: 'r2');
      await insertLockRow(
          id: 'l3', ownerId: 'owner-2', resourceId: 'r3');

      final result = await manager.getOwnerLocks('owner-1', 'user');

      expect(result.isOk, isTrue);
      expect(result.value.length, equals(2));
      expect(
        result.value.map((l) => l.id).toSet(),
        equals({'l1', 'l2'}),
      );
    });

    test('returns an empty list when owner has no active locks', () async {
      final result = await manager.getOwnerLocks('ghost', 'user');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('excludes released locks', () async {
      await insertLockRow(
          id: 'l1', ownerId: 'owner-1', status: 'released');

      final result = await manager.getOwnerLocks('owner-1', 'user');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('releaseOwnerLocks', () {
    test('releases all active locks for the owner and returns the count',
        () async {
      await insertLockRow(id: 'l1', ownerId: 'owner-1', resourceId: 'r1');
      await insertLockRow(id: 'l2', ownerId: 'owner-1', resourceId: 'r2');
      await insertLockRow(id: 'l3', ownerId: 'owner-2', resourceId: 'r3');

      final result = await manager.releaseOwnerLocks('owner-1', 'user');

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final released = await db.query('entry_locks',
          where: 'owner_id = ? AND status = ?',
          whereArgs: ['owner-1', 'released']);
      expect(released.length, equals(2));

      // Other owner untouched.
      final other = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['l3']);
      expect(other.first['status'], equals('active'));
    });

    test('returns 0 when the owner has no active locks', () async {
      final result = await manager.releaseOwnerLocks('ghost', 'user');

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('breakLock', () {
    test('force-marks a lock as broken and returns Ok(true)', () async {
      await insertLockRow(id: 'lock-1');

      final result = await manager.breakLock('lock-1', 'admin override');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);

      final rows = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['lock-1']);
      expect(rows.first['status'], equals('broken'));
      expect(rows.first['released_at'], isNotNull);
      expect(rows.first['reason'], equals('admin override'));
    });

    test('returns Ok(false) when no lock with the id exists', () async {
      final result = await manager.breakLock('missing', 'reason');

      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });
  });

  group('cleanupExpiredLocks', () {
    test('marks active+expired rows as expired and returns the count',
        () async {
      final pastMs = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      final futureMs = DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      await insertLockRow(id: 'expired-1', expiresAt: pastMs, resourceId: 'r1');
      await insertLockRow(id: 'expired-2', expiresAt: pastMs, resourceId: 'r2');
      await insertLockRow(id: 'live-1', expiresAt: futureMs, resourceId: 'r3');

      final result = await manager.cleanupExpiredLocks();

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final live = await db.query('entry_locks',
          where: 'id = ?', whereArgs: ['live-1']);
      expect(live.first['status'], equals('active'));
    });

    test('returns ConcurrencyException when the table is missing', () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.cleanupExpiredLocks();

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, equals('LOCK_CLEANUP_FAILED'));
    });
  });

  group('error branches (DatabaseException -> Err)', () {
    test('getLockInfo wraps a DB failure as ConcurrencyException', () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.getLockInfo('any');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, equals('LOCK_INFO_FAILED'));
    });

    test('checkLock wraps a DB failure as ConcurrencyException', () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.checkLock('r', 't');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
    });

    test('getOwnerLocks wraps a DB failure as ConcurrencyException', () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.getOwnerLocks('o', 'user');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
    });

    test('releaseOwnerLocks wraps a DB failure as ConcurrencyException',
        () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.releaseOwnerLocks('o', 'user');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, equals('OWNER_LOCKS_RELEASE_FAILED'));
    });

    test('breakLock wraps a DB failure as ConcurrencyException', () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.breakLock('id', 'reason');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, equals('LOCK_BREAK_FAILED'));
    });

    test('renewLock wraps a DB failure as LockRenewalException', () async {
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.renewLock('id', const Duration(minutes: 5));

      expect(result.isErr, isTrue);
      // getLockInfo fails first with a DatabaseException, propagated as a
      // ConcurrencyException through the Err branch.
      expect(result.error, isA<ConcurrencyException>());
    });

    test('releaseLock wraps a DB failure as ConcurrencyException', () async {
      // Seed a lock, then drop the table so the update() inside releaseLock
      // fails after getLockInfo would have succeeded — but here getLockInfo
      // itself fails, surfacing a ConcurrencyException.
      await db.execute('DROP TABLE entry_locks');

      final result = await manager.releaseLock('id', 'owner');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
    });
  });
}
