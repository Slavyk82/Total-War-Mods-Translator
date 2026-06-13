import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/events/domain_event.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/shared/models/event_record.dart';

import '../../helpers/noop_logger.dart';

/// A concrete [DomainEvent] used to exercise the bus and persistence paths.
class _TestEvent extends DomainEvent {
  _TestEvent({
    required String id,
    required this.payload,
    DateTime? occurredAt,
  }) : super(
          eventId: id,
          timestamp: occurredAt ?? DateTime.now(),
        );

  final Map<String, dynamic> payload;

  @override
  Map<String, dynamic> toJson() => payload;
}

/// A second event type to verify type-filtered subscriptions.
class _OtherEvent extends DomainEvent {
  _OtherEvent() : super(eventId: 'other', timestamp: DateTime.now());

  @override
  Map<String, dynamic> toJson() => {'kind': 'other'};
}

/// A "Batch" named event so the aggregate-type inference branch is hit.
class _BatchTestEvent extends DomainEvent {
  _BatchTestEvent(this.batchId)
      : super(eventId: 'b-$batchId', timestamp: DateTime.now());

  final String batchId;

  @override
  Map<String, dynamic> toJson() => {'batchId': batchId};
}

const _createEventStore = '''
  CREATE TABLE event_store (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    triggered_by TEXT,
    aggregate_id TEXT,
    aggregate_type TEXT,
    correlation_id TEXT,
    causation_id TEXT,
    metadata TEXT
  )
''';

void main() {
  final EventBus bus = EventBus.instance;
  final List<Database> openedDbs = [];
  int dbCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    EventBus.loggerForTesting = NoopLogger();
  });

  setUp(() {
    bus.persistEvents = false;
  });

  tearDown(() async {
    DatabaseService.resetTestDatabase();
    bus.persistEvents = false;
    for (final db in openedDbs) {
      try {
        await db.close();
      } catch (_) {
        // Already closed by the test.
      }
    }
    openedDbs.clear();
  });

  /// Opens a fresh, isolated in-memory database. Each call uses a unique path
  /// so leftover tables from a previous test cannot leak between tests.
  Future<Database> openRawDb() async {
    dbCounter++;
    final db = await databaseFactory.openDatabase(
      'file:eventbus_test_$dbCounter?mode=memory&cache=private',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    openedDbs.add(db);
    return db;
  }

  Future<Database> openDb() async {
    final db = await openRawDb();
    await db.execute(_createEventStore);
    DatabaseService.setTestDatabase(db);
    return db;
  }

  group('subscription and publishing', () {
    test('publish with no listeners does not throw', () async {
      await bus.publish(_TestEvent(id: '1', payload: {'a': 1}));
      expect(true, isTrue);
    });

    test('on<T>() delivers matching events to a single listener', () async {
      final received = <_TestEvent>[];
      final sub = bus.on<_TestEvent>().listen(received.add);

      await bus.publish(_TestEvent(id: '1', payload: {'v': 1}));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.first.eventId, '1');
      await sub.cancel();
    });

    test('on<T>() delivers to multiple listeners', () async {
      final a = <_TestEvent>[];
      final b = <_TestEvent>[];
      final subA = bus.on<_TestEvent>().listen(a.add);
      final subB = bus.on<_TestEvent>().listen(b.add);

      await bus.publish(_TestEvent(id: 'x', payload: {}));
      await pumpEventQueue();

      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await subA.cancel();
      await subB.cancel();
    });

    test('on<T>() filters by event type', () async {
      final tests = <_TestEvent>[];
      final others = <_OtherEvent>[];
      final subT = bus.on<_TestEvent>().listen(tests.add);
      final subO = bus.on<_OtherEvent>().listen(others.add);

      await bus.publish(_TestEvent(id: 't1', payload: {}));
      await bus.publish(_OtherEvent());
      await bus.publish(_TestEvent(id: 't2', payload: {}));
      await pumpEventQueue();

      expect(tests.map((e) => e.eventId), ['t1', 't2']);
      expect(others, hasLength(1));
      await subT.cancel();
      await subO.cancel();
    });

    test('events stream emits every published event', () async {
      final all = <DomainEvent>[];
      final sub = bus.events.listen(all.add);

      await bus.publish(_TestEvent(id: 'a', payload: {}));
      await bus.publish(_OtherEvent());
      await pumpEventQueue();

      expect(all, hasLength(2));
      await sub.cancel();
    });

    test('cancelling subscription stops delivery', () async {
      final received = <_TestEvent>[];
      final sub = bus.on<_TestEvent>().listen(received.add);

      await bus.publish(_TestEvent(id: 'before', payload: {}));
      await pumpEventQueue();
      await sub.cancel();

      await bus.publish(_TestEvent(id: 'after', payload: {}));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.first.eventId, 'before');
    });

    test('publishSync delivers without persistence', () async {
      final received = <_TestEvent>[];
      final sub = bus.on<_TestEvent>().listen(received.add);

      bus.publishSync(_TestEvent(id: 'sync', payload: {}));
      await pumpEventQueue();

      expect(received, hasLength(1));
      await sub.cancel();
    });

    test('hasListeners and listenerCount reflect active listeners', () async {
      expect(bus.hasListeners, isFalse);
      expect(bus.listenerCount, 0);

      final sub = bus.on<_TestEvent>().listen((_) {});
      await pumpEventQueue();

      expect(bus.hasListeners, isTrue);
      expect(bus.listenerCount, 1);

      await sub.cancel();
      await pumpEventQueue();

      expect(bus.hasListeners, isFalse);
      expect(bus.listenerCount, 0);
    });
  });

  group('persistence', () {
    test('publish does not persist when persistEvents is false', () async {
      final db = await openDb();
      bus.persistEvents = false;

      await bus.publish(_TestEvent(id: 'np', payload: {'x': 1}));
      await pumpEventQueue();

      final rows = await db.query('event_store');
      expect(rows, isEmpty);
    });

    test('publish persists event when enabled and db initialized', () async {
      final db = await openDb();
      bus.persistEvents = true;

      await bus.publish(
        _TestEvent(id: 'p1', payload: {'projectId': 'proj-9'}),
        triggeredBy: 'tester',
        correlationId: 'corr-1',
        causationId: 'cause-1',
        metadata: {'ip': '127.0.0.1'},
      );
      await pumpEventQueue();
      await pumpEventQueue();

      final rows = await db.query('event_store');
      expect(rows, hasLength(1));
      final row = rows.first;
      expect(row['event_type'], '_TestEvent');
      expect(row['triggered_by'], 'tester');
      expect(row['aggregate_id'], 'proj-9');
      expect(row['correlation_id'], 'corr-1');
      expect(row['causation_id'], 'cause-1');
      expect(jsonDecode(row['metadata'] as String), {'ip': '127.0.0.1'});
    });

    test('persist infers aggregate type and id for batch events', () async {
      final db = await openDb();
      bus.persistEvents = true;

      await bus.publish(_BatchTestEvent('batch-7'));
      await pumpEventQueue();
      await pumpEventQueue();

      final rows = await db.query('event_store');
      expect(rows, hasLength(1));
      expect(rows.first['aggregate_id'], 'batch-7');
      expect(rows.first['aggregate_type'], 'TranslationBatch');
    });

    test('persistence failure does not crash publish', () async {
      final db = await openRawDb();
      // Intentionally do NOT create the event_store table so the insert fails.
      DatabaseService.setTestDatabase(db);
      bus.persistEvents = true;

      await bus.publish(_TestEvent(id: 'fail', payload: {}));
      await pumpEventQueue();
      await pumpEventQueue();

      // No throw expected; bus swallows persistence errors.
      expect(true, isTrue);
    });

    test('publish skips persistence when db not initialized', () async {
      DatabaseService.resetTestDatabase();
      bus.persistEvents = true;

      // Should not throw even though no database is set.
      await bus.publish(_TestEvent(id: 'no-db', payload: {}));
      await pumpEventQueue();
      expect(true, isTrue);
    });
  });

  group('history and queries', () {
    Future<void> seed(Database db) async {
      await db.insert('event_store', {
        'id': 'e1',
        'event_type': 'BatchCompletedEvent',
        'payload': jsonEncode({'batchId': 'b1'}),
        'occurred_at': DateTime(2024, 1, 1).millisecondsSinceEpoch,
        'triggered_by': 'u1',
        'aggregate_id': 'b1',
        'aggregate_type': 'TranslationBatch',
        'correlation_id': 'c1',
        'causation_id': null,
        'metadata': jsonEncode({'k': 'v'}),
      });
      await db.insert('event_store', {
        'id': 'e2',
        'event_type': 'ProjectCreatedEvent',
        'payload': jsonEncode({'projectId': 'p2'}),
        'occurred_at': DateTime(2024, 6, 1).millisecondsSinceEpoch,
        'triggered_by': null,
        'aggregate_id': 'p2',
        'aggregate_type': 'Project',
        'correlation_id': null,
        'causation_id': null,
        'metadata': null,
      });
    }

    test('getEventHistory returns all events newest first', () async {
      final db = await openDb();
      await seed(db);

      final result = await bus.getEventHistory();
      expect(result, isA<Ok<List<EventRecord>, Exception>>());
      final events = (result as Ok<List<EventRecord>, Exception>).value;
      expect(events.map((e) => e.id), ['e2', 'e1']);
      // metadata parsing branch (null and non-null) is exercised.
      expect(events.last.metadata, {'k': 'v'});
      expect(events.first.metadata, isNull);
    });

    test('getEventHistory filters by eventType', () async {
      final db = await openDb();
      await seed(db);

      final result =
          await bus.getEventHistory(eventType: 'ProjectCreatedEvent');
      final events = (result as Ok<List<EventRecord>, Exception>).value;
      expect(events.map((e) => e.id), ['e2']);
    });

    test('getEventHistory filters by aggregateId', () async {
      final db = await openDb();
      await seed(db);

      final result = await bus.getEventHistory(aggregateId: 'b1');
      final events = (result as Ok<List<EventRecord>, Exception>).value;
      expect(events.map((e) => e.id), ['e1']);
    });

    test('getEventHistory filters by since timestamp', () async {
      final db = await openDb();
      await seed(db);

      final result =
          await bus.getEventHistory(since: DateTime(2024, 3, 1));
      final events = (result as Ok<List<EventRecord>, Exception>).value;
      expect(events.map((e) => e.id), ['e2']);
    });

    test('getEventHistory honours limit', () async {
      final db = await openDb();
      await seed(db);

      final result = await bus.getEventHistory(limit: 1);
      final events = (result as Ok<List<EventRecord>, Exception>).value;
      expect(events, hasLength(1));
    });

    test('getEventHistory returns Err when query fails', () async {
      final db = await openRawDb();
      DatabaseService.setTestDatabase(db);
      // No event_store table -> query throws.
      final result = await bus.getEventHistory();
      expect(result, isA<Err<List<EventRecord>, Exception>>());
    });

    test('searchEvents matches payload content', () async {
      final db = await openDb();
      await seed(db);

      final result = await bus.searchEvents(searchTerm: 'b1');
      final events = (result as Ok<List<EventRecord>, Exception>).value;
      expect(events.map((e) => e.id), contains('e1'));
    });

    test('searchEvents returns Err when query fails', () async {
      final db = await openRawDb();
      DatabaseService.setTestDatabase(db);
      final result = await bus.searchEvents(searchTerm: 'x');
      expect(result, isA<Err<List<EventRecord>, Exception>>());
    });
  });

  group('statistics and maintenance', () {
    test('getStatistics aggregates counts by type and aggregate', () async {
      final db = await openDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('event_store', {
        'id': 's1',
        'event_type': 'BatchCompletedEvent',
        'payload': '{}',
        'occurred_at': now,
        'aggregate_type': 'TranslationBatch',
      });
      await db.insert('event_store', {
        'id': 's2',
        'event_type': 'BatchCompletedEvent',
        'payload': '{}',
        'occurred_at': now,
        'aggregate_type': 'TranslationBatch',
      });
      await db.insert('event_store', {
        'id': 's3',
        'event_type': 'ProjectCreatedEvent',
        'payload': '{}',
        'occurred_at':
            DateTime(2000, 1, 1).millisecondsSinceEpoch,
        'aggregate_type': null,
      });

      final result = await bus.getStatistics();
      final stats = (result as Ok<EventStatistics, Exception>).value;
      expect(stats.totalEvents, 3);
      expect(stats.eventsByType['BatchCompletedEvent'], 2);
      expect(stats.eventsByAggregate['TranslationBatch'], 2);
      expect(stats.eventsLastHour, 2);
      expect(stats.eventsLastDay, 2);
      expect(stats.lastEventAt, isNotNull);
    });

    test('getStatistics handles empty store with null lastEventAt', () async {
      await openDb();
      final result = await bus.getStatistics();
      final stats = (result as Ok<EventStatistics, Exception>).value;
      expect(stats.totalEvents, 0);
      expect(stats.lastEventAt, isNull);
    });

    test('getStatistics returns Err when query fails', () async {
      final db = await openRawDb();
      DatabaseService.setTestDatabase(db);
      final result = await bus.getStatistics();
      expect(result, isA<Err<EventStatistics, Exception>>());
    });

    test('purgeOldEvents deletes events older than retention', () async {
      final db = await openDb();
      await db.insert('event_store', {
        'id': 'old',
        'event_type': 'E',
        'payload': '{}',
        'occurred_at':
            DateTime(2000, 1, 1).millisecondsSinceEpoch,
      });
      await db.insert('event_store', {
        'id': 'new',
        'event_type': 'E',
        'payload': '{}',
        'occurred_at': DateTime.now().millisecondsSinceEpoch,
      });

      final result = await bus.purgeOldEvents(retentionDays: 30);
      final deleted = (result as Ok<int, Exception>).value;
      expect(deleted, 1);

      final remaining = await db.query('event_store');
      expect(remaining, hasLength(1));
      expect(remaining.first['id'], 'new');
    });

    test('purgeOldEvents returns Err when query fails', () async {
      final db = await openRawDb();
      DatabaseService.setTestDatabase(db);
      final result = await bus.purgeOldEvents();
      expect(result, isA<Err<int, Exception>>());
    });

    test('replayEvents returns count of events from history', () async {
      final db = await openDb();
      await db.insert('event_store', {
        'id': 'r1',
        'event_type': 'E',
        'payload': '{}',
        'occurred_at': DateTime(2024, 1, 1).millisecondsSinceEpoch,
      });
      await db.insert('event_store', {
        'id': 'r2',
        'event_type': 'E',
        'payload': '{}',
        'occurred_at': DateTime(2024, 2, 1).millisecondsSinceEpoch,
      });

      final result = await bus.replayEvents();
      final count = (result as Ok<int, Exception>).value;
      expect(count, 2);
    });

    test('replayEvents returns Err when history fails', () async {
      final db = await openRawDb();
      DatabaseService.setTestDatabase(db);
      final result = await bus.replayEvents();
      expect(result, isA<Err<int, Exception>>());
    });
  });

  // NOTE: dispose() closes the shared singleton broadcast controller, so it
  // must run last. Keep this as the final group in the file.
  group('dispose (must run last)', () {
    test('dispose closes the underlying controller', () async {
      await bus.dispose();
      // After dispose, adding via publishSync on a closed broadcast
      // controller throws; verify the controller is closed.
      expect(() => bus.publishSync(_OtherEvent()), throwsStateError);
    });
  });
}
