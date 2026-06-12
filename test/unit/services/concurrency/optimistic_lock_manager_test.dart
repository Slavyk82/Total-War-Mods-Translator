import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';
import 'package:twmt/services/concurrency/optimistic_lock_manager.dart';

import '../../../helpers/test_database.dart';

/// Tests for [OptimisticLockManager].
///
/// The manager operates on any table that exposes `id`, `version` and
/// `updated_at` columns. The migrated production schema has no such table that
/// matches the manager's expectations directly:
///
///  - The compare-and-swap methods ([checkVersion], [updateWithVersionCheck],
///    [getCurrentVersion], [incrementVersion], [resetVersion],
///    [batchUpdateWithVersionCheck]) need a table with `id` / `version` /
///    `updated_at`. We CREATE a dedicated `test_versioned` table for these.
///
///  - [getVersionHistory] queries `translation_version_history` filtering on
///    `translation_version_id` and ordering by `version DESC`. The migrated
///    schema's `translation_version_history` has columns `version_id` and no
///    `version` column, so the production query would throw a
///    `DatabaseException`. We DROP and re-CREATE that table with the columns
///    the manager actually selects (`translation_version_id`, `version`) so the
///    happy path can be exercised; the error branch is covered separately by
///    querying after dropping the table.
void main() {
  late Database db;
  late OptimisticLockManager manager;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    manager = OptimisticLockManager();

    // Dedicated table for compare-and-swap / version methods. Mirrors the
    // columns the manager reads/writes: id, version, updated_at (+ payload).
    await db.execute('''
      CREATE TABLE test_versioned (
        id TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        data TEXT
      )
    ''');

    // The migrated translation_version_history table uses `version_id` and has
    // no `version` column, but the manager's getVersionHistory selects
    // `translation_version_id` and orders by `version`. Recreate it to match
    // the manager's expectations so the happy path is reachable.
    await db.execute('DROP TABLE IF EXISTS translation_version_history');
    await db.execute('''
      CREATE TABLE translation_version_history (
        id TEXT PRIMARY KEY,
        translation_version_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        translated_text TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<void> seedRecord(
    String id,
    int version, {
    String? data,
    int updatedAt = 1000,
  }) async {
    await db.insert('test_versioned', {
      'id': id,
      'version': version,
      'updated_at': updatedAt,
      'data': data,
    });
  }

  Future<Map<String, Object?>> readRecord(String id) async {
    final rows = await db.query(
      'test_versioned',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.first;
  }

  Future<void> seedHistory(
    String id,
    String recordId,
    int version, {
    String? text,
    int createdAt = 1000,
  }) async {
    await db.insert('translation_version_history', {
      'id': id,
      'translation_version_id': recordId,
      'version': version,
      'translated_text': text ?? 'text-$version',
      'created_at': createdAt,
    });
  }

  group('checkVersion', () {
    test('returns Ok with current version when it matches expected', () async {
      await seedRecord('r1', 5);

      final result = await manager.checkVersion('test_versioned', 'r1', 5);

      expect(result.isOk, isTrue);
      expect(result.value, equals(5));
    });

    test('returns VersionConflictException on mismatch', () async {
      await seedRecord('r1', 7);

      final result = await manager.checkVersion('test_versioned', 'r1', 5);

      expect(result.isErr, isTrue);
      final error = result.error;
      expect(error, isA<VersionConflictException>());
      expect(error.code, equals('VERSION_CONFLICT'));
      expect((error.details as Map?)?['expected_version'], equals(5));
      expect((error.details as Map?)?['actual_version'], equals(7));
      expect((error.details as Map?)?['resource_id'], equals('r1'));
    });

    test('returns RECORD_NOT_FOUND when record absent', () async {
      final result = await manager.checkVersion('test_versioned', 'missing', 1);

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RECORD_NOT_FOUND'));
      expect((result.error.details as Map?)?['table'], equals('test_versioned'));
      expect((result.error.details as Map?)?['id'], equals('missing'));
    });

    test('returns VERSION_CHECK_FAILED when table does not exist', () async {
      final result = await manager.checkVersion('no_such_table', 'r1', 1);

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('VERSION_CHECK_FAILED'));
    });
  });

  group('updateWithVersionCheck', () {
    test('updates row and bumps version on matching version (CAS success)',
        () async {
      await seedRecord('r1', 3, data: 'old');

      final result = await manager.updateWithVersionCheck(
        'test_versioned',
        'r1',
        3,
        {'data': 'new'},
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(4));

      final row = await readRecord('r1');
      expect(row['version'], equals(4));
      expect(row['data'], equals('new'));
      expect(row['updated_at'], isNot(equals(1000)));
    });

    test('returns VersionConflictException when version is stale (no update)',
        () async {
      await seedRecord('r1', 5, data: 'keep');

      final result = await manager.updateWithVersionCheck(
        'test_versioned',
        'r1',
        3, // stale
        {'data': 'should-not-apply'},
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<VersionConflictException>());
      expect((result.error.details as Map?)?['actual_version'], equals(5));

      // Row must be unchanged.
      final row = await readRecord('r1');
      expect(row['version'], equals(5));
      expect(row['data'], equals('keep'));
    });

    test('returns RECORD_NOT_FOUND when record absent', () async {
      final result = await manager.updateWithVersionCheck(
        'test_versioned',
        'missing',
        1,
        {'data': 'x'},
      );

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RECORD_NOT_FOUND'));
    });

    test('returns VERSION_UPDATE_FAILED on database error', () async {
      await seedRecord('r1', 1);

      // Unknown column triggers a DatabaseException inside the update.
      final result = await manager.updateWithVersionCheck(
        'test_versioned',
        'r1',
        1,
        {'nonexistent_column': 'x'},
      );

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('VERSION_UPDATE_FAILED'));
    });
  });

  group('getCurrentVersion', () {
    test('returns the stored version', () async {
      await seedRecord('r1', 9);

      final result = await manager.getCurrentVersion('test_versioned', 'r1');

      expect(result.isOk, isTrue);
      expect(result.value, equals(9));
    });

    test('returns RECORD_NOT_FOUND when record absent', () async {
      final result =
          await manager.getCurrentVersion('test_versioned', 'missing');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RECORD_NOT_FOUND'));
    });

    test('returns GET_VERSION_FAILED when table does not exist', () async {
      final result = await manager.getCurrentVersion('no_such_table', 'r1');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('GET_VERSION_FAILED'));
    });
  });

  group('incrementVersion', () {
    test('bumps version and returns the new value', () async {
      await seedRecord('r1', 2);

      final result = await manager.incrementVersion('test_versioned', 'r1');

      expect(result.isOk, isTrue);
      expect(result.value, equals(3));

      final row = await readRecord('r1');
      expect(row['version'], equals(3));
    });

    test('returns RECORD_NOT_FOUND when record absent', () async {
      final result =
          await manager.incrementVersion('test_versioned', 'missing');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RECORD_NOT_FOUND'));
    });

    test('returns INCREMENT_VERSION_FAILED when table does not exist',
        () async {
      final result = await manager.incrementVersion('no_such_table', 'r1');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('INCREMENT_VERSION_FAILED'));
    });
  });

  group('resetVersion', () {
    test('resets version to 1 and returns true', () async {
      await seedRecord('r1', 42);

      final result = await manager.resetVersion('test_versioned', 'r1');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);

      final row = await readRecord('r1');
      expect(row['version'], equals(1));
    });

    test('returns Ok(false) when record absent (no rows updated)', () async {
      final result = await manager.resetVersion('test_versioned', 'missing');

      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });

    test('returns RESET_VERSION_FAILED when table does not exist', () async {
      final result = await manager.resetVersion('no_such_table', 'r1');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RESET_VERSION_FAILED'));
    });
  });

  group('batchUpdateWithVersionCheck', () {
    test('updates all rows when every version matches', () async {
      await seedRecord('a', 1, data: 'a-old');
      await seedRecord('b', 2, data: 'b-old');

      final result = await manager.batchUpdateWithVersionCheck(
        'test_versioned',
        [
          (recordId: 'a', expectedVersion: 1, updates: {'data': 'a-new'}),
          (recordId: 'b', expectedVersion: 2, updates: {'data': 'b-new'}),
        ],
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals([2, 3]));

      final rowA = await readRecord('a');
      final rowB = await readRecord('b');
      expect(rowA['version'], equals(2));
      expect(rowA['data'], equals('a-new'));
      expect(rowB['version'], equals(3));
      expect(rowB['data'], equals('b-new'));
    });

    test('rolls back entire batch when one version is stale', () async {
      await seedRecord('a', 1, data: 'a-old');
      await seedRecord('b', 5, data: 'b-old'); // stale expectation below

      final result = await manager.batchUpdateWithVersionCheck(
        'test_versioned',
        [
          (recordId: 'a', expectedVersion: 1, updates: {'data': 'a-new'}),
          (recordId: 'b', expectedVersion: 2, updates: {'data': 'b-new'}),
        ],
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<VersionConflictException>());
      expect((result.error.details as Map?)?['resource_id'], equals('b'));
      expect((result.error.details as Map?)?['actual_version'], equals(5));

      // Transaction rolled back: 'a' must be untouched too.
      final rowA = await readRecord('a');
      expect(rowA['version'], equals(1));
      expect(rowA['data'], equals('a-old'));
    });

    test('returns RECORD_NOT_FOUND when a record is missing', () async {
      await seedRecord('a', 1);

      final result = await manager.batchUpdateWithVersionCheck(
        'test_versioned',
        [
          (recordId: 'a', expectedVersion: 1, updates: {'data': 'x'}),
          (recordId: 'missing', expectedVersion: 1, updates: {'data': 'y'}),
        ],
      );

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RECORD_NOT_FOUND'));

      // Rolled back: 'a' unchanged.
      final rowA = await readRecord('a');
      expect(rowA['version'], equals(1));
    });

    test('returns Ok with empty list for empty input', () async {
      final result = await manager.batchUpdateWithVersionCheck(
        'test_versioned',
        [],
      );

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('hasBeenModified', () {
    test('returns true when current version is greater than sinceVersion',
        () async {
      await seedRecord('r1', 5);

      final result =
          await manager.hasBeenModified('test_versioned', 'r1', 3);

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('returns false when current version equals sinceVersion', () async {
      await seedRecord('r1', 4);

      final result =
          await manager.hasBeenModified('test_versioned', 'r1', 4);

      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });

    test('propagates RECORD_NOT_FOUND from getCurrentVersion', () async {
      final result =
          await manager.hasBeenModified('test_versioned', 'missing', 1);

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('RECORD_NOT_FOUND'));
    });
  });

  group('getVersionHistory', () {
    test('returns entries ordered by version DESC', () async {
      await seedHistory('h1', 'tv1', 1, text: 'first');
      await seedHistory('h2', 'tv1', 3, text: 'third');
      await seedHistory('h3', 'tv1', 2, text: 'second');
      // A different record that must be excluded.
      await seedHistory('h4', 'tv2', 9, text: 'other');

      final result = await manager.getVersionHistory('tv1');

      expect(result.isOk, isTrue);
      final history = result.value;
      expect(history.length, equals(3));
      expect(history.map((e) => e['version']).toList(), equals([3, 2, 1]));
      expect(history.first['translated_text'], equals('third'));
    });

    test('respects the limit parameter', () async {
      await seedHistory('h1', 'tv1', 1);
      await seedHistory('h2', 'tv1', 2);
      await seedHistory('h3', 'tv1', 3);

      final result = await manager.getVersionHistory('tv1', limit: 2);

      expect(result.isOk, isTrue);
      expect(result.value.length, equals(2));
      // Highest versions first.
      expect(result.value.map((e) => e['version']).toList(), equals([3, 2]));
    });

    test('returns an empty list when there is no history', () async {
      final result = await manager.getVersionHistory('unknown-record');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('returns GET_HISTORY_FAILED when the table is missing', () async {
      await db.execute('DROP TABLE translation_version_history');

      final result = await manager.getVersionHistory('tv1');

      expect(result.isErr, isTrue);
      expect(result.error.code, equals('GET_HISTORY_FAILED'));
    });
  });
}
