import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/models/events/domain_event.dart';
import 'package:twmt/providers/translation/batch_state_provider.dart';
import 'package:twmt/services/shared/event_bus.dart';

/// Tests for [BatchStateNotifier], the Riverpod notifier that maintains a
/// [BatchState] for one `batchId` by listening to the batch event streams.
///
/// The event-stream providers are thin adapters over the [EventBus] singleton.
/// Reading `batchStateNotifierProvider(id)` runs `build()`, which registers the
/// seven `ref.listen` subscriptions synchronously — so the underlying broadcast
/// listeners are active BEFORE we publish (a broadcast stream drops events
/// emitted while it has no listener). We then publish with the synchronous
/// [EventBus.publishSync] and drain the microtask queue with [pumpEventQueue].
void main() {
  const batchId = 'batch-1';

  BatchStartedEvent started({String id = batchId}) => BatchStartedEvent(
        batchId: id,
        projectLanguageId: 'pl-1',
        providerId: 'prov-1',
        batchNumber: 4,
        totalUnits: 20,
      );

  BatchProgressEvent progress({String id = batchId}) => BatchProgressEvent(
        batchId: id,
        totalUnits: 20,
        completedUnits: 10,
        failedUnits: 2,
      );

  BatchCompletedEvent completed({String id = batchId}) => BatchCompletedEvent(
        batchId: id,
        projectLanguageId: 'pl-1',
        batchNumber: 4,
        totalUnits: 20,
        completedUnits: 18,
        failedUnits: 2,
        processingDuration: const Duration(seconds: 3),
      );

  BatchFailedEvent failed({String id = batchId}) => BatchFailedEvent(
        batchId: id,
        projectLanguageId: 'pl-1',
        batchNumber: 4,
        errorMessage: 'network down',
        completedBeforeFailure: 5,
        totalUnits: 20,
        retryCount: 1,
      );

  BatchPausedEvent paused({String id = batchId}) => BatchPausedEvent(
        batchId: id,
        projectLanguageId: 'pl-1',
        completedUnits: 6,
        totalUnits: 20,
      );

  BatchResumedEvent resumed({String id = batchId}) => BatchResumedEvent(
        batchId: id,
        projectLanguageId: 'pl-1',
        completedUnits: 6,
        totalUnits: 20,
      );

  BatchCancelledEvent cancelled({String id = batchId}) => BatchCancelledEvent(
        batchId: id,
        projectLanguageId: 'pl-1',
        completedUnits: 3,
        totalUnits: 20,
        reason: 'user',
      );

  /// Builds a container, activates the notifier (registering its listeners),
  /// publishes [events] synchronously, and returns the resulting state.
  Future<BatchState> stateAfter(
    List<DomainEvent> events, {
    String id = batchId,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Keep the (autoDispose) notifier mounted for the whole test: build() runs
    // _listenToEvents(), activating all seven broadcast subscriptions, and the
    // listener stops the notifier from being disposed (and rebuilt fresh)
    // across the async event delivery below.
    container.listen(batchStateProvider(id), (_, _) {});

    for (final event in events) {
      EventBus.instance.publishSync(event);
    }
    await pumpEventQueue();

    return container.read(batchStateProvider(id));
  }

  group('BatchStateNotifier initial state', () {
    test('build returns an idle state for the requested batchId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(batchStateProvider(batchId));

      expect(state.batchId, batchId);
      expect(state.status, BatchStatus.idle);
      expect(state.totalUnits, 0);
      expect(state.completedUnits, 0);
    });
  });

  group('BatchStateNotifier event handling', () {
    test('BatchStartedEvent moves the batch to running with metadata',
        () async {
      final state = await stateAfter([started()]);

      expect(state.status, BatchStatus.running);
      expect(state.totalUnits, 20);
      expect(state.batchNumber, 4);
      expect(state.projectLanguageId, 'pl-1');
      expect(state.startedAt, isNotNull);
    });

    test('BatchProgressEvent updates completed/failed counts and percent',
        () async {
      final state = await stateAfter([started(), progress()]);

      expect(state.completedUnits, 10);
      expect(state.failedUnits, 2);
      expect(state.progressPercent, 50.0);
      expect(state.hasErrors, isTrue);
      expect(state.remainingUnits, 8);
    });

    test('BatchCompletedEvent marks the batch completed', () async {
      final state = await stateAfter([started(), completed()]);

      expect(state.status, BatchStatus.completed);
      expect(state.completedUnits, 18);
      expect(state.failedUnits, 2);
      expect(state.completedAt, isNotNull);
      expect(state.isComplete, isTrue);
    });

    test('BatchFailedEvent marks the batch failed and records the message',
        () async {
      final state = await stateAfter([started(), failed()]);

      expect(state.status, BatchStatus.failed);
      expect(state.errorMessage, 'network down');
      expect(state.completedAt, isNotNull);
      expect(state.isComplete, isTrue);
    });

    test('BatchPausedEvent marks the batch paused', () async {
      final state = await stateAfter([started(), paused()]);

      expect(state.status, BatchStatus.paused);
      expect(state.isActive, isTrue);
    });

    test('BatchResumedEvent returns a paused batch to running', () async {
      final state = await stateAfter([started(), paused(), resumed()]);

      expect(state.status, BatchStatus.running);
    });

    test('BatchCancelledEvent marks the batch cancelled', () async {
      final state = await stateAfter([started(), cancelled()]);

      expect(state.status, BatchStatus.cancelled);
      expect(state.completedAt, isNotNull);
      expect(state.isComplete, isTrue);
    });

    test('ignores events addressed to a different batchId', () async {
      // The notifier tracks 'batch-1'; every event targets 'other'.
      final state = await stateAfter([
        started(id: 'other'),
        progress(id: 'other'),
        completed(id: 'other'),
      ]);

      expect(state.status, BatchStatus.idle);
      expect(state.totalUnits, 0);
      expect(state.completedUnits, 0);
    });
  });
}
