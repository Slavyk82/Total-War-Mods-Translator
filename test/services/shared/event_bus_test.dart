import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/domain_event.dart';
import 'package:twmt/services/shared/event_bus.dart';

/// A concrete [DomainEvent] used to exercise the bus.
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

void main() {
  final EventBus bus = EventBus.instance;

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

    test('publishSync delivers synchronously', () async {
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
