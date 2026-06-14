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
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
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

LlmExchangeLog _log(String requestId) => LlmExchangeLog(
      timestamp: DateTime(2024, 1, 1),
      providerCode: 'anthropic',
      modelName: 'model',
      requestId: requestId,
      unitsCount: 1,
      inputTokens: 1,
      outputTokens: 1,
      totalTokens: 2,
      processingTimeMs: 5,
      success: true,
    );

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

  group('cancellation token accessors', () {
    test('getCancellationToken returns null before creation, token after', () {
      expect(manager.getCancellationToken(_batchId), isNull);
      final created = manager.getOrCreateCancellationToken(_batchId);
      expect(manager.getCancellationToken(_batchId), same(created));
    });

    test('getOrCreateCancellationToken is idempotent per batchId', () {
      final t1 = manager.getOrCreateCancellationToken(_batchId);
      final t2 = manager.getOrCreateCancellationToken(_batchId);
      expect(identical(t1, t2), isTrue);
    });
  });

  group('updateProgress (no emit)', () {
    test('stores progress without adding to the stream', () async {
      final controller = manager.getOrCreateController(_batchId);
      final received = <Result<TranslationProgress, Object>>[];
      final sub = controller.stream.listen(received.add);

      final progress = _initialProgress();
      manager.updateProgress(_batchId, progress);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      expect(manager.getProgress(_batchId), same(progress));
      await sub.cancel();
    });
  });

  group('incrementCountersAndEmit', () {
    test('no-op when the batch is not tracked', () {
      manager.incrementCountersAndEmit('missing', successfulUnits: 5);
      expect(manager.getProgress('missing'), isNull);
    });

    test('adds counters/tokens, updates phase, recomputes percentage, emits',
        () async {
      final controller = manager.getOrCreateController(_batchId);
      manager.updateProgress(
        _batchId,
        TranslationProgress(
          batchId: _batchId,
          status: TranslationProgressStatus.inProgress,
          totalUnits: 10,
          processedUnits: 2,
          successfulUnits: 2,
          failedUnits: 0,
          skippedUnits: 0,
          currentPhase: TranslationPhase.initializing,
          tokensUsed: 100,
          tmReuseRate: 0.0,
          timestamp: DateTime(2024, 1, 1),
        ),
      );

      final received = <Result<TranslationProgress, Object>>[];
      final sub = controller.stream.listen(received.add);

      manager.incrementCountersAndEmit(
        _batchId,
        successfulUnits: 3,
        failedUnits: 1,
        processedUnits: 4,
        tokensUsed: 50,
        phaseDetail: 'chunk-2',
        currentPhase: TranslationPhase.llmTranslation,
      );
      await Future<void>.delayed(Duration.zero);

      final updated = manager.getProgress(_batchId)!;
      expect(updated.successfulUnits, 5);
      expect(updated.failedUnits, 1);
      expect(updated.processedUnits, 6);
      expect(updated.tokensUsed, 150);
      expect(updated.phaseDetail, 'chunk-2');
      expect(updated.currentPhase, TranslationPhase.llmTranslation);
      // 6 / 10 = 0.6
      expect(updated.progressPercentage, closeTo(0.6, 1e-9));

      expect(received, hasLength(1));
      expect(received.single.unwrap(), same(updated));
      await sub.cancel();
    });

    test('zero totalUnits yields 0.0 percentage (guards division)', () {
      manager.updateProgress(
        _batchId,
        TranslationProgress(
          batchId: _batchId,
          status: TranslationProgressStatus.inProgress,
          totalUnits: 0,
          processedUnits: 0,
          successfulUnits: 0,
          failedUnits: 0,
          skippedUnits: 0,
          currentPhase: TranslationPhase.initializing,
          tokensUsed: 0,
          tmReuseRate: 0.0,
          timestamp: DateTime(2024, 1, 1),
        ),
      );
      manager.incrementCountersAndEmit(_batchId, processedUnits: 0);
      expect(manager.getProgress(_batchId)!.progressPercentage, 0.0);
    });

    test('appends new logs and de-duplicates by requestId', () {
      manager.updateProgress(
        _batchId,
        _initialProgress().copyWith(llmLogs: [_log('r1')]),
      );

      manager.incrementCountersAndEmit(
        _batchId,
        appendLogs: [_log('r1'), _log('r2')],
      );

      expect(
        manager.getProgress(_batchId)!.llmLogs.map((l) => l.requestId),
        ['r1', 'r2'],
      );
    });

    test('empty appendLogs leaves logs unchanged', () {
      manager.updateProgress(
        _batchId,
        _initialProgress().copyWith(llmLogs: [_log('r1')]),
      );
      manager.incrementCountersAndEmit(_batchId, appendLogs: const []);
      expect(
        manager.getProgress(_batchId)!.llmLogs.map((l) => l.requestId),
        ['r1'],
      );
    });
  });

  group('updatePhaseAndEmit', () {
    test('no-op when the batch is not tracked', () {
      manager.updatePhaseAndEmit('missing', phaseDetail: 'x');
      expect(manager.getProgress('missing'), isNull);
    });

    test('updates phase fields and logs without touching counters, emits',
        () async {
      final controller = manager.getOrCreateController(_batchId);
      manager.updateProgress(
        _batchId,
        _initialProgress().copyWith(processedUnits: 4, successfulUnits: 4),
      );

      final received = <Result<TranslationProgress, Object>>[];
      final sub = controller.stream.listen(received.add);

      manager.updatePhaseAndEmit(
        _batchId,
        phaseDetail: 'saving',
        currentPhase: TranslationPhase.saving,
        appendLogs: [_log('r9')],
      );
      await Future<void>.delayed(Duration.zero);

      final p = manager.getProgress(_batchId)!;
      expect(p.currentPhase, TranslationPhase.saving);
      expect(p.phaseDetail, 'saving');
      expect(p.processedUnits, 4);
      expect(p.successfulUnits, 4);
      expect(p.llmLogs.map((l) => l.requestId), ['r9']);
      expect(received, hasLength(1));
      await sub.cancel();
    });

    test('null appendLogs leaves logs unchanged', () {
      manager.updateProgress(
        _batchId,
        _initialProgress().copyWith(llmLogs: [_log('r1')]),
      );
      manager.updatePhaseAndEmit(_batchId, phaseDetail: 'x');
      expect(
        manager.getProgress(_batchId)!.llmLogs.map((l) => l.requestId),
        ['r1'],
      );
    });
  });

  group('pause', () {
    test('errors when batch is not active', () async {
      final result = await manager.pause(batchId: _batchId);
      expect(result.isErr, isTrue);
      final err = result.unwrapErr();
      expect(err, isA<InvalidStateException>());
      expect((err as InvalidStateException).currentState, 'not_active');
    });

    test('errors when batch is already paused', () async {
      manager.updateProgress(
        _batchId,
        _initialProgress().copyWith(status: TranslationProgressStatus.paused),
      );
      final result = await manager.pause(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect((result.unwrapErr() as InvalidStateException).currentState,
          'paused');
    });

    test('pauses active batch, flips status and publishes BatchPausedEvent',
        () async {
      manager.updateProgress(_batchId, _initialProgress(total: 10));

      final result = await manager.pause(batchId: _batchId);

      expect(result.isOk, isTrue);
      expect(manager.getProgress(_batchId)!.status,
          TranslationProgressStatus.paused);
      verify(() => eventBus.publish(
            any(),
            triggeredBy: any(named: 'triggeredBy'),
            correlationId: any(named: 'correlationId'),
            causationId: any(named: 'causationId'),
            metadata: any(named: 'metadata'),
          )).called(1);
    });

    test('still succeeds when getById returns Err (empty projectLanguageId)',
        () async {
      when(() => batchRepository.getById(any())).thenAnswer((_) async =>
          Err<TranslationBatch, TWMTDatabaseException>(
              TWMTDatabaseException('missing')));
      manager.updateProgress(_batchId, _initialProgress());

      final result = await manager.pause(batchId: _batchId);
      expect(result.isOk, isTrue);
    });

    test('returns Err when the repository throws', () async {
      when(() => batchRepository.getById(any()))
          .thenThrow(Exception('boom'));
      manager.updateProgress(_batchId, _initialProgress());

      final result = await manager.pause(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
    });
  });

  group('resume', () {
    test('errors when batch is not paused', () async {
      final result = await manager.resume(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect((result.unwrapErr() as InvalidStateException).currentState,
          'not_paused');
    });

    test('resumes paused batch, flips status and publishes BatchResumedEvent',
        () async {
      manager.updateProgress(_batchId, _initialProgress(total: 8));
      await manager.pause(batchId: _batchId);

      final result = await manager.resume(batchId: _batchId);

      expect(result.isOk, isTrue);
      expect(manager.getProgress(_batchId)!.status,
          TranslationProgressStatus.inProgress);
      // pause + resume publish twice in total.
      verify(() => eventBus.publish(
            any(),
            triggeredBy: any(named: 'triggeredBy'),
            correlationId: any(named: 'correlationId'),
            causationId: any(named: 'causationId'),
            metadata: any(named: 'metadata'),
          )).called(2);
    });

    test('still succeeds when getById returns Err', () async {
      manager.updateProgress(_batchId, _initialProgress());
      await manager.pause(batchId: _batchId);
      when(() => batchRepository.getById(any())).thenAnswer((_) async =>
          Err<TranslationBatch, TWMTDatabaseException>(
              TWMTDatabaseException('missing')));

      final result = await manager.resume(batchId: _batchId);
      expect(result.isOk, isTrue);
    });

    test('returns Err when the repository throws', () async {
      manager.updateProgress(_batchId, _initialProgress());
      await manager.pause(batchId: _batchId);
      when(() => batchRepository.getById(any()))
          .thenThrow(Exception('boom'));

      final result = await manager.resume(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
    });
  });

  group('cancel', () {
    test('uses defaults when no progress and getById fails', () async {
      when(() => batchRepository.getById(any())).thenAnswer((_) async =>
          Err<TranslationBatch, TWMTDatabaseException>(
              TWMTDatabaseException('missing')));

      final result = await manager.cancel(batchId: _batchId);
      expect(result.isOk, isTrue);
    });

    test('returns Err when the repository throws', () async {
      when(() => batchRepository.getById(any()))
          .thenThrow(Exception('boom'));
      final result = await manager.cancel(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
    });
  });

  group('stop', () {
    test('cancels token, publishes event and trips checkPauseOrCancel',
        () async {
      final token = manager.getOrCreateCancellationToken(_batchId);
      manager.updateProgress(_batchId, _initialProgress());

      final result = await manager.stop(batchId: _batchId);

      expect(result.isOk, isTrue);
      expect(token.isCancelled, isTrue);
      verify(() => eventBus.publish(
            any(),
            triggeredBy: any(named: 'triggeredBy'),
            correlationId: any(named: 'correlationId'),
            causationId: any(named: 'causationId'),
            metadata: any(named: 'metadata'),
          )).called(1);
      expect(
        () => manager.checkPauseOrCancel(_batchId),
        throwsA(isA<CancelledException>()),
      );
    });

    test('succeeds with no token/progress and getById failing', () async {
      when(() => batchRepository.getById(any())).thenAnswer((_) async =>
          Err<TranslationBatch, TWMTDatabaseException>(
              TWMTDatabaseException('missing')));
      final result = await manager.stop(batchId: _batchId);
      expect(result.isOk, isTrue);
    });

    test('returns Err when the repository throws', () async {
      when(() => batchRepository.getById(any()))
          .thenThrow(Exception('boom'));
      final result = await manager.stop(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
    });
  });

  group('getStatus / isActive / getActiveBatchIds', () {
    test('getStatus returns tracked progress', () async {
      final p = _initialProgress();
      manager.updateProgress(_batchId, p);
      final result = await manager.getStatus(batchId: _batchId);
      expect(result.isOk, isTrue);
      expect(result.unwrap(), same(p));
    });

    test('getStatus returns null when untracked', () async {
      final result = await manager.getStatus(batchId: 'absent');
      expect(result.isOk, isTrue);
      expect(result.unwrap(), isNull);
    });

    test('isActive is true when tracked', () async {
      manager.updateProgress(_batchId, _initialProgress());
      expect(await manager.isActive(batchId: _batchId), isTrue);
    });

    test('isActive is true when paused even if removed from active map',
        () async {
      manager.updateProgress(_batchId, _initialProgress());
      await manager.pause(batchId: _batchId);
      expect(await manager.isActive(batchId: _batchId), isTrue);
    });

    test('isActive is false when unknown', () async {
      expect(await manager.isActive(batchId: 'nope'), isFalse);
    });

    test('getActiveBatchIds lists all tracked batch ids', () async {
      manager.updateProgress(_batchId, _initialProgress());
      manager.updateProgress(_otherBatchId, _initialProgress());
      final ids = await manager.getActiveBatchIds();
      expect(ids, containsAll([_batchId, _otherBatchId]));
    });
  });

  group('checkPauseOrCancel edge cases', () {
    test('returns normally when no flags are set', () async {
      await manager.checkPauseOrCancel(_batchId);
    });

    test('throws when stopped', () async {
      await manager.stop(batchId: _batchId);
      expect(
        () => manager.checkPauseOrCancel(_batchId),
        throwsA(isA<CancelledException>()),
      );
    });

    test('paused then resumed (completer cleared) falls through', () async {
      manager.updateProgress(_batchId, _initialProgress());
      await manager.pause(batchId: _batchId);
      await manager.resume(batchId: _batchId);
      await manager.checkPauseOrCancel(_batchId);
    });

    test('cancel after pause completer wakes the waiter via cleanup', () async {
      // pause registers a resume completer; cleanup() marks the batch cancelled
      // and completes that completer, so the post-resume re-check throws.
      manager.updateProgress(_batchId, _initialProgress());
      await manager.pause(batchId: _batchId);

      final future = manager.checkPauseOrCancel(_batchId);
      manager.cleanup(_batchId);

      await expectLater(future, throwsA(isA<CancelledException>()));
    });
  });

  group('cleanup edge cases', () {
    test('cleanup of an unknown batch is a no-op', () {
      expect(() => manager.cleanup('unknown'), returnsNormally);
    });
  });
}
