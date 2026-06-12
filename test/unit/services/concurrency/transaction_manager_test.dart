import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';

import '../../../helpers/test_database.dart';

/// Unit tests for [TransactionManager].
///
/// The manager has no tables of its own: it runs caller-supplied actions inside
/// transactions against the shared [DatabaseService.database]. The migrated
/// in-memory DB from [TestDatabase.openMigrated] wires that singleton, so
/// `TransactionManager()` resolves to the same handle. We use the seeded-then-
/// cleared `settings` table (exists, empty after openMigrated) for real
/// insert/query actions, plus `rawQuery('SELECT 1')` for read-only checks.
void main() {
  late Database db;
  late TransactionManager manager;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    manager = TransactionManager();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  /// Inserts a minimal valid `settings` row inside the supplied transaction.
  Future<void> insertSetting(Transaction txn, String id, String key) async {
    await txn.insert('settings', {
      'id': id,
      'key': key,
      'value': 'v',
      'value_type': 'string',
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  group('executeTransaction', () {
    test('returns Ok with the value the action produced', () async {
      final result = await manager.executeTransaction<int>((txn) async {
        return 42;
      });

      expect(result.isOk, isTrue);
      expect(result.value, equals(42));
    });

    test('commits a real insert performed inside the transaction', () async {
      final result = await manager.executeTransaction<int>((txn) async {
        await insertSetting(txn, 'tx-1', 'tx.one');
        final rows = await txn.query('settings', where: 'id = ?', whereArgs: ['tx-1']);
        return rows.length;
      });

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      // Visible outside the transaction => committed.
      final committed = await db.query('settings', where: 'id = ?', whereArgs: ['tx-1']);
      expect(committed.length, equals(1));
      expect(committed.first['key'], equals('tx.one'));
    });

    test('returns Err and rolls back when the action throws', () async {
      final result = await manager.executeTransaction<int>((txn) async {
        await insertSetting(txn, 'tx-rollback', 'tx.rollback');
        throw StateError('boom');
      });

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error, isA<TransactionException>());

      // Row must NOT be present => rolled back.
      final rows = await db.query('settings', where: 'id = ?', whereArgs: ['tx-rollback']);
      expect(rows, isEmpty);
    });
  });

  group('executeBatch', () {
    test('returns Ok with the number of operations performed', () async {
      final result = await manager.executeBatch([
        (txn) async => insertSetting(txn, 'b-1', 'batch.one'),
        (txn) async => insertSetting(txn, 'b-2', 'batch.two'),
        (txn) async => insertSetting(txn, 'b-3', 'batch.three'),
      ]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(3));

      final rows = await db.query('settings');
      expect(rows.length, equals(3));
    });

    test('returns Err and rolls back all operations when one throws', () async {
      final result = await manager.executeBatch([
        (txn) async => insertSetting(txn, 'b-ok', 'batch.ok'),
        (txn) async => throw StateError('batch failure'),
        (txn) async => insertSetting(txn, 'b-after', 'batch.after'),
      ]);

      expect(result.isErr, isTrue);
      expect(result.error, isA<TransactionException>());

      // Atomicity: the earlier successful insert must be rolled back too.
      final rows = await db.query('settings');
      expect(rows, isEmpty);
    });
  });

  group('executeReadOnly', () {
    test('returns Ok with the query result', () async {
      final result = await manager.executeReadOnly<List<Map<String, Object?>>>(
        (database) async => database.rawQuery('SELECT 1 AS one'),
      );

      expect(result.isOk, isTrue);
      expect(result.value.first['one'], equals(1));
    });

    test('reads rows that were committed by a prior transaction', () async {
      await manager.executeTransaction<void>((txn) async {
        await insertSetting(txn, 'ro-1', 'readonly.one');
      });

      final result = await manager.executeReadOnly<int>((database) async {
        final rows = await database.query('settings');
        return rows.length;
      });

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));
    });

    test('returns Err when the read callback throws', () async {
      final result = await manager.executeReadOnly<int>((database) async {
        throw StateError('read failure');
      });

      expect(result.isErr, isTrue);
      expect(result.error, isA<TransactionException>());
    });
  });

  group('executeExclusive', () {
    test('returns Ok and commits an insert (IMMEDIATE lock, default)', () async {
      final result = await manager.executeExclusive<int>((txn) async {
        await insertSetting(txn, 'ex-1', 'exclusive.one');
        return 7;
      });

      expect(result.isOk, isTrue);
      expect(result.value, equals(7));

      final rows = await db.query('settings', where: 'id = ?', whereArgs: ['ex-1']);
      expect(rows.length, equals(1));
    });

    test('returns Ok with EXCLUSIVE lock as well', () async {
      final result = await manager.executeExclusive<String>(
        (txn) async => 'locked',
        exclusive: true,
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals('locked'));
    });

    test('returns Err and rolls back when the action throws', () async {
      final result = await manager.executeExclusive<int>((txn) async {
        await insertSetting(txn, 'ex-rollback', 'exclusive.rollback');
        throw StateError('exclusive boom');
      });

      expect(result.isErr, isTrue);
      expect(result.error, isA<TransactionException>());

      final rows = await db.query('settings', where: 'id = ?', whereArgs: ['ex-rollback']);
      expect(rows, isEmpty);
    });
  });

  group('executeWithTimeout', () {
    test('returns Ok when the action completes within the timeout', () async {
      final result = await manager.executeWithTimeout<int>(
        (txn) async {
          await insertSetting(txn, 'to-1', 'timeout.one');
          return 1;
        },
        const Duration(seconds: 5),
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final rows = await db.query('settings', where: 'id = ?', whereArgs: ['to-1']);
      expect(rows.length, equals(1));
    });

    test('returns Err (TransactionException) when the action exceeds the timeout', () async {
      final result = await manager.executeWithTimeout<int>(
        (txn) async {
          // Deliberately slow: exceeds the tiny timeout below. The Dart-side
          // .timeout() fires a TimeoutException which the manager maps to a
          // TransactionException; the underlying SQLite transaction is NOT
          // cancelled (documented limitation), but the Result is an Err.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return 1;
        },
        const Duration(milliseconds: 10),
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<TransactionException>());
      expect(result.error.message, contains('timed out'));
    });
  });
}
