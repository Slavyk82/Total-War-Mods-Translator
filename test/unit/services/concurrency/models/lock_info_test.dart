import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/concurrency/models/lock_info.dart';

LockInfo _lock({
  LockStatus status = LockStatus.active,
  required DateTime expiresAt,
}) =>
    LockInfo(
      id: 'l1',
      lockType: LockType.pessimistic,
      resourceId: 'r1',
      resourceType: 'translation_unit',
      ownerId: 'u1',
      ownerType: 'user',
      status: status,
      acquiredAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
    );

void main() {
  final future = DateTime.now().add(const Duration(minutes: 10));
  final past = DateTime.now().subtract(const Duration(minutes: 10));

  group('LockInfo.isActive / isExpired / timeRemaining', () {
    test('an active lock that has not expired is active and not expired', () {
      final lock = _lock(expiresAt: future);
      expect(lock.isActive, isTrue);
      expect(lock.isExpired, isFalse);
      expect(lock.timeRemaining, greaterThan(Duration.zero));
    });

    test('an active lock past its expiry is expired, not active', () {
      final lock = _lock(expiresAt: past);
      expect(lock.isActive, isFalse);
      expect(lock.isExpired, isTrue);
      expect(lock.timeRemaining, Duration.zero);
    });

    test('a released lock is neither active nor expired', () {
      final lock = _lock(status: LockStatus.released, expiresAt: future);
      expect(lock.isActive, isFalse);
      expect(lock.isExpired, isFalse);
      expect(lock.timeRemaining, Duration.zero);
    });

    test('a lock with explicit expired status reports expired', () {
      final lock = _lock(status: LockStatus.expired, expiresAt: future);
      expect(lock.isExpired, isTrue);
    });
  });

  group('LockInfo copyWith / equality / json', () {
    test('copyWith overrides only the given field', () {
      final lock = _lock(expiresAt: future);
      final broken = lock.copyWith(status: LockStatus.broken);

      expect(broken.status, LockStatus.broken);
      expect(broken.id, lock.id);
      expect(broken, isNot(equals(lock)));
    });

    test('value equality holds for identical field sets', () {
      final a = _lock(expiresAt: future);
      final b = _lock(expiresAt: future);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('round-trips through json', () {
      final lock = _lock(expiresAt: future);
      final restored = LockInfo.fromJson(lock.toJson());
      expect(restored.id, lock.id);
      expect(restored.lockType, LockType.pessimistic);
      expect(restored.status, LockStatus.active);
    });
  });

  group('LockRequest', () {
    test('applies sensible defaults', () {
      const req = LockRequest(
        resourceId: 'r',
        resourceType: 'unit',
        ownerId: 'u',
        ownerType: 'user',
      );
      expect(req.lockType, LockType.pessimistic);
      expect(req.timeout, const Duration(minutes: 5));
      expect(req.force, isFalse);
    });

    test('round-trips through json', () {
      const req = LockRequest(
        resourceId: 'r',
        resourceType: 'unit',
        ownerId: 'u',
        ownerType: 'user',
        force: true,
      );
      final restored = LockRequest.fromJson(req.toJson());
      expect(restored.resourceId, 'r');
      expect(restored.force, isTrue);
    });
  });

  group('BatchReservation', () {
    BatchReservation res({String status = 'active', required DateTime expiresAt}) =>
        BatchReservation(
          id: 'b1',
          batchId: 'batch',
          translationUnitId: 'tu',
          languageCode: 'fr',
          reservedAt: DateTime(2026, 1, 1),
          expiresAt: expiresAt,
          status: status,
        );

    test('is active only when status is active and not expired', () {
      expect(res(expiresAt: future).isActive, isTrue);
      expect(res(expiresAt: past).isActive, isFalse);
      expect(res(status: 'released', expiresAt: future).isActive, isFalse);
    });

    test('copyWith + equality + json', () {
      final a = res(expiresAt: future);
      expect(a.copyWith(status: 'expired').status, 'expired');
      expect(a, equals(res(expiresAt: future)));
      expect(BatchReservation.fromJson(a.toJson()).batchId, 'batch');
    });
  });
}
