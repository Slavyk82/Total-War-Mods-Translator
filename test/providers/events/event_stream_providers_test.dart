import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/providers/events/event_stream_providers.dart';
import 'package:twmt/services/shared/event_bus.dart';

/// Tests for the Riverpod stream providers in
/// `lib/providers/events/event_stream_providers.dart`.
///
/// Each provider is a thin adapter over the [EventBus] broadcast singleton:
/// `Stream<XEvent> xEvents(Ref ref) => EventBus.instance.on<XEvent>();`.
///
/// We publish through the real singleton with [EventBus.publishSync] (which is
/// synchronous) and assert the provider exposes the expected events.
///
/// Riverpod 3 `$StreamProvider`s do not expose a `.stream` getter, so we
/// subscribe with [ProviderContainer.listen] and accumulate every [AsyncData]
/// value. Listening also keeps the provider alive (it is `keepAlive: false`)
/// and, crucially, activates the underlying broadcast-stream listener BEFORE we
/// publish — a broadcast stream drops events emitted while it has no listener.
void main() {
  // Collects the successful values emitted by a stream provider.
  //
  // [read] reads the provider's `AsyncValue`; [listen] registers the listener.
  // We pass both as closures so the same helper works for plain providers and
  // for family providers (which are invoked with an argument).
  List<T> listenValues<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
  ) {
    final values = <T>[];
    final sub = container.listen<AsyncValue<T>>(
      provider,
      (previous, next) {
        next.whenData(values.add);
      },
    );
    addTearDown(sub.close);
    // Read once to force the provider (and its stream subscription) to be
    // created/active before any event is published.
    container.read(provider);
    return values;
  }

  // ----- Event factories (minimal valid instances) -----

  BatchStartedEvent makeBatchStarted({String batchId = 'b1'}) =>
      BatchStartedEvent(
        batchId: batchId,
        projectLanguageId: 'pl1',
        providerId: 'prov1',
        batchNumber: 1,
        totalUnits: 10,
      );

  BatchProgressEvent makeBatchProgress({String batchId = 'b1'}) =>
      BatchProgressEvent(
        batchId: batchId,
        totalUnits: 10,
        completedUnits: 5,
        failedUnits: 0,
      );

  BatchCompletedEvent makeBatchCompleted({String batchId = 'b1'}) =>
      BatchCompletedEvent(
        batchId: batchId,
        projectLanguageId: 'pl1',
        batchNumber: 1,
        totalUnits: 10,
        completedUnits: 10,
        failedUnits: 0,
        processingDuration: const Duration(seconds: 1),
      );

  BatchFailedEvent makeBatchFailed({String batchId = 'b1'}) => BatchFailedEvent(
        batchId: batchId,
        projectLanguageId: 'pl1',
        batchNumber: 1,
        errorMessage: 'boom',
        completedBeforeFailure: 3,
        totalUnits: 10,
        retryCount: 0,
      );

  BatchPausedEvent makeBatchPaused() => BatchPausedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 4,
        totalUnits: 10,
      );

  BatchResumedEvent makeBatchResumed() => BatchResumedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 4,
        totalUnits: 10,
      );

  BatchCancelledEvent makeBatchCancelled() => BatchCancelledEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 2,
        totalUnits: 10,
        reason: 'user',
      );

  // ===================== Batch event streams (7) =====================

  group('batch event streams', () {
    test('batchStartedEventsProvider receives published BatchStartedEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchStartedEventsProvider);

      EventBus.instance.publishSync(makeBatchStarted());
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.batchId, 'b1');
    });

    test('batchProgressEventsProvider receives published BatchProgressEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchProgressEventsProvider);

      EventBus.instance.publishSync(makeBatchProgress());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('batchCompletedEventsProvider receives published BatchCompletedEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchCompletedEventsProvider);

      EventBus.instance.publishSync(makeBatchCompleted());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('batchFailedEventsProvider receives published BatchFailedEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchFailedEventsProvider);

      EventBus.instance.publishSync(makeBatchFailed());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('batchPausedEventsProvider receives published BatchPausedEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchPausedEventsProvider);

      EventBus.instance.publishSync(makeBatchPaused());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('batchResumedEventsProvider receives published BatchResumedEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchResumedEventsProvider);

      EventBus.instance.publishSync(makeBatchResumed());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('batchCancelledEventsProvider receives published BatchCancelledEvent',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchCancelledEventsProvider);

      EventBus.instance.publishSync(makeBatchCancelled());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });
  });

  // =================== Filtered family providers (3) ==================

  group('filtered family providers', () {
    test('batchProgressForBatchProvider only receives matching batchId',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, batchProgressForBatchProvider('target'));

      EventBus.instance.publishSync(makeBatchProgress(batchId: 'other'));
      EventBus.instance.publishSync(makeBatchProgress(batchId: 'target'));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.batchId, 'target');
    });

    test('batchCompletedForBatchProvider only receives matching batchId',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, batchCompletedForBatchProvider('target'));

      EventBus.instance.publishSync(makeBatchCompleted(batchId: 'other'));
      EventBus.instance.publishSync(makeBatchCompleted(batchId: 'target'));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.batchId, 'target');
    });

    test('batchFailedForBatchProvider only receives matching batchId',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, batchFailedForBatchProvider('target'));

      EventBus.instance.publishSync(makeBatchFailed(batchId: 'other'));
      EventBus.instance.publishSync(makeBatchFailed(batchId: 'target'));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.batchId, 'target');
    });
  });

  // ========================= Type filtering ==========================

  group('runtime type filtering', () {
    test('a typed provider ignores events of a different type', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, batchStartedEventsProvider);

      // Publish a different batch event type; it must NOT be delivered.
      EventBus.instance.publishSync(makeBatchCompleted());
      await pumpEventQueue();
      expect(received, isEmpty);

      // The matching type IS delivered.
      EventBus.instance.publishSync(makeBatchStarted());
      await pumpEventQueue();
      expect(received, hasLength(1));
    });
  });
}
