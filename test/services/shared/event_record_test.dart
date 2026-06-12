import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/models/event_record.dart';

void main() {
  final occurred = DateTime.fromMillisecondsSinceEpoch(5000);

  EventRecord record() => EventRecord(
        id: 'e1',
        eventType: 'BatchCompletedEvent',
        payload: const {'count': 3},
        occurredAt: occurred,
        aggregateId: 'b1',
        aggregateType: 'TranslationBatch',
      );

  group('EventRecord', () {
    test('round-trips through JSON', () {
      final restored = EventRecord.fromJson(record().toJson());
      expect(restored.id, 'e1');
      expect(restored.eventType, 'BatchCompletedEvent');
      expect(restored.payload, {'count': 3});
      expect(restored.occurredAt, occurred);
      expect(restored.aggregateId, 'b1');
      expect(restored.aggregateType, 'TranslationBatch');
    });

    test('copyWith overrides only the given fields', () {
      final r = record().copyWith(triggeredBy: 'user', eventType: 'Other');
      expect(r.triggeredBy, 'user');
      expect(r.eventType, 'Other');
      expect(r.id, 'e1');
    });

    test('equality is based on id, eventType and occurredAt', () {
      final a = record();
      final b = record().copyWith(aggregateId: 'different');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      final c = record().copyWith(eventType: 'Changed');
      expect(a, isNot(equals(c)));
    });

    test('toString includes id, type and aggregate id', () {
      final s = record().toString();
      expect(s, contains('e1'));
      expect(s, contains('BatchCompletedEvent'));
      expect(s, contains('b1'));
    });
  });

  group('EventStatistics', () {
    test('round-trips through JSON', () {
      final stats = EventStatistics(
        totalEvents: 10,
        eventsByType: const {'A': 6, 'B': 4},
        eventsByAggregate: const {'Project': 10},
        eventsLastHour: 2,
        eventsLastDay: 8,
        lastEventAt: DateTime.fromMillisecondsSinceEpoch(9000),
      );

      final restored = EventStatistics.fromJson(stats.toJson());

      expect(restored.totalEvents, 10);
      expect(restored.eventsByType, {'A': 6, 'B': 4});
      expect(restored.eventsByAggregate, {'Project': 10});
      expect(restored.eventsLastHour, 2);
      expect(restored.eventsLastDay, 8);
      expect(restored.lastEventAt, stats.lastEventAt);
    });

    test('tolerates a null lastEventAt', () {
      final stats = EventStatistics(
        totalEvents: 0,
        eventsByType: const {},
        eventsByAggregate: const {},
        eventsLastHour: 0,
        eventsLastDay: 0,
      );
      final restored = EventStatistics.fromJson(stats.toJson());
      expect(restored.lastEventAt, isNull);
    });
  });
}
