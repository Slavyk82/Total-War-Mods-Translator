import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/models/events/domain_event.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/translation/handlers/batch_progress_manager.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

import '../../../../helpers/fakes/fake_logger.dart';

// Characterisation tests for BatchProgressManager. Pinned behaviours:
// - getOrCreateController: idempotent per batchId, distinct across batchIds.
// - updateAndEmitProgress: emits Ok(progress) on the broadcast stream and
//   updates in-memory active-batch state (NO repository write — persistence
//   only happens via pause/resume/cancel/stop, which hit getById).
// - checkPauseOrCancel: throws CancelledException after cancel(); awaits on
//   the internal resume completer while paused and resolves when resume()
//   completes the completer.
// - cleanup: closes the stream controller and removes batch state so a fresh
//   getOrCreateController returns a new instance.

class _MockBatchRepository extends Mock implements TranslationBatchRepository {}

class _MockEventBus extends Mock implements EventBus {}

// Silent logger fake — BatchProgressManager logs info/error throughout
// pause/resume/cancel/stop and we do not want noisy stubs.

class _FakeDomainEvent extends Fake implements DomainEvent {}

// --- Fixture helpers ---------------------------------------------------

const String _batchId = 'batch-progress-1';
const String _otherBatchId = 'batch-progress-2';
const String _projectLanguageId = 'plang-1';

TranslationProgress _initialProgress({int total = 1}) {
  return TranslationProgress(
    batchId: _batchId,
    status: TranslationProgressStatus.inProgress,
    totalUnits: total,
    processedUnits: 0,
    successfulUnits: 0,
    failedUnits: 0,
    skippedUnits: 0,
    currentPhase: TranslationPhase.initializing,
    tokensUsed: 0,
    tmReuseRate: 0.0,
    timestamp: DateTime.now(),
  );
}

TranslationBatch _fakeBatch(String id) {
  return TranslationBatch(
    id: id,
    projectLanguageId: _projectLanguageId,
    providerId: 'provider_anthropic',
    batchNumber: 1,
    unitsCount: 1,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDomainEvent());
  });

  late _MockBatchRepository batchRepository;
  late _MockEventBus eventBus;
  late FakeLogger logger;
  late BatchProgressManager manager;

  setUp(() {
    batchRepository = _MockBatchRepository();
    eventBus = _MockEventBus();
    logger = FakeLogger();

    // Default: getById returns a valid batch so pause/resume/cancel/stop
    // can publish events without blowing up.
    when(() => batchRepository.getById(any()))
        .thenAnswer((_) async => Ok<TranslationBatch, TWMTDatabaseException>(
              _fakeBatch(_batchId),
            ));

    // EventBus.publish is async; return a resolved future.
    when(() => eventBus.publish(
          any(),
          triggeredBy: any(named: 'triggeredBy'),
          correlationId: any(named: 'correlationId'),
          causationId: any(named: 'causationId'),
          metadata: any(named: 'metadata'),
        )).thenAnswer((_) async {});

    manager = BatchProgressManager(
      batchRepository: batchRepository,
      eventBus: eventBus,
      logger: logger,
    );
  });

  group('getOrCreateController', () {
    test('returns same instance for same batchId, distinct for different ids',
        () {
      final a1 = manager.getOrCreateController(_batchId);
      final a2 = manager.getOrCreateController(_batchId);
      final b = manager.getOrCreateController(_otherBatchId);

      expect(identical(a1, a2), isTrue,
          reason: 'Same batchId must return the same controller instance');
      expect(identical(a1, b), isFalse,
          reason: 'Different batchIds must return distinct controllers');
      expect(a1.stream.isBroadcast, isTrue,
          reason: 'Controller must be a broadcast stream');
    });
  });

  group('updateAndEmitProgress', () {
    test('emits Ok(progress) on the stream and updates in-memory state',
        () async {
      final controller = manager.getOrCreateController(_batchId);
      final progress = _initialProgress(total: 3);

      // Subscribe BEFORE emitting — broadcast streams drop events otherwise.
      final received =
          <Result<TranslationProgress, Object>>[];
      final sub = controller.stream.listen(received.add);

      manager.updateAndEmitProgress(_batchId, progress);

      // Allow the microtask queue to flush so the stream event is delivered.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      final first = received.single;
      expect(first.isOk, isTrue);
      expect(first.unwrap(), same(progress));

      // In-memory state is refreshed so subsequent getProgress returns it.
      expect(manager.getProgress(_batchId), same(progress));

      await sub.cancel();
    });
  });

  group('checkPauseOrCancel', () {
    test('throws CancelledException after cancel()', () async {
      // Seed active state so subsequent logic has a progress snapshot.
      manager.updateProgress(_batchId, _initialProgress());

      final cancelResult = await manager.cancel(batchId: _batchId);
      expect(cancelResult.isOk, isTrue);

      expect(
        () => manager.checkPauseOrCancel(_batchId),
        throwsA(isA<CancelledException>()),
      );
    });

    test('awaits while paused and resolves after resume()', () {
      fakeAsync((async) {
        // Seed active progress so pause() does not short-circuit.
        manager.updateProgress(_batchId, _initialProgress());

        // Kick off pause — it awaits getById internally but the mock returns
        // an immediately-resolved future, so fakeAsync.flushMicrotasks lets
        // it complete synchronously in simulated time.
        bool paused = false;
        manager.pause(batchId: _batchId).then((_) => paused = true);
        async.flushMicrotasks();
        expect(paused, isTrue,
            reason: 'pause() should resolve once getById completes');

        // Now start the checkPauseOrCancel future. It should block on the
        // internal resume completer — never resolving while paused.
        bool checkDone = false;
        Object? checkError;
        manager.checkPauseOrCancel(_batchId).then(
              (_) => checkDone = true,
              onError: (Object e) => checkError = e,
            );

        // Elapse simulated time; the future must NOT complete while paused.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(checkDone, isFalse,
            reason: 'checkPauseOrCancel must await while paused');
        expect(checkError, isNull);

        // Resume — this completes the resume completer and unblocks the
        // awaiting checkPauseOrCancel call.
        manager.resume(batchId: _batchId);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        expect(checkDone, isTrue,
            reason: 'checkPauseOrCancel must resolve after resume()');
        expect(checkError, isNull);
      });
    });

    test('propagates CancelledException to pause-awaiters on cleanup()', () {
      fakeAsync((async) {
        // Seed active progress so pause() does not short-circuit.
        manager.updateProgress(_batchId, _initialProgress());

        // Pause the batch and let pause() resolve in simulated time.
        bool paused = false;
        manager.pause(batchId: _batchId).then((_) => paused = true);
        async.flushMicrotasks();
        expect(paused, isTrue);

        // Start a pause-awaiter that captures any error thrown.
        bool checkDone = false;
        Object? checkError;
        manager.checkPauseOrCancel(_batchId).then(
          (_) {
            checkDone = true;
          },
          onError: (Object e) {
            checkError = e;
          },
        );

        // Awaiter must remain blocked on the resume completer.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(checkDone, isFalse);
        expect(checkError, isNull);

        // Cleanup while paused — the awaiter must NOT silently succeed.
        manager.cleanup(_batchId);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        expect(checkDone, isFalse,
            reason: 'cleanup must not let awaiter complete normally');
        expect(checkError, isA<CancelledException>(),
            reason:
                'cleanup during pause must surface CancelledException to awaiters');
      });
    });
  });

  group('cleanup', () {
    test('closes the controller and removes state so a new controller is '
        'created on next getOrCreateController call', () async {
      final original = manager.getOrCreateController(_batchId);
      manager.updateProgress(_batchId, _initialProgress());
      // Also force creation of a cancellation token so cleanup exercises
      // that branch too.
      final token = manager.getOrCreateCancellationToken(_batchId);
      expect(token.isCancelled, isFalse);

      manager.cleanup(_batchId);

      expect(original.isClosed, isTrue,
          reason: 'cleanup must close the broadcast controller');
      expect(token.isCancelled, isTrue,
          reason: 'cleanup must cancel the LLM cancellation token');
      expect(manager.getProgress(_batchId), isNull,
          reason: 'cleanup must drop the active-batch snapshot');

      final fresh = manager.getOrCreateController(_batchId);
      expect(identical(original, fresh), isFalse,
          reason: 'a fresh controller must be created after cleanup');
      expect(fresh.isClosed, isFalse);
    });
  });

  group('pause/cancel event emission', () {
    test('cancel() publishes a BatchCancelledEvent via the event bus',
        () async {
      manager.updateProgress(_batchId, _initialProgress());

      await manager.cancel(batchId: _batchId);

      // cancel() awaits getById then publish(); verify publish was called.
      verify(() => eventBus.publish(
            any(),
            triggeredBy: any(named: 'triggeredBy'),
            correlationId: any(named: 'correlationId'),
            causationId: any(named: 'causationId'),
            metadata: any(named: 'metadata'),
          )).called(1);
    });
  });
}
