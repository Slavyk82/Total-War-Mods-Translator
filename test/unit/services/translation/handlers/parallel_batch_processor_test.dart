import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_cancellation_token.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/translation/handlers/llm_cache_manager.dart';
import 'package:twmt/services/translation/handlers/llm_retry_handler.dart';
import 'package:twmt/services/translation/handlers/llm_token_estimator.dart';
import 'package:twmt/services/translation/handlers/parallel_batch_processor.dart';
import 'package:twmt/services/translation/handlers/translation_error_recovery.dart';
import 'package:twmt/services/translation/handlers/translation_splitter.dart'
    hide ProgressUpdateCallback, SubBatchTranslatedCallback;
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

import '../../../../helpers/mock_logging_service.dart';

// Tests for the auto-split aggregation chain consumed by
// ParallelBatchProcessor._aggregateResults.
//
// Convention under test: every translateWithAutoSplit call returns progress
// whose tokensUsed/failedUnits/llmLogs equal the `currentProgress` baseline
// plus that call's OWN contribution. When a chunk auto-splits, BOTH halves'
// contributions must survive in the returned progress, otherwise the
// parallel aggregate (which diffs each chunk's returned progress against the
// shared pre-LLM baseline) undercounts tokens, failed units and logs.

class _MockLlmRetryHandler extends Mock implements LlmRetryHandler {}

class _FakeBuiltPrompt {
  final String systemMessage = 'Translate the given units.';
}

TranslationUnit _unit(String id, String sourceText) {
  return TranslationUnit(
    id: id,
    projectId: 'project-1',
    key: 'key.$id',
    sourceText: sourceText,
    createdAt: 0,
    updatedAt: 0,
  );
}

LlmRequest _buildRequest(Map<String, String> texts) {
  return LlmRequest(
    requestId: 'req-parallel-1',
    targetLanguage: 'fr',
    texts: texts,
    systemPrompt: 'Translate.',
    modelName: 'gpt-4o-mini',
    timestamp: DateTime(2026, 6, 10, 12, 0, 0),
  );
}

TranslationContext _buildContext({int parallelBatches = 1}) {
  return TranslationContext(
    id: 'ctx-1',
    projectId: 'project-1',
    projectLanguageId: 'pl-1',
    providerId: 'provider_openai',
    modelId: 'gpt-4o-mini',
    targetLanguage: 'fr',
    parallelBatches: parallelBatches,
    createdAt: DateTime(2026, 6, 10),
    updatedAt: DateTime(2026, 6, 10),
  );
}

TranslationProgress _buildProgress({
  int totalUnits = 4,
  int tokensUsed = 0,
  int failedUnits = 0,
  List<LlmExchangeLog> llmLogs = const [],
}) {
  return TranslationProgress(
    batchId: 'batch-1',
    status: TranslationProgressStatus.inProgress,
    totalUnits: totalUnits,
    processedUnits: 0,
    successfulUnits: 0,
    failedUnits: failedUnits,
    skippedUnits: 0,
    currentPhase: TranslationPhase.llmTranslation,
    tokensUsed: tokensUsed,
    tmReuseRate: 0.0,
    timestamp: DateTime(2026, 6, 10, 12, 0, 0),
  ).copyWith(llmLogs: llmLogs);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_buildRequest(const {'u1': 'Hello'}));
  });

  group('ParallelBatchProcessor with an auto-splitting chunk', () {
    test(
        'reports the SUM of both halves\' tokens, failed units and logs '
        'when a chunk splits on a token-limit error', () async {
      final tokenEstimator = LlmTokenEstimator();
      final retryHandler = _MockLlmRetryHandler();
      final logger = MockLoggingService();
      final processor = ParallelBatchProcessor(
        tokenEstimator: tokenEstimator,
        cacheManager: LlmCacheManager(logger: logger),
        translationSplitter: TranslationSplitter(
          tokenEstimator: tokenEstimator,
          retryHandler: retryHandler,
          logger: logger,
        ),
        logger: logger,
      );

      final units = [
        _unit('u1', 'Source one'),
        _unit('u2', 'Source two'),
        _unit('u3', 'Source three'),
        _unit('u4', 'Source four'),
      ];

      // The full 4-unit chunk fails with a token-limit error (the production
      // auto-split trigger); each 2-unit half then succeeds. Each half
      // returns a translation for only its FIRST unit, so each half also
      // contributes exactly one failed (missing) unit.
      when(() => retryHandler.translateWithRetry(
            llmRequest: any(named: 'llmRequest'),
            batchId: any(named: 'batchId'),
            dioCancelToken: any(named: 'dioCancelToken'),
          )).thenAnswer((invocation) async {
        final request =
            invocation.namedArguments[const Symbol('llmRequest')] as LlmRequest;
        if (request.texts.length > 2) {
          return Err<LlmResponse, LlmServiceException>(
            const LlmTokenLimitException(
              'Estimated tokens exceed the model limit',
              providerCode: 'openai',
            ),
          );
        }
        final isFirstHalf = request.texts.containsKey('u1');
        final firstKey = request.texts.keys.first;
        return Ok<LlmResponse, LlmServiceException>(LlmResponse(
          requestId: request.requestId,
          translations: {firstKey: 'T:$firstKey'},
          providerCode: 'openai',
          modelName: 'gpt-4o-mini',
          inputTokens: isFirstHalf ? 100 : 30,
          outputTokens: isFirstHalf ? 50 : 20,
          totalTokens: isFirstHalf ? 150 : 50,
          processingTimeMs: 10,
          timestamp: DateTime(2026, 6, 10, 12, 0, 1),
        ));
      });

      final baseline = _buildProgress();
      final cacheResult = CacheProcessingResult(
        cachedTranslations: <String, String>{},
        uncachedSourceTexts: units.map((u) => u.sourceText).toList(),
        registeredHashes: <String, String>{},
        sourceTextToUnits: {
          for (final u in units) u.sourceText: [u],
        },
        cachedUnitIds: <String>{},
        allTranslations: <String, String>{},
      );

      final (finalProgress, translations, _) =
          await processor.processParallelBatches(
        batchId: 'batch-1',
        unitsForLlm: units,
        unitsToTranslate: units,
        builtPrompt: _FakeBuiltPrompt(),
        context: _buildContext(),
        progress: baseline,
        currentProgress: baseline,
        cacheResult: cacheResult,
        getCancellationToken: (_) => null,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: (_) async {},
      );

      // Tokens: first half 100+50, second half 30+20. Dropping the first
      // half's contribution would report only 50.
      expect(finalProgress.tokensUsed, 200,
          reason: 'aggregate must include BOTH halves\' tokens');
      // Failed units: one missing translation per half.
      expect(finalProgress.failedUnits, 2,
          reason: 'aggregate must include BOTH halves\' failed units');
      // Translations from both halves survive.
      expect(translations, {'u1': 'T:u1', 'u3': 'T:u3'});

      // Both halves' success logs must be present in the merged logs.
      final successIds = finalProgress.llmLogs
          .where((log) => log.success)
          .map((log) => log.requestId)
          .toList();
      expect(successIds.where((id) => id.contains('part1')), hasLength(1),
          reason: 'first half\'s exchange log must not be dropped');
      expect(successIds.where((id) => id.contains('part2')), hasLength(1),
          reason: 'second half\'s exchange log must not be dropped');
    });
  });

  group('ParallelBatchProcessor partial-then-fail counting (D5)', () {
    test('counts only the NOT-yet-saved units as failed when a chunk saves '
        'its first half then fails on the second half', () async {
      final tokenEstimator = LlmTokenEstimator();
      final retryHandler = _MockLlmRetryHandler();
      final logger = MockLoggingService();
      final processor = ParallelBatchProcessor(
        tokenEstimator: tokenEstimator,
        cacheManager: LlmCacheManager(logger: logger),
        translationSplitter: TranslationSplitter(
          tokenEstimator: tokenEstimator,
          retryHandler: retryHandler,
          logger: logger,
        ),
        logger: logger,
      );

      final units = [
        _unit('u1', 'Source one'),
        _unit('u2', 'Source two'),
        _unit('u3', 'Source three'),
        _unit('u4', 'Source four'),
      ];

      // Full 4-unit chunk trips the token limit -> auto-split. The FIRST half
      // (u1,u2) succeeds and is persisted via onSubBatchTranslated. The SECOND
      // half (u3,u4) then dies with a fatal network error, so the whole chunk
      // takes the error path. Only u3,u4 are truly failed - u1,u2 are already
      // saved on disk and must NOT be counted as failures.
      when(() => retryHandler.translateWithRetry(
            llmRequest: any(named: 'llmRequest'),
            batchId: any(named: 'batchId'),
            dioCancelToken: any(named: 'dioCancelToken'),
          )).thenAnswer((invocation) async {
        final request =
            invocation.namedArguments[const Symbol('llmRequest')] as LlmRequest;
        if (request.texts.length > 2) {
          return Err<LlmResponse, LlmServiceException>(
            const LlmTokenLimitException(
              'Estimated tokens exceed the model limit',
              providerCode: 'openai',
            ),
          );
        }
        if (request.texts.containsKey('u1')) {
          // First half: both units translated successfully.
          return Ok<LlmResponse, LlmServiceException>(LlmResponse(
            requestId: request.requestId,
            translations: {'u1': 'T:u1', 'u2': 'T:u2'},
            providerCode: 'openai',
            modelName: 'gpt-4o-mini',
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            processingTimeMs: 10,
            timestamp: DateTime(2026, 6, 10, 12, 0, 1),
          ));
        }
        // Second half: fatal, non-recoverable error.
        return Err<LlmResponse, LlmServiceException>(
          const LlmNetworkException('Connection reset', providerCode: 'openai'),
        );
      });

      final savedIds = <String>{};
      Future<void> saveCallback(
        List<TranslationUnit> u,
        Map<String, String> t,
        Set<String> c,
      ) async {
        savedIds.addAll(t.keys);
      }

      final baseline = _buildProgress();
      final cacheResult = CacheProcessingResult(
        cachedTranslations: <String, String>{},
        uncachedSourceTexts: units.map((u) => u.sourceText).toList(),
        registeredHashes: <String, String>{},
        sourceTextToUnits: {
          for (final u in units) u.sourceText: [u],
        },
        cachedUnitIds: <String>{},
        allTranslations: <String, String>{},
      );

      final (finalProgress, _, _) = await processor.processParallelBatches(
        batchId: 'batch-1',
        unitsForLlm: units,
        unitsToTranslate: units,
        builtPrompt: _FakeBuiltPrompt(),
        context: _buildContext(),
        progress: baseline,
        currentProgress: baseline,
        cacheResult: cacheResult,
        getCancellationToken: (_) => null,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: (_) async {},
        onSubBatchTranslated: saveCallback,
      );

      // The first half really was saved.
      expect(savedIds, containsAll(<String>['u1', 'u2']));
      // Only the 2 unsaved units count as failed - NOT the whole 4-unit chunk.
      expect(finalProgress.failedUnits, 2,
          reason: 'already-saved units must not be double-counted as failed');
    });
  });

  group('ParallelBatchProcessor cancellation-token wiring', () {
    test(
        'every parallel chunk forwards the ROOT batch Dio cancel token so '
        'Stop aborts in-flight requests immediately', () async {
      final tokenEstimator = LlmTokenEstimator();
      final retryHandler = _MockLlmRetryHandler();
      final logger = MockLoggingService();
      final processor = ParallelBatchProcessor(
        tokenEstimator: tokenEstimator,
        cacheManager: LlmCacheManager(logger: logger),
        translationSplitter: TranslationSplitter(
          tokenEstimator: tokenEstimator,
          retryHandler: retryHandler,
          logger: logger,
        ),
        logger: logger,
      );

      final units = [
        _unit('u1', 'Source one'),
        _unit('u2', 'Source two'),
        _unit('u3', 'Source three'),
        _unit('u4', 'Source four'),
      ];

      // Production reality: the cancellation token is registered ONLY under the
      // root batch id (BatchProgressManager.getOrCreateCancellationToken is
      // called once for the root batch in the orchestrator). Chunk ids like
      // 'batch-1-parallel-0' have no token of their own.
      final rootToken = LlmCancellationToken();
      final capturedTokens = <Object?>[];

      when(() => retryHandler.translateWithRetry(
            llmRequest: any(named: 'llmRequest'),
            batchId: any(named: 'batchId'),
            dioCancelToken: any(named: 'dioCancelToken'),
          )).thenAnswer((invocation) async {
        capturedTokens
            .add(invocation.namedArguments[const Symbol('dioCancelToken')]);
        final request = invocation.namedArguments[const Symbol('llmRequest')]
            as LlmRequest;
        return Ok<LlmResponse, LlmServiceException>(LlmResponse(
          requestId: request.requestId,
          translations: {for (final k in request.texts.keys) k: 'T:$k'},
          providerCode: 'openai',
          modelName: 'gpt-4o-mini',
          inputTokens: 10,
          outputTokens: 10,
          totalTokens: 20,
          processingTimeMs: 10,
          timestamp: DateTime(2026, 6, 10, 12, 0, 1),
        ));
      });

      final baseline = _buildProgress();
      final cacheResult = CacheProcessingResult(
        cachedTranslations: <String, String>{},
        uncachedSourceTexts: units.map((u) => u.sourceText).toList(),
        registeredHashes: <String, String>{},
        sourceTextToUnits: {
          for (final u in units) u.sourceText: [u],
        },
        cachedUnitIds: <String>{},
        allTranslations: <String, String>{},
      );

      await processor.processParallelBatches(
        batchId: 'batch-1',
        unitsForLlm: units,
        unitsToTranslate: units,
        builtPrompt: _FakeBuiltPrompt(),
        context: _buildContext(parallelBatches: 2),
        progress: baseline,
        currentProgress: baseline,
        cacheResult: cacheResult,
        // Token exists only for the root id, exactly like production.
        getCancellationToken: (id) => id == 'batch-1' ? rootToken : null,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: (_) async {},
      );

      expect(capturedTokens, isNotEmpty,
          reason: 'each chunk must issue an LLM call');
      expect(
        capturedTokens,
        everyElement(same(rootToken.dioToken)),
        reason: 'a null token here means the in-flight request cannot be '
            'aborted until it completes naturally — the reported cancel lag',
      );
    });
  });

  group('ParallelBatchProcessor with a fatally-failing chunk', () {
    test(
        'counts a fatally-failed chunk\'s units as failed so the batch is not '
        'silently reported complete with zero failures', () async {
      final tokenEstimator = LlmTokenEstimator();
      final retryHandler = _MockLlmRetryHandler();
      final logger = MockLoggingService();
      final processor = ParallelBatchProcessor(
        tokenEstimator: tokenEstimator,
        cacheManager: LlmCacheManager(logger: logger),
        translationSplitter: TranslationSplitter(
          tokenEstimator: tokenEstimator,
          retryHandler: retryHandler,
          logger: logger,
        ),
        logger: logger,
      );

      final units = [
        _unit('u1', 'Source one'),
        _unit('u2', 'Source two'),
        _unit('u3', 'Source three'),
        _unit('u4', 'Source four'),
      ];

      // Two parallel chunks of two units each. The chunk holding u1/u2 hits a
      // non-retryable, non-splittable provider error (fatal): the splitter's
      // error recovery throws TranslationOrchestrationException. The chunk
      // holding u3/u4 succeeds. The failed chunk's two units MUST be counted
      // as failed; otherwise the orchestrator marks the whole batch
      // 'completed' with 0 failures and the user ships an incomplete
      // translation believing it finished.
      when(() => retryHandler.translateWithRetry(
            llmRequest: any(named: 'llmRequest'),
            batchId: any(named: 'batchId'),
            dioCancelToken: any(named: 'dioCancelToken'),
          )).thenAnswer((invocation) async {
        final request =
            invocation.namedArguments[const Symbol('llmRequest')] as LlmRequest;
        if (request.texts.containsKey('u1')) {
          return Err<LlmResponse, LlmServiceException>(
            const LlmInvalidRequestException(
              'Model rejected the request',
              providerCode: 'openai',
            ),
          );
        }
        return Ok<LlmResponse, LlmServiceException>(LlmResponse(
          requestId: request.requestId,
          translations: {for (final k in request.texts.keys) k: 'T:$k'},
          providerCode: 'openai',
          modelName: 'gpt-4o-mini',
          inputTokens: 10,
          outputTokens: 10,
          totalTokens: 20,
          processingTimeMs: 10,
          timestamp: DateTime(2026, 6, 10, 12, 0, 1),
        ));
      });

      final baseline = _buildProgress();
      final cacheResult = CacheProcessingResult(
        cachedTranslations: <String, String>{},
        uncachedSourceTexts: units.map((u) => u.sourceText).toList(),
        registeredHashes: <String, String>{},
        sourceTextToUnits: {
          for (final u in units) u.sourceText: [u],
        },
        cachedUnitIds: <String>{},
        allTranslations: <String, String>{},
      );

      final (finalProgress, translations, _) =
          await processor.processParallelBatches(
        batchId: 'batch-1',
        unitsForLlm: units,
        unitsToTranslate: units,
        builtPrompt: _FakeBuiltPrompt(),
        context: _buildContext(parallelBatches: 2),
        progress: baseline,
        currentProgress: baseline,
        cacheResult: cacheResult,
        getCancellationToken: (_) => null,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: (_) async {},
      );

      // The two units in the fatally-failed chunk must be counted as failed.
      expect(finalProgress.failedUnits, 2,
          reason: 'a fatally-failed parallel chunk must contribute its unit '
              'count to failedUnits, not be silently dropped');
      // The surviving chunk's translations are still returned (partial success).
      expect(translations, {'u3': 'T:u3', 'u4': 'T:u4'});
    });
  });

  group('TranslationErrorRecovery split contract (via handleLlmError)', () {
    test(
        'returned progress chains BOTH halves\' contributions on top of a '
        'non-zero shared baseline', () async {
      final recovery = TranslationErrorRecovery(
        tokenEstimator: LlmTokenEstimator(),
        logger: MockLoggingService(),
      );

      final baselineLog = LlmExchangeLog.fromResponse(
        requestId: 'baseline-1',
        providerCode: 'openai',
        modelName: 'gpt-4o-mini',
        unitsCount: 5,
        inputTokens: 700,
        outputTokens: 300,
        processingTimeMs: 5,
      );
      final baseline = _buildProgress(
        totalUnits: 2,
        tokensUsed: 1000,
        failedUnits: 2,
        llmLogs: [baselineLog],
      );

      final units = [_unit('u1', 'Hello'), _unit('u2', 'World')];

      // Fake recursive callback mirroring the production contract
      // (_processSuccessfulResponse): the returned progress equals the
      // *passed* currentProgress baseline plus this call's own contribution.
      // First half (u1): 150 tokens, 1 failure, no translation.
      // Second half (u2): 50 tokens, 0 failures, one translation.
      Future<(TranslationProgress, Map<String, String>)> fakeTranslate({
        required String batchId,
        required String rootBatchId,
        required List<TranslationUnit> unitsToTranslate,
        required LlmRequest llmRequest,
        required TranslationContext context,
        required TranslationProgress progress,
        required TranslationProgress currentProgress,
        required Function(String batchId) getCancellationToken,
        required ProgressUpdateCallback onProgressUpdate,
        required Future<void> Function(String batchId) checkPauseOrCancel,
        SubBatchTranslatedCallback? onSubBatchTranslated,
        int depth = 0,
      }) async {
        final isFirstHalf = unitsToTranslate.single.id == 'u1';
        final log = LlmExchangeLog.fromResponse(
          requestId: llmRequest.requestId,
          providerCode: 'openai',
          modelName: 'gpt-4o-mini',
          unitsCount: 1,
          inputTokens: isFirstHalf ? 100 : 30,
          outputTokens: isFirstHalf ? 50 : 20,
          processingTimeMs: 10,
        );
        final updated = progress.copyWith(
          tokensUsed: currentProgress.tokensUsed + (isFirstHalf ? 150 : 50),
          failedUnits: currentProgress.failedUnits + (isFirstHalf ? 1 : 0),
          llmLogs: [...currentProgress.llmLogs, log],
          timestamp: DateTime(2026, 6, 10, 12, 0, 2),
        );
        return (
          updated,
          isFirstHalf ? <String, String>{} : {'u2': 'T:u2'},
        );
      }

      final (resultProgress, translations) = await recovery.handleLlmError(
        error: const LlmTokenLimitException(
          'Estimated tokens exceed the model limit',
          providerCode: 'openai',
        ),
        batchId: 'chunk-0',
        rootBatchId: 'batch-1',
        unitsToTranslate: units,
        llmRequest:
            _buildRequest(const {'u1': 'Hello', 'u2': 'World'}),
        context: _buildContext(),
        progress: baseline,
        currentProgress: baseline,
        getCancellationToken: (_) => null,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: (_) async {},
        depth: 0,
        translateWithAutoSplit: fakeTranslate,
      );

      // baseline 1000 + first half 150 + second half 50.
      expect(resultProgress.tokensUsed, 1200,
          reason: 'first half\'s tokens must not be lost when the second '
              'half rebases onto the shared baseline');
      // baseline 2 + first half 1 + second half 0.
      expect(resultProgress.failedUnits, 3,
          reason: 'first half\'s failed-unit delta must be preserved');
      expect(translations, {'u2': 'T:u2'});

      final requestIds =
          resultProgress.llmLogs.map((log) => log.requestId).toList();
      expect(requestIds, contains('baseline-1'));
      expect(requestIds, contains('chunk-0-part1-depth0'),
          reason: 'first half\'s exchange log must be in the returned logs');
      expect(requestIds, contains('chunk-0-part2-depth0'));
    });
  });
}
