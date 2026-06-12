import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/concurrency/batch_isolation_manager.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';
import 'package:twmt/services/concurrency/models/lock_info.dart';

import '../../../helpers/test_database.dart';

void main() {
  late Database db;
  late BatchIsolationManager manager;

  setUp(() async {
    db = await TestDatabase.openMigrated();

    // `batch_entry_reservations` is not part of schema.sql / migrations, so we
    // create it here. Columns are reverse-engineered from every INSERT, SELECT,
    // UPDATE and DELETE in BatchIsolationManager:
    //  - id, batch_id, translation_unit_id, language_code, status (TEXT)
    //  - reserved_at, expires_at, released_at (INTEGER epoch millis)
    //  - error_reason (TEXT, written by releaseUnitsOnError)
    await db.execute('''
      CREATE TABLE batch_entry_reservations (
        id TEXT PRIMARY KEY,
        batch_id TEXT NOT NULL,
        translation_unit_id TEXT NOT NULL,
        language_code TEXT NOT NULL,
        reserved_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        released_at INTEGER,
        status TEXT NOT NULL,
        error_reason TEXT
      )
    ''');

    manager = BatchIsolationManager();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<List<Map<String, Object?>>> rows({String? where, List<Object?>? args}) {
    return db.query('batch_entry_reservations', where: where, whereArgs: args);
  }

  group('reserveUnits', () {
    test('returns Ok with empty list when unitIds is empty (no DB writes)',
        () async {
      final result = await manager.reserveUnits('batch_1', const [], 'fr');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
      expect(await rows(), isEmpty);
    });

    test('reserves all units and inserts active rows', () async {
      final result =
          await manager.reserveUnits('batch_1', ['u1', 'u2', 'u3'], 'fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(['u1', 'u2', 'u3']));

      final inserted = await rows();
      expect(inserted.length, equals(3));
      for (final row in inserted) {
        expect(row['batch_id'], equals('batch_1'));
        expect(row['language_code'], equals('fr'));
        expect(row['status'], equals('active'));
        expect(row['id'], isNotNull);
        expect(row['reserved_at'], isA<int>());
        expect(row['expires_at'], isA<int>());
        // expires_at must be strictly after reserved_at (timeout is clamped to
        // a minimum of 5 minutes).
        expect(row['expires_at'] as int, greaterThan(row['reserved_at'] as int));
      }
    });

    test('skips units already reserved by another batch (isolation)', () async {
      // batch_1 reserves u1 and u2.
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');

      // batch_2 tries u2 and u3; u2 is taken, so only u3 is reserved.
      final result =
          await manager.reserveUnits('batch_2', ['u2', 'u3'], 'fr');

      expect(result.isOk, isTrue);
      // Skipping is NOT an error: u2 omitted, u3 returned.
      expect(result.value, equals(['u3']));

      final u2Rows = await rows(
        where: 'translation_unit_id = ?',
        args: ['u2'],
      );
      expect(u2Rows.length, equals(1));
      expect(u2Rows.first['batch_id'], equals('batch_1'));

      final u3Rows = await rows(
        where: 'translation_unit_id = ?',
        args: ['u3'],
      );
      expect(u3Rows.first['batch_id'], equals('batch_2'));
    });

    test('same unit in a different language is independent', () async {
      await manager.reserveUnits('batch_1', ['u1'], 'fr');

      // u1 reserved for 'fr' does not block reserving u1 for 'de'.
      final result = await manager.reserveUnits('batch_2', ['u1'], 'de');

      expect(result.isOk, isTrue);
      expect(result.value, equals(['u1']));
      expect((await rows(where: 'translation_unit_id = ?', args: ['u1'])).length,
          equals(2));
    });

    test('a completed reservation does not block a new reservation', () async {
      await manager.reserveUnits('batch_1', ['u1'], 'fr');
      await manager.releaseUnits('batch_1', 'fr');

      // The earlier reservation is now 'completed' (not 'active'), so u1 is
      // available again.
      final result = await manager.reserveUnits('batch_2', ['u1'], 'fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(['u1']));
    });

    test('clamps an over-large timeout to maxTimeout (2h)', () async {
      final before = DateTime.now();
      final result = await manager.reserveUnits(
        'batch_1',
        ['u1'],
        'fr',
        timeout: const Duration(days: 10),
      );
      expect(result.isOk, isTrue);

      final row = (await rows()).single;
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(row['expires_at'] as int);
      // Clamped to <= 2 hours from reservation time (allow small slack).
      expect(
        expiresAt.isBefore(before.add(const Duration(hours: 2, minutes: 1))),
        isTrue,
      );
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.reserveUnits('batch_1', ['u1'], 'fr');

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, equals('RESERVE_UNITS_FAILED'));
    });
  });

  group('releaseUnits', () {
    test('releases all active units for a batch+language', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');

      final result = await manager.releaseUnits('batch_1', 'fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final active = await rows(where: 'status = ?', args: ['active']);
      expect(active, isEmpty);

      final completed = await rows(where: 'status = ?', args: ['completed']);
      expect(completed.length, equals(2));
      for (final row in completed) {
        expect(row['released_at'], isA<int>());
      }
    });

    test('releases only the specified units', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2', 'u3'], 'fr');

      final result =
          await manager.releaseUnits('batch_1', 'fr', unitIds: ['u1', 'u3']);

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final stillActive = await rows(where: 'status = ?', args: ['active']);
      expect(stillActive.length, equals(1));
      expect(stillActive.single['translation_unit_id'], equals('u2'));
    });

    test('does not touch reservations of other batches', () async {
      await manager.reserveUnits('batch_1', ['u1'], 'fr');
      await manager.reserveUnits('batch_2', ['u2'], 'fr');

      final result = await manager.releaseUnits('batch_1', 'fr');

      expect(result.value, equals(1));
      final b2 = await rows(where: 'batch_id = ?', args: ['batch_2']);
      expect(b2.single['status'], equals('active'));
    });

    test('returns 0 when nothing matches', () async {
      final result = await manager.releaseUnits('ghost_batch', 'fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.releaseUnits('batch_1', 'fr');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RELEASE_UNITS_FAILED'));
    });
  });

  group('releaseUnitsOnError', () {
    test('marks all active units as failed with error_reason', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');

      final result = await manager.releaseUnitsOnError(
        'batch_1',
        'fr',
        errorReason: 'quota exceeded',
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final failed = await rows(where: 'status = ?', args: ['failed']);
      expect(failed.length, equals(2));
      for (final row in failed) {
        expect(row['error_reason'], equals('quota exceeded'));
        expect(row['released_at'], isA<int>());
      }
    });

    test('marks only the specified units as failed', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');

      final result = await manager.releaseUnitsOnError(
        'batch_1',
        'fr',
        unitIds: ['u1'],
      );

      expect(result.value, equals(1));
      final failed = await rows(where: 'status = ?', args: ['failed']);
      expect(failed.single['translation_unit_id'], equals('u1'));
      // error_reason omitted -> stays null.
      expect(failed.single['error_reason'], isNull);
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.releaseUnitsOnError('batch_1', 'fr');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RELEASE_ERROR_FAILED'));
    });
  });

  group('getAvailableUnits', () {
    test('returns Ok empty when input is empty', () async {
      final result = await manager.getAvailableUnits(const [], 'fr');
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('returns only the units not actively reserved', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u3'], 'fr');

      final result =
          await manager.getAvailableUnits(['u1', 'u2', 'u3', 'u4'], 'fr');

      expect(result.isOk, isTrue);
      expect(result.value, equals(['u2', 'u4']));
    });

    test('language scope is respected', () async {
      await manager.reserveUnits('batch_1', ['u1'], 'fr');

      // u1 is reserved for fr but free for de.
      final result = await manager.getAvailableUnits(['u1'], 'de');
      expect(result.value, equals(['u1']));
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.getAvailableUnits(['u1'], 'fr');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('GET_AVAILABLE_FAILED'));
    });
  });

  group('getBatchReservations', () {
    test('returns active reservations parsed as BatchReservation', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');

      final result = await manager.getBatchReservations('batch_1');

      expect(result.isOk, isTrue);
      expect(result.value.length, equals(2));
      final r = result.value.first;
      expect(r, isA<BatchReservation>());
      expect(r.batchId, equals('batch_1'));
      expect(r.languageCode, equals('fr'));
      expect(r.status, equals('active'));
      expect(result.value.map((x) => x.translationUnitId).toSet(),
          equals({'u1', 'u2'}));
    });

    test('filters by language code when provided', () async {
      await manager.reserveUnits('batch_1', ['u1'], 'fr');
      await manager.reserveUnits('batch_1', ['u2'], 'de');

      final result =
          await manager.getBatchReservations('batch_1', languageCode: 'de');

      expect(result.isOk, isTrue);
      expect(result.value.length, equals(1));
      expect(result.value.single.translationUnitId, equals('u2'));
      expect(result.value.single.languageCode, equals('de'));
    });

    test('excludes non-active (completed) reservations', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');
      await manager.releaseUnits('batch_1', 'fr', unitIds: ['u1']);

      final result = await manager.getBatchReservations('batch_1');

      expect(result.value.length, equals(1));
      expect(result.value.single.translationUnitId, equals('u2'));
    });

    test('returns empty list for unknown batch', () async {
      final result = await manager.getBatchReservations('nope');
      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.getBatchReservations('batch_1');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('GET_RESERVATIONS_FAILED'));
    });
  });

  group('extendReservations', () {
    test('pushes expires_at forward for active reservations', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2'], 'fr');

      final before = await rows();
      final originalExpiry = {
        for (final r in before)
          r['translation_unit_id'] as String: r['expires_at'] as int,
      };

      final result = await manager.extendReservations(
        'batch_1',
        'fr',
        const Duration(minutes: 30),
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final after = await rows();
      for (final r in after) {
        final unit = r['translation_unit_id'] as String;
        // +30 minutes = +1_800_000 ms.
        expect(
          r['expires_at'] as int,
          equals(originalExpiry[unit]! + 30 * 60 * 1000),
        );
      }
    });

    test('returns 0 and changes nothing when no active reservations', () async {
      final result = await manager.extendReservations(
        'batch_1',
        'fr',
        const Duration(minutes: 30),
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.extendReservations(
        'batch_1',
        'fr',
        const Duration(minutes: 30),
      );

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('EXTEND_RESERVATIONS_FAILED'));
    });
  });

  group('cleanupExpiredReservations', () {
    test('marks active+expired rows as expired and sets released_at', () async {
      final past = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      final reserved = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;

      // A fresh reservation that should survive. Done FIRST: reserveUnits runs
      // _cleanupExpiredReservations internally, which would otherwise expire the
      // stale row below before our explicit cleanupExpiredReservations() call.
      await manager.reserveUnits('batch_1', ['u2'], 'fr');
      // Insert a stale active reservation directly (expires_at in the past).
      await db.insert('batch_entry_reservations', {
        'id': 'stale-1',
        'batch_id': 'batch_1',
        'translation_unit_id': 'u1',
        'language_code': 'fr',
        'reserved_at': reserved,
        'expires_at': past,
        'status': 'active',
      });

      final result = await manager.cleanupExpiredReservations();

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final stale =
          (await rows(where: 'id = ?', args: ['stale-1'])).single;
      expect(stale['status'], equals('expired'));
      expect(stale['released_at'], isA<int>());

      final fresh =
          (await rows(where: 'translation_unit_id = ?', args: ['u2'])).single;
      expect(fresh['status'], equals('active'));
    });

    test('expired reservation frees the unit for re-reservation', () async {
      final past = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await db.insert('batch_entry_reservations', {
        'id': 'stale-1',
        'batch_id': 'batch_1',
        'translation_unit_id': 'u1',
        'language_code': 'fr',
        'reserved_at': past,
        'expires_at': past,
        'status': 'active',
      });

      // reserveUnits runs cleanup first, so the stale 'u1' is freed and a new
      // reservation succeeds.
      final result = await manager.reserveUnits('batch_2', ['u1'], 'fr');
      expect(result.value, equals(['u1']));

      final active = await rows(where: 'status = ?', args: ['active']);
      expect(active.single['batch_id'], equals('batch_2'));
    });

    test('returns 0 when nothing is expired', () async {
      await manager.reserveUnits('batch_1', ['u1'], 'fr');

      final result = await manager.cleanupExpiredReservations();

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.cleanupExpiredReservations();

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('CLEANUP_EXPIRED_FAILED'));
    });
  });

  group('getReservationStats', () {
    test('returns counts grouped by status', () async {
      await manager.reserveUnits('batch_1', ['u1', 'u2', 'u3'], 'fr');
      await manager.releaseUnits('batch_1', 'fr', unitIds: ['u1']);
      await manager.releaseUnitsOnError('batch_1', 'fr', unitIds: ['u2']);

      final result = await manager.getReservationStats();

      expect(result.isOk, isTrue);
      expect(result.value['active'], equals(1));
      expect(result.value['completed'], equals(1));
      expect(result.value['failed'], equals(1));
    });

    test('returns empty map when there are no reservations', () async {
      final result = await manager.getReservationStats();

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('returns Err(ConcurrencyException) on DatabaseException', () async {
      await db.execute('DROP TABLE batch_entry_reservations');

      final result = await manager.getReservationStats();

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('GET_STATS_FAILED'));
    });
  });
}
