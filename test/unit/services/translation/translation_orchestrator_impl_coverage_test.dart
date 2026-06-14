import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/common/validation_result.dart' as common;
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/models/domain/translation_batch_unit.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/models/events/domain_event.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/history/history_change_entry.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/features/activity/services/activity_logger.dart';
import 'package:twmt/models/events/activity_event.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/translation/batch_translation_cache.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/translation_orchestrator_impl.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';

import '../../../helpers/fakes/fake_logger.dart';

// --- Mocks --------------------------------------------------------------

class _MockLlmService extends Mock implements ILlmService {}

class _MockTmService extends Mock implements ITranslationMemoryService {}

class _MockPromptBuilder extends Mock implements IPromptBuilderService {}

class _MockValidation extends Mock implements IValidationService {}

class _MockHistoryService extends Mock implements IHistoryService {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockUnitRepository extends Mock implements TranslationUnitRepository {}

class _MockBatchRepository extends Mock implements TranslationBatchRepository {}

class _MockBatchUnitRepository extends Mock
    implements TranslationBatchUnitRepository {}

class _MockTransactionManager extends Mock implements TransactionManager {}

class _MockEventBus extends Mock implements EventBus {}

class _MockProviderRepository extends Mock
    implements TranslationProviderRepository {}

class _MockActivityLogger extends Mock implements ActivityLogger {}

class _FakeLogger extends FakeLogger {
  final List<String> warnings = [];
  final List<String> debugs = [];

  @override
  void warning(String message, [dynamic data]) {
    warnings.add(message);
  }

  @override
  void debug(String message, [dynamic data]) {
    debugs.add(message);
  }
}

// Fallback objects for mocktail argument matchers.
class _FakeTranslationContext extends Fake implements TranslationContext {}

class _FakeTranslationUnit extends Fake implements TranslationUnit {}

class _FakeTransaction extends Fake implements Transaction {}

class _FakeTranslationVersion extends Fake implements TranslationVersion {}

class _FakeLlmRequest extends Fake implements LlmRequest {}

class _FakeTranslationBatch extends Fake implements TranslationBatch {}

class _FakeDomainEvent extends Fake implements DomainEvent {}

// --- Fixtures ----------------------------------------------------------

const String _projectId = 'project-1';
const String _projectLanguageId = 'plang-1';
const String _batchId = 'batch-1';

TranslationUnit _fakeUnit(String key, String source) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return TranslationUnit(
    id: 'unit-$key',
    projectId: _projectId,
    key: key,
    sourceText: source,
    createdAt: now,
    updatedAt: now,
  );
}

TranslationBatch _fakeBatch(String id, {int unitsCount = 0, int retry = 0}) {
  return TranslationBatch(
    id: id,
    projectLanguageId: _projectLanguageId,
    providerId: 'provider_anthropic',
    batchNumber: 1,
    unitsCount: unitsCount,
    retryCount: retry,
  );
}

TranslationBatchUnit _fakeBatchUnit(String unitId, int order) {
  return TranslationBatchUnit(
    id: 'bu-$unitId',
    batchId: _batchId,
    unitId: unitId,
    processingOrder: order,
  );
}

TranslationContext _fakeContext({bool skipTm = false, int parallelBatches = 1}) {
  final now = DateTime.now();
  return TranslationContext(
    id: 'ctx-1',
    projectId: _projectId,
    projectLanguageId: _projectLanguageId,
    providerId: 'provider_anthropic',
    modelId: 'claude-haiku-4.5',
    targetLanguage: 'fr',
    sourceLanguage: 'en',
    skipTranslationMemory: skipTm,
    parallelBatches: parallelBatches,
    createdAt: now,
    updatedAt: now,
  );
}

LlmResponse _fakeLlmResponse(Map<String, String> translations) {
  return LlmResponse(
    requestId: 'req-1',
    translations: translations,
    providerCode: 'anthropic',
    modelName: 'claude-haiku-4.5',
    inputTokens: 100,
    outputTokens: 100,
    totalTokens: 200,
    processingTimeMs: 50,
    timestamp: DateTime.now(),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTranslationContext());
    registerFallbackValue(_FakeTranslationUnit());
    registerFallbackValue(_FakeTransaction());
    registerFallbackValue(_FakeTranslationVersion());
    registerFallbackValue(_FakeLlmRequest());
    registerFallbackValue(_FakeTranslationBatch());
    registerFallbackValue(_FakeDomainEvent());
    registerFallbackValue(<TranslationUnit>[]);
    registerFallbackValue(<TranslationVersion>[]);
    registerFallbackValue(<HistoryChangeEntry>[]);
    registerFallbackValue(<String, int>{});
    registerFallbackValue(<({String sourceText, String targetText})>[]);
    registerFallbackValue(StackTrace.empty);
  });

  late _MockLlmService llmService;
  late _MockTmService tmService;
  late _MockPromptBuilder promptBuilder;
  late _MockValidation validation;
  late _MockHistoryService historyService;
  late _MockVersionRepository versionRepository;
  late _MockUnitRepository unitRepository;
  late _MockBatchRepository batchRepository;
  late _MockBatchUnitRepository batchUnitRepository;
  late _MockTransactionManager transactionManager;
  late _MockEventBus eventBus;
  late _FakeLogger logger;
  late TranslationOrchestratorImpl service;

  setUp(() async {
    BatchTranslationCache.instance.clear();

    if (GetIt.I.isRegistered<TranslationProviderRepository>()) {
      await GetIt.I.unregister<TranslationProviderRepository>();
    }
    final mockProviderRepo = _MockProviderRepository();
    when(() => mockProviderRepo.getByCode(any())).thenAnswer(
      (_) async => Err(TWMTDatabaseException('not found in test')),
    );
    GetIt.I.registerSingleton<TranslationProviderRepository>(mockProviderRepo);

    llmService = _MockLlmService();
    tmService = _MockTmService();
    promptBuilder = _MockPromptBuilder();
    validation = _MockValidation();
    historyService = _MockHistoryService();
    versionRepository = _MockVersionRepository();
    unitRepository = _MockUnitRepository();
    batchRepository = _MockBatchRepository();
    batchUnitRepository = _MockBatchUnitRepository();
    transactionManager = _MockTransactionManager();
    eventBus = _MockEventBus();
    logger = _FakeLogger();

    when(() => batchRepository.getById(any()))
        .thenAnswer((_) async => Ok(_fakeBatch(_batchId, unitsCount: 2)));
    when(() => batchRepository.update(any())).thenAnswer(
      (inv) async => Ok(inv.positionalArguments[0] as TranslationBatch),
    );

    when(() => batchUnitRepository.findByBatchId(any()))
        .thenAnswer((_) async => Ok([_fakeBatchUnit('hello', 0)]));
    when(() => unitRepository.getByIds(any())).thenAnswer(
      (_) async => Ok([_fakeUnit('hello', 'Hello world')]),
    );

    when(() => tmService.findExactMatch(
          sourceText: any(named: 'sourceText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => Ok(null));
    when(() => tmService.findFuzzyMatchesIsolate(
          sourceText: any(named: 'sourceText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          minSimilarity: any(named: 'minSimilarity'),
          maxResults: any(named: 'maxResults'),
          category: any(named: 'category'),
        )).thenAnswer((_) async => Ok(const <TmMatch>[]));
    when(() => tmService.incrementUsageCountBatch(any()))
        .thenAnswer((_) async => Ok(0));
    when(() => tmService.addTranslationsBatch(
          translations: any(named: 'translations'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((inv) async {
      final list = inv.namedArguments[#translations]
          as List<({String sourceText, String targetText})>;
      return Ok(list.length);
    });

    when(() => versionRepository.getTranslatedUnitIds(
          unitIds: any(named: 'unitIds'),
          projectLanguageId: any(named: 'projectLanguageId'),
        )).thenAnswer((_) async => Ok(<String>{}));
    when(() => versionRepository.upsert(any())).thenAnswer(
      (inv) async => Ok(inv.positionalArguments[0] as TranslationVersion),
    );
    when(() => versionRepository.upsertBatchOptimized(
          entities: any(named: 'entities'),
          onProgress: any(named: 'onProgress'),
        )).thenAnswer((inv) async {
      final entities =
          inv.namedArguments[#entities] as List<TranslationVersion>;
      return Ok((
        inserted: entities.length,
        updated: 0,
        effectiveVersionIds: entities.map((e) => e.id).toList(),
      ));
    });

    when(() => promptBuilder.buildPrompt(
          units: any(named: 'units'),
          context: any(named: 'context'),
          includeExamples: any(named: 'includeExamples'),
          maxExamples: any(named: 'maxExamples'),
        )).thenAnswer((_) async => Ok(BuiltPrompt(
          systemMessage: 'You are a translator',
          userMessage: 'Translate',
          unitCount: 1,
          metadata: PromptMetadata(
            includesExamples: false,
            exampleCount: 0,
            includesGlossary: false,
            glossaryTermCount: 0,
            includesGameContext: false,
            includesProjectContext: false,
            createdAt: DateTime.now(),
          ),
        )));

    when(() => llmService.translateBatch(
          any(),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer(
      (_) async => Ok(_fakeLlmResponse({'unit-hello': 'Bonjour le monde'})),
    );
    when(() => llmService.estimateTokens(any()))
        .thenAnswer((_) async => Ok(1234));
    when(() => llmService.getActiveProviderCode())
        .thenAnswer((_) async => 'anthropic');

    when(() => validation.validateTranslation(
          sourceText: any(named: 'sourceText'),
          translatedText: any(named: 'translatedText'),
          key: any(named: 'key'),
          glossaryTerms: any(named: 'glossaryTerms'),
          maxLength: any(named: 'maxLength'),
        )).thenAnswer((_) async => Ok(const common.ValidationResult(
          isValid: true,
        )));

    when(() => historyService.recordChange(
          versionId: any(named: 'versionId'),
          translatedText: any(named: 'translatedText'),
          status: any(named: 'status'),
          changedBy: any(named: 'changedBy'),
          changeReason: any(named: 'changeReason'),
        )).thenAnswer((_) async => Ok(null));
    when(() => historyService.recordChangesBatch(any()))
        .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

    when(() => transactionManager.executeTransaction<bool>(any()))
        .thenAnswer((inv) async {
      final action =
          inv.positionalArguments[0] as Future<bool> Function(Transaction);
      final value = await action(_FakeTransaction());
      return Ok(value);
    });

    when(() => eventBus.publish(any())).thenAnswer((_) async {});

    service = TranslationOrchestratorImpl(
      llmService: llmService,
      tmService: tmService,
      promptBuilder: promptBuilder,
      validation: validation,
      historyService: historyService,
      versionRepository: versionRepository,
      unitRepository: unitRepository,
      batchRepository: batchRepository,
      batchUnitRepository: batchUnitRepository,
      transactionManager: transactionManager,
      eventBus: eventBus,
      logger: logger,
    );
  });

  // --- Internal-flow error / cancellation branches ---------------------

  group('translateBatch — error & cancellation branches', () {
    test('loadBatchUnits Err surfaces on the stream and bypasses the LLM',
        () async {
      // findByBatchId fails -> loadBatchUnits returns Err -> orchestrator
      // emits that Err and cleans up (lines 199-203).
      when(() => batchUnitRepository.findByBatchId(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('boom loading batch units')),
      );

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isErr, isTrue,
          reason: 'loadBatchUnits Err must surface as a stream Err');
      expect(terminal.unwrapErr(), isA<TranslationOrchestrationException>());
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });

    test(
        'cancellation: pre-cancelled batch emits cancelled progress and '
        'publishes BatchCancelledEvent', () async {
      // Mark the batch cancelled BEFORE the workflow reaches its first
      // checkPauseOrCancel (line 300). That throws CancelledException, routing
      // into _handleCancellationInternal (lines 510-557).
      await service.cancelTranslation(batchId: _batchId);

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      // Terminal emission is the cancelled progress (Ok), not an Err.
      final cancelledEvents = events
          .where((e) =>
              e.isOk && e.unwrap().status == TranslationProgressStatus.cancelled)
          .toList();
      expect(cancelledEvents, isNotEmpty,
          reason: 'Expected a cancelled progress emission, got: $events');

      // A BatchCancelledEvent was published by _handleCancellationInternal.
      final published = verify(() => eventBus.publish(captureAny())).captured;
      expect(published.whereType<BatchCancelledEvent>(), isNotEmpty,
          reason: 'Expected BatchCancelledEvent from the cancellation handler');
      // The LLM must never have run.
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });

    test(
        'error path: non-cancel throwable increments retry count and publishes '
        'BatchFailedEvent', () async {
      // The orchestrator loads the batch (retryCount=2) for events; then the
      // LLM throws a *non*-Result error so it bubbles to _handleErrorInternal
      // (lines 561-624), which updates the batch retry count and publishes
      // BatchFailedEvent.
      when(() => batchRepository.getById(any()))
          .thenAnswer((_) async => Ok(_fakeBatch(_batchId, unitsCount: 2, retry: 2)));
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenThrow(StateError('hard failure inside LLM'));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isOk, isTrue,
          reason: 'Error handler emits a failed *progress* (Ok), got: $terminal');
      expect(terminal.unwrap().status, TranslationProgressStatus.failed);
      expect(terminal.unwrap().errorMessage, isNotNull);

      // Retry count bumped in the DB (2 -> 3).
      final captured =
          verify(() => batchRepository.update(captureAny())).captured;
      final updated = captured.whereType<TranslationBatch>().toList();
      expect(updated, isNotEmpty);
      expect(updated.last.retryCount, 3);
      expect(updated.last.status, TranslationBatchStatus.failed);

      // BatchFailedEvent carries the pre-increment retryCount (2).
      final published = verify(() => eventBus.publish(captureAny())).captured;
      final failedEvents = published.whereType<BatchFailedEvent>().toList();
      expect(failedEvents, isNotEmpty);
      expect(failedEvents.last.retryCount, 2);
    });

    test(
        'error path: retry-count DB update failure is swallowed with a warning',
        () async {
      // batch.update throws -> the inner try/catch logs a warning (lines
      // 610-612) but the failed-event path still completes.
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenThrow(StateError('hard failure inside LLM'));
      when(() => batchRepository.update(any()))
          .thenThrow(StateError('cannot persist retry count'));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      expect(events.last.unwrap().status, TranslationProgressStatus.failed);
      expect(
        logger.warnings.any((m) => m.contains('retry count')),
        isTrue,
        reason: 'Expected a warning about the failed retry-count update, got: '
            '${logger.warnings}',
      );
    });
  });

  // --- Delegating public methods ---------------------------------------

  group('estimateBatch', () {
    test('loadBatchUnits Err short-circuits estimateBatch with Err', () async {
      when(() => batchUnitRepository.findByBatchId(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('cannot load units')),
      );

      final result =
          await service.estimateBatch(batchId: _batchId, context: _fakeContext());

      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<TranslationOrchestrationException>());
    });

    test('happy path returns an estimate with provider/model resolved',
        () async {
      final result =
          await service.estimateBatch(batchId: _batchId, context: _fakeContext());

      expect(result.isOk, isTrue,
          reason: 'Expected an Ok estimate, got: $result');
      final estimate = result.unwrap();
      expect(estimate.batchId, _batchId);
      expect(estimate.totalEstimatedTokens, 1234);
      expect(estimate.totalUnits, greaterThanOrEqualTo(1));
    });
  });

  group('validateBatch (public)', () {
    test('empty batchId yields a validation error list', () async {
      final errors =
          await service.validateBatch(batchId: '', context: _fakeContext());
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.message.contains('Batch ID')), isTrue);
    });

    test('valid batchId with existing batch yields no errors', () async {
      final errors =
          await service.validateBatch(batchId: _batchId, context: _fakeContext());
      expect(errors, isEmpty);
    });
  });

  group('lifecycle controls delegate to the progress manager', () {
    test('pause on an inactive batch returns Err(InvalidStateException)',
        () async {
      final result = await service.pauseTranslation(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<InvalidStateException>());
    });

    test('resume on a non-paused batch returns Err(InvalidStateException)',
        () async {
      final result = await service.resumeTranslation(batchId: _batchId);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr(), isA<InvalidStateException>());
    });

    test('cancel returns Ok and publishes a BatchCancelledEvent', () async {
      final result = await service.cancelTranslation(batchId: _batchId);
      expect(result.isOk, isTrue);
      final published = verify(() => eventBus.publish(captureAny())).captured;
      expect(published.whereType<BatchCancelledEvent>(), isNotEmpty);
    });

    test('stop returns Ok and publishes a BatchCancelledEvent', () async {
      final result = await service.stopTranslation(batchId: _batchId);
      expect(result.isOk, isTrue);
      final published = verify(() => eventBus.publish(captureAny())).captured;
      expect(published.whereType<BatchCancelledEvent>(), isNotEmpty);
    });

    test('getBatchStatus on unknown batch returns Ok(null)', () async {
      final result = await service.getBatchStatus(batchId: 'unknown');
      expect(result.isOk, isTrue);
      expect(result.unwrap(), isNull);
    });

    test('isBatchActive is false for an unknown batch', () async {
      expect(await service.isBatchActive(batchId: 'unknown'), isFalse);
    });

    test('getActiveBatches is empty when nothing is running', () async {
      expect(await service.getActiveBatches(), isEmpty);
    });
  });

  group('getBatchStatistics', () {
    test('returns empty statistics when the DB query throws', () async {
      // _batchRepository.database is unstubbed -> rawQuery throws -> handler
      // returns the empty-stats fallback (catch branch).
      final stats = await service.getBatchStatistics();
      expect(stats.totalBatches, 0);
      expect(stats.totalUnitsProcessed, 0);
    });
  });

  group('activity logger integration', () {
    test(
        'resolves ActivityLogger from the service locator and logs on completion',
        () async {
      // Register a mock ActivityLogger so the orchestrator's static
      // _tryResolveActivityLogger() returns it (line 128) instead of null,
      // and the fire-and-forget _activityLogger?.log(...) call runs.
      if (GetIt.I.isRegistered<ActivityLogger>()) {
        await GetIt.I.unregister<ActivityLogger>();
      }
      final activityLogger = _MockActivityLogger();
      when(() => activityLogger.log(
            ActivityEventType.translationBatchCompleted,
            projectId: any(named: 'projectId'),
            gameCode: any(named: 'gameCode'),
            payload: any(named: 'payload'),
          )).thenAnswer((_) async {});
      GetIt.I.registerSingleton<ActivityLogger>(activityLogger);
      addTearDown(() async {
        if (GetIt.I.isRegistered<ActivityLogger>()) {
          await GetIt.I.unregister<ActivityLogger>();
        }
      });

      // Build a fresh orchestrator (no explicit activityLogger) so the ctor
      // resolves the one we just registered.
      final localService = TranslationOrchestratorImpl(
        llmService: llmService,
        tmService: tmService,
        promptBuilder: promptBuilder,
        validation: validation,
        historyService: historyService,
        versionRepository: versionRepository,
        unitRepository: unitRepository,
        batchRepository: batchRepository,
        batchUnitRepository: batchUnitRepository,
        transactionManager: transactionManager,
        eventBus: eventBus,
        logger: logger,
      );

      final events = await localService
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      expect(events.last.unwrap().status, TranslationProgressStatus.completed);
      verify(() => activityLogger.log(
            ActivityEventType.translationBatchCompleted,
            projectId: _projectId,
            gameCode: null,
            payload: any(named: 'payload'),
          )).called(1);
    });
  });

  group('translateBatchesParallel', () {
    test('forwards progress events for each batch through one stream',
        () async {
      // Two batch IDs, each resolving to one translatable unit. The parallel
      // handler fans out and merges their progress streams.
      final events = await service
          .translateBatchesParallel(
            batchIds: ['batch-a', 'batch-b'],
            context: _fakeContext(),
            maxParallel: 2,
          )
          .toList();

      expect(events, isNotEmpty,
          reason: 'Parallel handler must forward progress events');
      // At least one completed progress should appear across the merged stream.
      expect(
        events.any((e) =>
            e.isOk && e.unwrap().status == TranslationProgressStatus.completed),
        isTrue,
        reason: 'Expected a completed progress from the parallel run',
      );
    });
  });
}
