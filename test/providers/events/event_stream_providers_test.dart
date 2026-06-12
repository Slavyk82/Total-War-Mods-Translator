import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/models/events/project_events.dart';
import 'package:twmt/models/events/tm_events.dart';
import 'package:twmt/models/events/translation_events.dart';
import 'package:twmt/providers/events/event_stream_providers.dart';
import 'package:twmt/services/shared/event_bus.dart';

import '../../helpers/noop_logger.dart';

/// Tests for the 18 Riverpod stream providers in
/// `lib/providers/events/event_stream_providers.dart`.
///
/// Each provider is a thin adapter over the [EventBus] broadcast singleton:
/// `Stream<XEvent> xEvents(Ref ref) => EventBus.instance.on<XEvent>();`.
///
/// We publish through the real singleton with [EventBus.publishSync] (which is
/// synchronous and never touches the database) and assert the provider exposes
/// the expected events.
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

  TranslationAddedEvent makeTranslationAdded() => TranslationAddedEvent(
        versionId: 'v1',
        unitId: 'u1',
        projectLanguageId: 'pl1',
        translatedText: 'hello',
      );

  TranslationEditedEvent makeTranslationEdited() => TranslationEditedEvent(
        versionId: 'v1',
        unitId: 'u1',
        oldTranslation: 'a',
        newTranslation: 'b',
        editedBy: 'tester',
      );

  TranslationValidatedEvent makeTranslationValidated() =>
      TranslationValidatedEvent(
        versionId: 'v1',
        unitId: 'u1',
        status: 'translated',
        validatedBy: 'tester',
      );

  TranslationDeletedEvent makeTranslationDeleted() => TranslationDeletedEvent(
        versionId: 'v1',
        unitId: 'u1',
        projectLanguageId: 'pl1',
        deletedBy: 'tester',
        reason: 'cleanup',
      );

  TranslationStatusChangedEvent makeTranslationStatusChanged() =>
      TranslationStatusChangedEvent(
        versionId: 'v1',
        unitId: 'u1',
        oldStatus: 'pending',
        newStatus: 'translated',
      );

  ProjectCreatedEvent makeProjectCreated({String projectId = 'p1'}) =>
      ProjectCreatedEvent(
        projectId: projectId,
        projectName: 'My Project',
        gameInstallationId: 'g1',
        targetLanguageIds: const ['fr', 'de'],
      );

  ProjectUpdatedEvent makeProjectUpdated({String projectId = 'p1'}) =>
      ProjectUpdatedEvent(
        projectId: projectId,
        changes: const {'name': 'new'},
      );

  ProjectCompletedEvent makeProjectCompleted({String projectId = 'p1'}) =>
      ProjectCompletedEvent(
        projectId: projectId,
        projectName: 'My Project',
        totalUnits: 100,
        completedLanguages: 2,
        totalDuration: const Duration(hours: 1),
      );

  TranslationAddedToTmEvent makeTranslationAddedToTm() =>
      TranslationAddedToTmEvent(
        versionId: 'v1',
        unitId: 'u1',
        tmId: 'tm1',
        sourceText: 'source',
        translatedText: 'target',
        targetLanguageId: 'fr',
        gameContext: 'ctx',
      );

  setUpAll(() {
    // Not strictly needed for publishSync (no DB / no logging), but keep the
    // bus quiet in case any path logs.
    EventBus.loggerForTesting = NoopLogger();
  });

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

  // ================== Translation event streams (5) ==================

  group('translation event streams', () {
    test('translationAddedEventsProvider receives published event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, translationAddedEventsProvider);

      EventBus.instance.publishSync(makeTranslationAdded());
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.translatedText, 'hello');
    });

    test('translationEditedEventsProvider receives published event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, translationEditedEventsProvider);

      EventBus.instance.publishSync(makeTranslationEdited());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('translationValidatedEventsProvider receives published event',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, translationValidatedEventsProvider);

      EventBus.instance.publishSync(makeTranslationValidated());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('translationDeletedEventsProvider receives published event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, translationDeletedEventsProvider);

      EventBus.instance.publishSync(makeTranslationDeleted());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('translationStatusChangedEventsProvider receives published event',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, translationStatusChangedEventsProvider);

      EventBus.instance.publishSync(makeTranslationStatusChanged());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });
  });

  // ==================== Project event streams (3) ====================

  group('project event streams', () {
    test('projectCreatedEventsProvider receives published event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, projectCreatedEventsProvider);

      EventBus.instance.publishSync(makeProjectCreated());
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.projectId, 'p1');
    });

    test('projectUpdatedEventsProvider receives published event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, projectUpdatedEventsProvider);

      EventBus.instance.publishSync(makeProjectUpdated());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('projectCompletedEventsProvider receives published event', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues(container, projectCompletedEventsProvider);

      EventBus.instance.publishSync(makeProjectCompleted());
      await pumpEventQueue();

      expect(received, hasLength(1));
    });
  });

  // ======================= TM event stream (1) =======================

  group('TM event stream', () {
    test('translationAddedToTmEventsProvider receives published event',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received =
          listenValues(container, translationAddedToTmEventsProvider);

      EventBus.instance.publishSync(makeTranslationAddedToTm());
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.tmId, 'tm1');
    });
  });

  // =================== Filtered family providers (4) ==================

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

    test('projectEventsProvider only receives matching projectId', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues<ProjectEvent>(
        container,
        projectEventsProvider('target'),
      );

      // Non-matching project, then matching project.
      EventBus.instance.publishSync(makeProjectCreated(projectId: 'other'));
      EventBus.instance.publishSync(makeProjectUpdated(projectId: 'target'));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.projectId, 'target');
    });

    test(
        'projectEventsProvider matches any ProjectEvent subtype for the project',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final received = listenValues<ProjectEvent>(
        container,
        projectEventsProvider('p1'),
      );

      // Three different ProjectEvent subtypes, all for 'p1'.
      EventBus.instance.publishSync(makeProjectCreated(projectId: 'p1'));
      EventBus.instance.publishSync(makeProjectUpdated(projectId: 'p1'));
      EventBus.instance.publishSync(makeProjectCompleted(projectId: 'p1'));
      await pumpEventQueue();

      expect(received, hasLength(3));
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
