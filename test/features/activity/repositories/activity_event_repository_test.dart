import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/repositories/activity_event_repository_impl.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_activity_events.dart';
import '../../../helpers/test_bootstrap.dart';

void main() {
  late Database db;
  late ActivityEventRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);
    await ActivityEventsMigration().execute();
    repository = ActivityEventRepositoryImpl();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  ActivityEvent make(
    int tsMs,
    ActivityEventType type, {
    String? gameCode,
    String? projectId,
    Map<String, dynamic>? payload,
  }) {
    return ActivityEvent(
      id: 0,
      type: type,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
      projectId: projectId,
      gameCode: gameCode,
      payload: payload ?? const {},
    );
  }

  group('ActivityEventRepositoryImpl', () {
    test('insert persists a row and returns it with new id', () async {
      final e = make(
        1800000000000,
        ActivityEventType.packCompiled,
        gameCode: 'wh3',
        projectId: 'p1',
        payload: {'k': 1},
      );
      final r = await repository.insert(e);
      expect(r.isOk, isTrue);
      expect(r.value.id, greaterThan(0));

      final rows = await db.query('activity_events');
      expect(rows, hasLength(1));
    });

    test('getRecent returns DESC timestamp, most recent first', () async {
      await repository.insert(make(100, ActivityEventType.glossaryEnriched));
      await repository.insert(make(300, ActivityEventType.packCompiled));
      await repository.insert(make(200, ActivityEventType.projectPublished));

      final r = await repository.getRecent();
      expect(r.isOk, isTrue);
      final list =
          r.value.map((e) => e.timestamp.millisecondsSinceEpoch).toList();
      expect(list, [300, 200, 100]);
    });

    test('getRecent with same timestamp orders by id DESC (stable)', () async {
      await repository.insert(make(500, ActivityEventType.glossaryEnriched));
      await repository.insert(make(500, ActivityEventType.modUpdatesDetected));

      final r = await repository.getRecent();
      expect(r.value.first.type, ActivityEventType.modUpdatesDetected);
      expect(r.value.last.type, ActivityEventType.glossaryEnriched);
    });

    test('getRecent respects limit', () async {
      for (var i = 0; i < 25; i++) {
        await repository.insert(make(i, ActivityEventType.glossaryEnriched));
      }
      final r = await repository.getRecent(limit: 20);
      expect(r.value, hasLength(20));
    });

    test('getRecent filters by gameCode when provided', () async {
      await repository.insert(
        make(100, ActivityEventType.packCompiled, gameCode: 'wh3'),
      );
      await repository.insert(
        make(200, ActivityEventType.packCompiled, gameCode: 'rome2'),
      );
      await repository.insert(
        make(300, ActivityEventType.modUpdatesDetected),
      );

      final r = await repository.getRecent(gameCode: 'wh3');
      expect(r.value, hasLength(1));
      expect(r.value.first.gameCode, 'wh3');
    });
  });
}
