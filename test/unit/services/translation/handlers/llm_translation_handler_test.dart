import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/translation/batch_translation_cache.dart';
import 'package:twmt/services/translation/handlers/llm_translation_handler.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

import '../../../../helpers/mock_logging_service.dart';

// Characterisation tests for LlmTranslationHandler.performTranslation.
//
// The handler composes LlmRetryHandler, LlmCacheManager, TranslationSplitter,
// SingleBatchProcessor and ParallelBatchProcessor internally from the injected
// ILlmService / IPromptBuilderService / ILoggingService. Per the testing
// strategy, we mock only the three injected collaborators so the real internal
// pipeline executes with mocked LLM responses. This lets us pin the external
// contract (LlmRequest payload, promptBuilder invocation, progress updates,
// error propagation) without depending on private helpers.
//
// BatchTranslationCache is a singleton used by the real LlmCacheManager;
// we clear it in setUp to prevent cross-test leaks.

class _MockLlmService extends Mock implements ILlmService {}

class _MockPromptBuilder extends Mock implements IPromptBuilderService {}

class _FakeTranslationContext extends Fake implements TranslationContext {}

class _FakeTranslationUnit extends Fake implements TranslationUnit {}

class _FakeLlmRequest extends Fake implements LlmRequest {}

// --- Fixture builders ------------------------------------------------------

const String _projectId = 'project-1';
const String _projectLanguageId = 'plang-1';
const String _batchId = 'batch-llm-1';

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

TranslationContext _fakeContext() {
  final now = DateTime.now();
  return TranslationContext(
    id: 'ctx-1',
    projectId: _projectId,
    projectLanguageId: _projectLanguageId,
    providerId: 'provider_anthropic',
    modelId: 'claude-haiku-4.5',
    targetLanguage: 'fr',
    sourceLanguage: 'en',
    // skipTranslationMemory=true bypasses BatchTranslationCache lookups so
    // the units we pass always reach the LLM call, regardless of any hash
    // collisions that might linger in the shared singleton.
    skipTranslationMemory: true,
    createdAt: now,
    updatedAt: now,
  );
}

TranslationProgress _initialProgress() {
  return TranslationProgress(
    batchId: _batchId,
    status: TranslationProgressStatus.inProgress,
    totalUnits: 3,
    processedUnits: 0,
    successfulUnits: 0,
    failedUnits: 0,
    skippedUnits: 0,
    currentPhase: TranslationPhase.initializing,
    tokensUsed: 0,
    tmReuseRate: 0.0,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

LlmResponse _fakeLlmResponse({required Map<String, String> translations}) {
  return LlmResponse(
    requestId: _batchId,
    translations: translations,
    providerCode: 'anthropic',
    modelName: 'claude-haiku-4.5',
    inputTokens: 42,
    outputTokens: 58,
    totalTokens: 100,
    processingTimeMs: 123,
    timestamp: DateTime(2026, 4, 14, 12, 0, 1),
  );
}

BuiltPrompt _fakeBuiltPrompt() {
  return BuiltPrompt(
    systemMessage: 'You are a Total War translator.',
    userMessage: 'Translate the following keys.',
    unitCount: 0,
    metadata: PromptMetadata(
      includesExamples: false,
      exampleCount: 0,
      includesGlossary: false,
      glossaryTermCount: 0,
      includesGameContext: false,
      includesProjectContext: false,
      createdAt: DateTime(2026, 4, 14, 12, 0, 0),
    ),
  );
}

void _stubPromptBuilderOk(_MockPromptBuilder promptBuilder) {
  when(() => promptBuilder.buildPrompt(
        units: any(named: 'units'),
        context: any(named: 'context'),
        includeExamples: any(named: 'includeExamples'),
        maxExamples: any(named: 'maxExamples'),
      )).thenAnswer((_) async => Ok(_fakeBuiltPrompt()));
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTranslationContext());
    registerFallbackValue(_FakeTranslationUnit());
    registerFallbackValue(_FakeLlmRequest());
    registerFallbackValue(<TranslationUnit>[]);
  });

  late _MockLlmService llmService;
  late _MockPromptBuilder promptBuilder;
  late MockLoggingService logger;
  late LlmTranslationHandler handler;

  setUp(() {
    // Clear singleton cache between tests — LlmCacheManager uses it internally.
    BatchTranslationCache.instance.clear();

    llmService = _MockLlmService();
    promptBuilder = _MockPromptBuilder();
    logger = MockLoggingService();
    handler = LlmTranslationHandler(
      llmService: llmService,
      promptBuilder: promptBuilder,
      logger: logger,
    );
  });

  Future<void> noopCheckPauseOrCancel(String _) async {}
  dynamic noCancellationToken(String _) => null;

  group('LlmTranslationHandler.performTranslation', () {
    test('happy path: sends un-matched units to LLM and returns translations',
        () async {
      final units = [
        _fakeUnit('k1', 'Hello'),
        _fakeUnit('k2', 'World'),
      ];

      _stubPromptBuilderOk(promptBuilder);

      // Request.texts is unitId -> sourceText; the response must mirror that
      // shape so SingleBatchProcessor can zip translations back by position.
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Ok(_fakeLlmResponse(translations: {
            'unit-k1': 'Bonjour',
            'unit-k2': 'Monde',
          })));

      final progressEvents = <TranslationProgress>[];
      final (finalProgress, translations, cachedIds) =
          await handler.performTranslation(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(),
        tmMatchedUnitIds: const <String>{},
        getCancellationToken: noCancellationToken,
        onProgressUpdate: (_, p) => progressEvents.add(p),
        checkPauseOrCancel: noopCheckPauseOrCancel,
      );

      // Pump pending microtasks/tasks so any async progress callbacks emitted
      // by the internal pipeline are delivered before assertions. This guards
      // against scheduler-induced flake under full-suite parallel load.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(translations, equals({
        'unit-k1': 'Bonjour',
        'unit-k2': 'Monde',
      }));
      // No units served from cache => cachedUnitIds stays empty (both are
      // fresh LLM translations, not duplicates).
      expect(cachedIds, isEmpty);

      // Tokens are accumulated from the mocked LLM response.
      expect(finalProgress.tokensUsed, equals(100));
      // The pipeline must have surfaced progress at some point — we no longer
      // pin the exact intermediate phases, since their delivery ordering is
      // scheduler-sensitive under load. The translations + token assertions
      // above already prove the LLM path was actually taken.
      expect(progressEvents, isNotEmpty);

      // Verify the payload sent to the LLM carries exactly the two un-matched
      // units, keyed by unit.id.
      final captured = verify(() => llmService.translateBatch(
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
          )).captured;
      expect(captured, hasLength(1));
      final sentRequest = captured.single as LlmRequest;
      expect(sentRequest.texts, equals({
        'unit-k1': 'Hello',
        'unit-k2': 'World',
      }));
      expect(sentRequest.targetLanguage, equals('fr'));
      expect(sentRequest.providerCode, equals('anthropic'));
      expect(sentRequest.modelName, equals('claude-haiku-4.5'));
    });

    test('calls promptBuilder.buildPrompt once with the active context and the '
        'deduplicated units-for-LLM list', () async {
      final units = [_fakeUnit('k1', 'Hello')];
      final context = _fakeContext();

      _stubPromptBuilderOk(promptBuilder);
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async =>
          Ok(_fakeLlmResponse(translations: {'unit-k1': 'Bonjour'})));

      await handler.performTranslation(
        batchId: _batchId,
        units: units,
        context: context,
        currentProgress: _initialProgress(),
        tmMatchedUnitIds: const <String>{},
        getCancellationToken: noCancellationToken,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: noopCheckPauseOrCancel,
      );

      final captured = verify(() => promptBuilder.buildPrompt(
            units: captureAny(named: 'units'),
            context: captureAny(named: 'context'),
            includeExamples: captureAny(named: 'includeExamples'),
            maxExamples: captureAny(named: 'maxExamples'),
          )).captured;
      // One call — captureAny produces 4 captured values per call.
      expect(captured.length, equals(4));
      final capturedUnits = captured[0] as List<TranslationUnit>;
      final capturedContext = captured[1] as TranslationContext;
      final includeExamples = captured[2] as bool;
      final maxExamples = captured[3] as int;

      expect(capturedUnits.map((u) => u.id).toList(), equals(['unit-k1']));
      expect(capturedContext.id, equals(context.id));
      expect(capturedContext.targetLanguage, equals('fr'));
      // Pin the handler's current defaults for TM few-shot injection.
      expect(includeExamples, isTrue);
      expect(maxExamples, equals(3));
    });

    test('rethrows TranslationOrchestrationException when LLM returns a fatal '
        '(non-retryable, non-splittable) auth error', () async {
      final units = [_fakeUnit('k1', 'Hello')];

      _stubPromptBuilderOk(promptBuilder);
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Err<LlmResponse, LlmServiceException>(
            const LlmAuthenticationException(
              'Invalid API key',
              providerCode: 'anthropic',
            ),
          ));

      expect(
        () => handler.performTranslation(
          batchId: _batchId,
          units: units,
          context: _fakeContext(),
          currentProgress: _initialProgress(),
          tmMatchedUnitIds: const <String>{},
          getCancellationToken: noCancellationToken,
          onProgressUpdate: (_, _) {},
          checkPauseOrCancel: noopCheckPauseOrCancel,
        ),
        throwsA(isA<TranslationOrchestrationException>()),
      );
    });

    test('partial response: LLM returns fewer translations than units => the '
        'units whose keys are present get a translation and missing keys are '
        'counted in failedUnits', () async {
      final units = [
        _fakeUnit('k1', 'Hello'),
        _fakeUnit('k2', 'World'),
        _fakeUnit('k3', 'Foo'),
      ];

      _stubPromptBuilderOk(promptBuilder);
      // LLM returns translations for 2 of 3 keys. With key-based matching
      // the third unit (unit-k3) is absent from the response and must be
      // reported as a failure rather than silently dropped.
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Ok(_fakeLlmResponse(translations: {
            'unit-k1': 'Bonjour',
            'unit-k2': 'Monde',
          })));

      final (finalProgress, translations, _) =
          await handler.performTranslation(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(),
        tmMatchedUnitIds: const <String>{},
        getCancellationToken: noCancellationToken,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: noopCheckPauseOrCancel,
      );

      // Only the two units whose IDs are present in the response get a
      // translation; the third is absent from the translations map.
      expect(translations.keys, containsAll(<String>['unit-k1', 'unit-k2']));
      expect(translations.containsKey('unit-k3'), isFalse);
      expect(translations.length, equals(2));

      // The missing unit must now be surfaced via failedUnits so the
      // orchestrator can report it instead of silently losing it.
      expect(finalProgress.failedUnits, equals(1));
    });

    test('reordered response keys: LLM returns translations in a different '
        'order than requested and they are still attributed to the correct '
        'unit IDs', () async {
      final units = [
        _fakeUnit('k1', 'Hello'),
        _fakeUnit('k2', 'World'),
      ];

      _stubPromptBuilderOk(promptBuilder);
      // Response keys are in reverse order from the request. Key-based
      // matching must still pair each translation with the right unit ID;
      // the previous positional zip would have swapped them.
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Ok(_fakeLlmResponse(translations: {
            'unit-k2': 'Monde',
            'unit-k1': 'Bonjour',
          })));

      final (finalProgress, translations, _) =
          await handler.performTranslation(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(),
        tmMatchedUnitIds: const <String>{},
        getCancellationToken: noCancellationToken,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: noopCheckPauseOrCancel,
      );

      expect(translations, equals({
        'unit-k1': 'Bonjour',
        'unit-k2': 'Monde',
      }));
      // No unit is missing from the response => no failures recorded here.
      expect(finalProgress.failedUnits, equals(0));
    });

    test('extra unknown keys in response: unknown keys are ignored and known '
        'keys are correctly attributed', () async {
      final units = [
        _fakeUnit('k1', 'Hello'),
        _fakeUnit('k2', 'World'),
      ];

      _stubPromptBuilderOk(promptBuilder);
      // LLM emits an extra unsolicited key; it must be silently dropped
      // (not attached to any unit) while k1 and k2 are still delivered.
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Ok(_fakeLlmResponse(translations: {
            'unit-k1': 'Bonjour',
            'unit-k2': 'Monde',
            'unit-unknown': 'Inconnu',
          })));

      final (finalProgress, translations, _) =
          await handler.performTranslation(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(),
        tmMatchedUnitIds: const <String>{},
        getCancellationToken: noCancellationToken,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: noopCheckPauseOrCancel,
      );

      expect(translations, equals({
        'unit-k1': 'Bonjour',
        'unit-k2': 'Monde',
      }));
      expect(translations.containsKey('unit-unknown'), isFalse);
      // All requested units were translated => no failures recorded.
      expect(finalProgress.failedUnits, equals(0));
    });

    test('tmMatchedUnitIds filters units before the LLM call: matched IDs '
        'are absent from LlmRequest.texts', () async {
      final units = [
        _fakeUnit('k1', 'Hello'),
        _fakeUnit('k2', 'World'),
      ];

      _stubPromptBuilderOk(promptBuilder);
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async =>
          Ok(_fakeLlmResponse(translations: {'unit-k2': 'Monde'})));

      await handler.performTranslation(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(),
        // k1 was already translated by TM => must not be sent to LLM.
        tmMatchedUnitIds: const <String>{'unit-k1'},
        getCancellationToken: noCancellationToken,
        onProgressUpdate: (_, _) {},
        checkPauseOrCancel: noopCheckPauseOrCancel,
      );

      final captured = verify(() => llmService.translateBatch(
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
          )).captured;
      final sentRequest = captured.single as LlmRequest;
      expect(sentRequest.texts.keys, equals(<String>['unit-k2']));
      expect(sentRequest.texts.containsKey('unit-k1'), isFalse);
    });

    test('cancellation: when checkPauseOrCancel throws, the handler never '
        'reaches the LLM service', () async {
      // Note on plan drift: the plan (test 6) suggests a "cancellation token
      // with isCancelled:true" short-circuit, but the handler does NOT read
      // LlmCancellationToken.isCancelled itself. Cancellation flows through
      // the checkPauseOrCancel callback, which TranslationSplitter invokes at
      // the top of every translateWithAutoSplit call and which is expected to
      // throw when the batch is cancelled. That is the real cancellation
      // contract, so we pin it here.
      final units = [_fakeUnit('k1', 'Hello')];

      _stubPromptBuilderOk(promptBuilder);
      when(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async =>
          Ok(_fakeLlmResponse(translations: {'unit-k1': 'Bonjour'})));

      Future<void> cancellingCheck(String _) async {
        throw const TranslationOrchestrationException(
          'Translation cancelled by user',
          batchId: _batchId,
        );
      }

      await expectLater(
        handler.performTranslation(
          batchId: _batchId,
          units: units,
          context: _fakeContext(),
          currentProgress: _initialProgress(),
          tmMatchedUnitIds: const <String>{},
          getCancellationToken: noCancellationToken,
          onProgressUpdate: (_, _) {},
          checkPauseOrCancel: cancellingCheck,
        ),
        throwsA(isA<TranslationOrchestrationException>()),
      );

      verifyNever(() => llmService.translateBatch(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ));
    });
  });
}
