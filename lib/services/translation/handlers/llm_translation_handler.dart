import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

/// Handles LLM translation operations
///
/// Responsibilities:
/// - Build contextual prompts with TM examples (few-shot learning)
/// - Call LLM service for translation
/// - Track token usage
/// - Return translation results
class LlmTranslationHandler {
  final ILlmService _llmService;
  final IPromptBuilderService _promptBuilder;
  final LoggingService _logger;

  LlmTranslationHandler({
    required ILlmService llmService,
    required IPromptBuilderService promptBuilder,
    required LoggingService logger,
  })  : _llmService = llmService,
        _promptBuilder = promptBuilder,
        _logger = logger;

  /// Perform LLM translation for units not matched by TM
  ///
  /// Returns tuple of (updated progress, translations map)
  Future<(TranslationProgress, Map<String, String>)> performTranslation({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Future<bool> Function(TranslationUnit unit, TranslationContext context) isUnitTranslated,
  }) async {
    // Get units that still need translation (not matched by TM)
    final unitsToTranslate = <TranslationUnit>[];
    for (final unit in units) {
      if (!await isUnitTranslated(unit, context)) {
        unitsToTranslate.add(unit);
      }
    }

    if (unitsToTranslate.isEmpty) {
      _logger.info('No units require LLM translation', {'batchId': batchId});
      return (currentProgress, <String, String>{});
    }

    _logger.info('Starting LLM translation', {
      'batchId': batchId,
      'unitsCount': unitsToTranslate.length,
    });

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.buildingPrompt,
      timestamp: DateTime.now(),
    );

    // Build prompt with TM examples (few-shot learning)
    final promptResult = await _promptBuilder.buildPrompt(
      units: unitsToTranslate,
      context: context,
      includeExamples: true,
      maxExamples: 3,
    );

    if (promptResult.isErr) {
      throw TranslationOrchestrationException(
        'Failed to build prompt: ${promptResult.unwrapErr()}',
        batchId: batchId,
      );
    }

    final builtPrompt = promptResult.unwrap();

    progress = progress.copyWith(
      currentPhase: TranslationPhase.llmTranslation,
      timestamp: DateTime.now(),
    );

    // Create LLM request
    final textsMap = <String, String>{};
    for (final unit in unitsToTranslate) {
      textsMap[unit.id] = unit.sourceText;
    }

    final llmRequest = LlmRequest(
      requestId: batchId,
      texts: textsMap,
      targetLanguage: context.targetLanguage,
      systemPrompt: builtPrompt.systemMessage,
      modelName: context.modelId,
      gameContext: context.gameContext,
      glossaryTerms: context.glossaryTerms,
      timestamp: DateTime.now(),
    );

    // Call LLM service
    final llmResult = await _llmService.translateBatch(llmRequest);

    if (llmResult.isErr) {
      throw TranslationOrchestrationException(
        'LLM translation failed: ${llmResult.unwrapErr()}',
        batchId: batchId,
      );
    }

    final llmResponse = llmResult.unwrap();

    // Store LLM translations in map to return for validation step
    final translations = <String, String>{};
    for (var i = 0;
        i < unitsToTranslate.length && i < llmResponse.translations.length;
        i++) {
      final unit = unitsToTranslate[i];
      final translatedText = llmResponse.translations.values.elementAt(i);

      // Store in map for validation step
      translations[unit.id] = translatedText;
    }

    _logger.info('LLM translation completed', {
      'batchId': batchId,
      'translatedCount': llmResponse.translations.length,
      'tokensUsed': llmResponse.totalTokens,
    });

    final updatedProgress = progress.copyWith(
      tokensUsed: currentProgress.tokensUsed + llmResponse.totalTokens,
      timestamp: DateTime.now(),
    );

    return (updatedProgress, translations);
  }
}
