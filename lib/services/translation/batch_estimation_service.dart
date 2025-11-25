import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/batch_estimate.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Service for batch translation performance estimation
///
/// Handles all estimation-related operations including:
/// - Token count estimation
/// - Duration prediction
/// - TM reuse rate analysis
class BatchEstimationService {
  final ILlmService _llmService;
  final IPromptBuilderService _promptBuilder;
  final LoggingService _logger;

  /// Function to check if a unit is already translated (from TM)
  final Future<bool> Function(TranslationUnit, TranslationContext) _isUnitTranslated;

  BatchEstimationService({
    required ILlmService llmService,
    required IPromptBuilderService promptBuilder,
    required LoggingService logger,
    required Future<bool> Function(TranslationUnit, TranslationContext) isUnitTranslated,
  })  : _llmService = llmService,
        _promptBuilder = promptBuilder,
        _logger = logger,
        _isUnitTranslated = isUnitTranslated;

  /// Estimate performance for batch translation
  ///
  /// Analyzes:
  /// - TM match coverage (units that won't need LLM)
  /// - Token count estimation for LLM units
  /// - Duration prediction based on historical performance
  ///
  /// [batchId]: Batch identifier
  /// [units]: Translation units to estimate
  /// [context]: Translation context (languages, provider, etc.)
  ///
  /// Returns detailed batch estimate or error
  Future<Result<BatchEstimate, TranslationOrchestrationException>>
      estimateBatch({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
  }) async {
    try {
      _logger.info('Estimating batch', {'batchId': batchId});

      if (units.isEmpty) {
        return Err(EmptyBatchException('Batch has no units', batchId: batchId));
      }

      // Check TM for exact/fuzzy matches to calculate TM reuse rate
      var tmMatchCount = 0;
      for (final unit in units) {
        if (await _isUnitTranslated(unit, context)) {
          tmMatchCount++;
        }
      }

      final unitsRequiringLlm = units.length - tmMatchCount;
      final tmReuseRate = units.isNotEmpty ? tmMatchCount / units.length : 0.0;

      // Build prompt for token estimation
      final promptResult = await _promptBuilder.buildPrompt(
        units: units.take(unitsRequiringLlm).toList(),
        context: context,
        includeExamples: true,
        maxExamples: 3,
      );

      if (promptResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to build prompt for estimation: ${promptResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      // Create LLM request for token estimation
      final textsMap = <String, String>{};
      for (var i = 0; i < unitsRequiringLlm && i < units.length; i++) {
        textsMap[units[i].id] = units[i].sourceText;
      }

      final llmRequest = LlmRequest(
        requestId: 'estimate-$batchId',
        texts: textsMap,
        targetLanguage: context.targetLanguage,
        systemPrompt: promptResult.unwrap().systemMessage,
        modelName: context.modelId,
        providerCode: context.providerCode,
        gameContext: context.gameContext,
        glossaryTerms: context.glossaryTerms,
        timestamp: DateTime.now(),
      );

      // Estimate tokens using LLM service
      final tokensResult = await _llmService.estimateTokens(llmRequest);
      if (tokensResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to estimate tokens: ${tokensResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      final estimatedTokens = tokensResult.unwrap();
      // Split tokens: ~40% input (source text), ~60% output (translation)
      final estimatedInputTokens = (estimatedTokens * 0.4).round();
      final estimatedOutputTokens = (estimatedTokens * 0.6).round();

      // Get provider info
      final providerCode = await _llmService.getActiveProviderCode();

      // Get model name from provider configuration
      String modelName = 'Unknown';
      try {
        final providerRepo = ServiceLocator.get<TranslationProviderRepository>();
        final providerResult = await providerRepo.getByCode(providerCode);

        if (providerResult.isOk) {
          final provider = providerResult.unwrap();
          modelName = provider.defaultModel ?? 'Unknown';
        }
      } catch (e) {
        _logger.warning('Failed to get provider model name: $e');
      }

      // Estimate duration (rough: 50 units per minute)
      final estimatedDurationSeconds =
          ((unitsRequiringLlm / AppConstants.estimatedUnitsPerMinute) * 60).round();

      final estimate = BatchEstimate(
        batchId: batchId,
        totalUnits: units.length,
        estimatedInputTokens: estimatedInputTokens,
        estimatedOutputTokens: estimatedOutputTokens,
        totalEstimatedTokens: estimatedTokens,
        providerCode: providerCode,
        modelName: modelName,
        unitsFromTm: tmMatchCount,
        unitsRequiringLlm: unitsRequiringLlm,
        tmReuseRate: tmReuseRate,
        estimatedDurationSeconds: estimatedDurationSeconds,
        createdAt: DateTime.now(),
      );

      _logger.info('Batch estimation completed', {
        'batchId': batchId,
        'totalUnits': units.length,
        'unitsFromTm': tmMatchCount,
        'unitsRequiringLlm': unitsRequiringLlm,
        'estimatedTokens': estimatedTokens,
      });

      return Ok(estimate);
    } catch (e, stackTrace) {
      _logger.error('Batch estimation failed', e, stackTrace);
      return Err(
        TranslationOrchestrationException(
          'Failed to estimate batch: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
