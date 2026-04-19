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
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/translation/batch_translation_cache.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
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

// Silent logger fake that captures warning messages so tests can assert on
// them. Extends the shared [FakeLogger] so it only needs to override the
// warning path.
class _FakeLogger extends FakeLogger {
  final List<String> warnings = [];

  @override
  void warning(String message, [dynamic data]) {
    warnings.add(message);
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

// --- Fixture builders --------------------------------------------------

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

TranslationBatch _fakeBatch(String id, {int unitsCount = 0}) {
  return TranslationBatch(
    id: id,
    projectLanguageId: _projectLanguageId,
    providerId: 'provider_anthropic',
    batchNumber: 1,
    unitsCount: unitsCount,
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

TranslationContext _fakeContext({bool skipTm = false}) {
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
    createdAt: now,
    updatedAt: now,
  );
}

TmMatch _fakeExactMatch({
  required String sourceText,
  required String targetText,
}) {
  return TmMatch(
    entryId: 'entry-${sourceText.hashCode}',
    sourceText: sourceText,
    targetText: targetText,
    targetLanguageCode: 'fr',
    similarityScore: 1.0,
    matchType: TmMatchType.exact,
    breakdown: const SimilarityBreakdown(
      levenshteinScore: 1.0,
      jaroWinklerScore: 1.0,
      tokenScore: 1.0,
      contextBoost: 0.0,
      weights: ScoreWeights.defaultWeights,
    ),
    usageCount: 1,
    lastUsedAt: DateTime.now(),
  );
}

TmMatch _fakeFuzzyMatch({
  required String sourceText,
  required String targetText,
  required double similarity,
}) {
  return TmMatch(
    entryId: 'entry-fuzzy-${sourceText.hashCode}',
    sourceText: sourceText,
    targetText: targetText,
    targetLanguageCode: 'fr',
    similarityScore: similarity,
    matchType: TmMatchType.fuzzy,
    breakdown: SimilarityBreakdown(
      levenshteinScore: similarity,
      jaroWinklerScore: similarity,
      tokenScore: similarity,
      contextBoost: 0.0,
      weights: ScoreWeights.defaultWeights,
    ),
    usageCount: 1,
    lastUsedAt: DateTime.now(),
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

// --- Test setup --------------------------------------------------------

void main() {
  setUpAll(() {
    // Register fallback values for mocktail's any() matcher.
    registerFallbackValue(_FakeTranslationContext());
    registerFallbackValue(_FakeTranslationUnit());
    registerFallbackValue(_FakeTransaction());
    registerFallbackValue(_FakeTranslationVersion());
    registerFallbackValue(_FakeLlmRequest());
    registerFallbackValue(_FakeTranslationBatch());
    registerFallbackValue(_FakeDomainEvent());
    registerFallbackValue(<TranslationUnit>[]);
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
    // Clear the shared translation cache between tests. This singleton is
    // populated by the real LlmCacheManager inside LlmTranslationHandler.
    BatchTranslationCache.instance.clear();

    // BatchEstimationHandler constructor falls back to
    // ServiceLocator.get<TranslationProviderRepository>(); register a mock
    // so that fallback succeeds in tests that do not exercise estimation.
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

    // --- Neutral defaults: tests override only what they care about. ---

    // Batch validation lookups.
    when(() => batchRepository.getById(any()))
        .thenAnswer((_) async => Ok(_fakeBatch(_batchId, unitsCount: 2)));
    when(() => batchRepository.update(any())).thenAnswer(
      (inv) async => Ok(inv.positionalArguments[0] as TranslationBatch),
    );

    // Default batch/unit loading: single translatable unit.
    when(() => batchUnitRepository.findByBatchId(any()))
        .thenAnswer((_) async => Ok([_fakeBatchUnit('hello', 0)]));
    when(() => unitRepository.getByIds(any())).thenAnswer(
      (_) async => Ok([_fakeUnit('hello', 'Hello world')]),
    );

    // TM defaults: no matches anywhere, forces LLM fallback.
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

    // Version repository defaults.
    when(() => versionRepository.getTranslatedUnitIds(
          unitIds: any(named: 'unitIds'),
          projectLanguageId: any(named: 'projectLanguageId'),
        )).thenAnswer((_) async => Ok(<String>{}));
    when(() => versionRepository.upsert(any())).thenAnswer(
      (inv) async => Ok(inv.positionalArguments[0] as TranslationVersion),
    );
    when(() => versionRepository.upsertWithTransaction(any(), any()))
        .thenAnswer((_) async {});

    // Prompt builder default: minimal prompt.
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

    // LLM default: succeed with a translation for "unit-hello".
    when(() => llmService.translateBatch(
          any(),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer(
      (_) async =>
          Ok(_fakeLlmResponse({'unit-hello': 'Bonjour le monde'})),
    );

    // Validation default: clean pass.
    when(() => validation.validateTranslation(
          sourceText: any(named: 'sourceText'),
          translatedText: any(named: 'translatedText'),
          key: any(named: 'key'),
          glossaryTerms: any(named: 'glossaryTerms'),
          maxLength: any(named: 'maxLength'),
        )).thenAnswer((_) async => Ok(const common.ValidationResult(
          isValid: true,
        )));

    // History: always succeed (return type uses TWMTDatabaseException).
    when(() => historyService.recordChange(
          versionId: any(named: 'versionId'),
          translatedText: any(named: 'translatedText'),
          status: any(named: 'status'),
          changedBy: any(named: 'changedBy'),
          changeReason: any(named: 'changeReason'),
        )).thenAnswer((_) async => Ok(null));

    // TransactionManager: invoke the callback with a fake Transaction so the
    // write path inside the closure actually runs. Without this the fuzzy
    // auto-accept / persistence assertions below would pass even if the
    // orchestrator never touched its collaborators.
    when(() => transactionManager.executeTransaction<bool>(any()))
        .thenAnswer((inv) async {
      final action =
          inv.positionalArguments[0] as Future<bool> Function(Transaction);
      final value = await action(_FakeTransaction());
      return Ok(value);
    });

    // EventBus.publish returns Future<void>; stub it so any() matches.
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

  group('translateBatch', () {
    test('happy path: TM miss → LLM translates → validated and persisted',
        () async {
      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      expect(events, isNotEmpty);
      final terminal = events.last;
      expect(terminal.isOk, isTrue,
          reason: 'Expected terminal Ok but got: $terminal');
      final finalProgress = terminal.unwrap();
      expect(finalProgress.status, TranslationProgressStatus.completed);
      expect(finalProgress.currentPhase, TranslationPhase.completed);
      expect(finalProgress.successfulUnits, 1);
      expect(finalProgress.failedUnits, 0);

      // LLM was called at least once (happy path invariant).
      verify(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).called(greaterThanOrEqualTo(1));
      // Validation + persistence were exercised.
      verify(() => validation.validateTranslation(
            sourceText: any(named: 'sourceText'),
            translatedText: any(named: 'translatedText'),
            key: any(named: 'key'),
            glossaryTerms: any(named: 'glossaryTerms'),
            maxLength: any(named: 'maxLength'),
          )).called(1);
      verify(() => versionRepository.upsert(any())).called(1);
    });

    test('skip-filter path: bracketed placeholder bypasses LLM entirely',
        () async {
      // Two units: one normal, one fully-bracketed placeholder.
      when(() => batchUnitRepository.findByBatchId(any()))
          .thenAnswer((_) async => Ok([
                _fakeBatchUnit('hello', 0),
                _fakeBatchUnit('placeholder', 1),
              ]));
      when(() => unitRepository.getByIds(any())).thenAnswer((_) async => Ok([
            _fakeUnit('hello', 'Hello world'),
            _fakeUnit('placeholder', '[PLACEHOLDER]'),
          ]));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isOk, isTrue);
      expect(terminal.unwrap().status, TranslationProgressStatus.completed);

      // The LLM was invoked (for "hello"), but never saw the placeholder
      // source text — the skip filter strips it before the LLM step.
      final captured = verify(() => llmService.translateBatch(
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
          )).captured;
      for (final req in captured.cast<LlmRequest>()) {
        expect(req.texts.values, isNot(contains('[PLACEHOLDER]')),
            reason:
                'Skip-filter path must never send bracketed placeholders to the LLM');
      }
    });

    test('TM-hit path: exact TM match skips the LLM call', () async {
      // Single unit with a perfect TM match.
      when(() => batchUnitRepository.findByBatchId(any()))
          .thenAnswer((_) async => Ok([_fakeBatchUnit('hello', 0)]));
      when(() => unitRepository.getByIds(any())).thenAnswer(
        (_) async => Ok([_fakeUnit('hello', 'Hello world')]),
      );
      when(() => tmService.findExactMatch(
            sourceText: 'Hello world',
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => Ok(_fakeExactMatch(
            sourceText: 'Hello world',
            targetText: 'Bonjour le monde',
          )));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isOk, isTrue);
      expect(terminal.unwrap().status, TranslationProgressStatus.completed);

      // TM match means the LLM is never invoked for this batch.
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });

    test(
        'LLM-error path: LLM failure is wrapped and batch status becomes failed',
        () async {
      // Single unit, no TM match, LLM fails with a fatal auth error.
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Err(const LlmAuthenticationException(
            'Invalid key',
            providerCode: 'anthropic',
          )));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      // Orchestrator swallows fatal LLM errors into a progress update carrying
      // status=failed and a non-empty errorMessage (see _handleErrorInternal).
      // The stream's terminal event is therefore Ok(progress.failed), not Err.
      final terminal = events.last;
      expect(terminal.isOk, isTrue,
          reason: 'Expected terminal Ok(progress.failed) but got: $terminal');
      final finalProgress = terminal.unwrap();
      expect(finalProgress.status, TranslationProgressStatus.failed);
      expect(finalProgress.errorMessage, isNotNull);
      expect(finalProgress.errorMessage, contains('LLM translation failed'));
      // Validation and persistence never ran for a fatal LLM failure.
      verifyNever(() => versionRepository.upsert(any()));
    });

    test('empty batch → EmptyBatchException on the stream', () async {
      when(() => batchUnitRepository.findByBatchId(any()))
          .thenAnswer((_) async => Ok(const <TranslationBatchUnit>[]));
      when(() => unitRepository.getByIds(any()))
          .thenAnswer((_) async => Ok(const <TranslationUnit>[]));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isErr, isTrue);
      expect(terminal.unwrapErr(), isA<EmptyBatchException>());
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });

    test('all units filtered out → EmptyBatchException on the stream',
        () async {
      when(() => batchUnitRepository.findByBatchId(any()))
          .thenAnswer((_) async => Ok([
                _fakeBatchUnit('p1', 0),
                _fakeBatchUnit('p2', 1),
              ]));
      when(() => unitRepository.getByIds(any())).thenAnswer((_) async => Ok([
            _fakeUnit('p1', '[PLACEHOLDER_ONE]'),
            _fakeUnit('p2', '[PLACEHOLDER_TWO]'),
          ]));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isErr, isTrue);
      expect(terminal.unwrapErr(), isA<EmptyBatchException>());
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });

    // --- Deferred orchestrator branches (Phase 6 Task 6.5) -------------

    test(
        'skipTranslationMemory=true: TM lookup is skipped, LLM handles the unit',
        () async {
      // Context opts out of TM lookup entirely.
      final ctx = _fakeContext(skipTm: true);

      final events = await service
          .translateBatch(batchId: _batchId, context: ctx)
          .toList();

      final terminal = events.last;
      expect(terminal.isOk, isTrue,
          reason: 'Expected terminal Ok(progress.completed) but got: $terminal');
      final finalProgress = terminal.unwrap();
      expect(finalProgress.status, TranslationProgressStatus.completed);
      expect(finalProgress.successfulUnits, 1);

      // Neither exact nor fuzzy TM lookup ran because the context flag bypasses
      // the TmLookupHandler entirely (see orchestrator's skipTranslationMemory branch).
      verifyNever(() => tmService.findExactMatch(
            sourceText: any(named: 'sourceText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          ));
      verifyNever(() => tmService.findFuzzyMatchesIsolate(
            sourceText: any(named: 'sourceText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          ));
      // LLM *was* invoked for the unit that would otherwise have hit TM.
      verify(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).called(greaterThanOrEqualTo(1));
    });

    test('fuzzy TM match >=95% auto-accepts without invoking the LLM',
        () async {
      // Exact miss but fuzzy returns a 0.97 match -> auto-accept path.
      // Auto-accept threshold is actually 0.85 (docstring says 95%), so 0.97
      // comfortably exceeds it. We pin the observable behaviour at 0.97 so
      // any future threshold tightening above 0.97 will flag this test.
      when(() => tmService.findExactMatch(
            sourceText: 'Hello world',
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => Ok(null));
      when(() => tmService.findFuzzyMatchesIsolate(
            sourceText: 'Hello world',
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          )).thenAnswer((_) async => Ok([
            _fakeFuzzyMatch(
              sourceText: 'Hello world',
              targetText: 'Bonjour le monde (fuzzy)',
              similarity: 0.97,
            ),
          ]));

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isOk, isTrue,
          reason: 'Expected terminal Ok(progress.completed) but got: $terminal');
      expect(terminal.unwrap().status, TranslationProgressStatus.completed);

      // Fuzzy auto-accept ran (transaction executor was called to persist the match).
      verify(() => transactionManager.executeTransaction<bool>(any()))
          .called(greaterThanOrEqualTo(1));

      // LLM is never invoked because the fuzzy match covered the only unit.
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });

    test(
        'batch details load failure: workflow still completes, warning logged, batchNumber fallback 0',
        () async {
      // Sequence getById responses: the first call is the orchestrator's
      // "load batch details for events" (line ~149) — make it throw so the
      // outer catch logs a warning and leaves `batch` null. The second call
      // is BatchEstimationHandler.validateBatch looking up the batch; we
      // return Ok there so validation does not short-circuit the workflow.
      var getByIdCalls = 0;
      when(() => batchRepository.getById(any())).thenAnswer((_) async {
        getByIdCalls++;
        if (getByIdCalls == 1) {
          throw StateError('simulated DB failure');
        }
        return Ok(_fakeBatch(_batchId, unitsCount: 1));
      });

      final events = await service
          .translateBatch(batchId: _batchId, context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isOk, isTrue,
          reason: 'Null batch must not block the workflow, got: $terminal');
      expect(terminal.unwrap().status, TranslationProgressStatus.completed);
      expect(terminal.unwrap().successfulUnits, 1);

      // The "batch details for events" warning must have been recorded.
      expect(
        logger.warnings.any((m) => m.contains('batch details')),
        isTrue,
        reason: 'Expected a warning about failing to load batch details, got: '
            '${logger.warnings}',
      );

      // BatchStartedEvent was published with batchNumber=0 fallback because
      // the orchestrator could not load the real batch at event-emission time.
      final publishedEvents =
          verify(() => eventBus.publish(captureAny())).captured;
      final startedEvents =
          publishedEvents.whereType<BatchStartedEvent>().toList();
      expect(startedEvents, isNotEmpty,
          reason: 'Expected at least one BatchStartedEvent to be published');
      expect(startedEvents.first.batchNumber, 0,
          reason:
              'When batch load fails, event emission must fall back to batchNumber=0');
    });

    test(
        'pre-workflow validation failure: empty batchId yields Err(TranslationOrchestrationException)',
        () async {
      // BatchEstimationHandler.validateBatch appends a "Batch ID cannot be
      // empty" error for a blank batchId — this is the pre-workflow Err path.
      // Default getById stub returns Ok, so validation only fails on the
      // batchId-empty check, not on missing-in-DB.
      final events = await service
          .translateBatch(batchId: '', context: _fakeContext())
          .toList();

      final terminal = events.last;
      expect(terminal.isErr, isTrue,
          reason: 'Pre-workflow validation failure must surface as Err, '
              'got: $terminal');
      expect(terminal.unwrapErr(), isA<TranslationOrchestrationException>());
      expect(
        terminal.unwrapErr().toString(),
        contains('Batch validation failed'),
      );

      // Neither LLM nor persistence ran because we never reached the workflow.
      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
      verifyNever(() => versionRepository.upsert(any()));
    });
  });
}

