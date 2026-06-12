import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/activity/repositories/activity_event_repository_impl.dart';
import 'package:twmt/models/events/activity_event.dart';

import '../../../helpers/test_database.dart';

/// Covers the append-only repository's unsupported CRUD overrides
/// (`getById`, `getAll`, `update`, `delete`). These exist only to satisfy
/// the [BaseRepository] contract and throw [UnsupportedError] synchronously
/// when invoked. The existing `activity_event_repository_test.dart` already
/// covers `insert` and `getRecent`, so those are not re-tested here.
void main() {
  late Database db;
  late ActivityEventRepositoryImpl repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = ActivityEventRepositoryImpl();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  ActivityEvent makeEvent() {
    return ActivityEvent(
      id: 0,
      type: ActivityEventType.packCompiled,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1800000000000),
      projectId: 'p1',
      gameCode: 'wh3',
      payload: const {'k': 1},
    );
  }

  group('ActivityEventRepositoryImpl unsupported CRUD', () {
    test('getById throws UnsupportedError (append-only)', () {
      expect(
        () => repository.getById('1'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('getById'),
          ),
        ),
      );
    });

    test('getAll throws UnsupportedError pointing to getRecent', () {
      expect(
        () => repository.getAll(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('getRecent'),
          ),
        ),
      );
    });

    test('update throws UnsupportedError (events are immutable)', () {
      expect(
        () => repository.update(makeEvent()),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('immutable'),
          ),
        ),
      );
    });

    test('delete throws UnsupportedError (append-only)', () {
      expect(
        () => repository.delete('1'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('delete'),
          ),
        ),
      );
    });
  });
}
