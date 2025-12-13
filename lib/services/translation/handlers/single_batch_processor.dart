import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'llm_token_estimator.dart';
import 'llm_cache_manager.dart';
import 'translation_splitter.dart';

/// Handles single (non-parallel) batch processing for LLM translation.
///
/// Responsibilities:
/// - Process a batch of units sequentially
/// - Delegate to TranslationSplitter for auto-splitting logic
/// - Update cache with results
/// - Handle duplicate translations
class SingleBatchProcessor {
  final LlmTokenEstimator _tokenEstimator;
  final LlmCacheManager _cacheManager;
  final TranslationSplitter _translationSplitter;
  final LoggingService _logger;

  SingleBatchProcessor({
    required LlmTokenEstimator tokenEstimator,
    required LlmCacheManager cacheManager,
    required TranslationSplitter translationSplitter,
    required LoggingService logger,
  })  : _tokenEstimator = tokenEstimator,
        _cacheManager = cacheManager,
        _translationSplitter = translationSplitter,
        _logger = logger;

  /// Process units as a single batch (with auto-splitting if needed).
  ///
  /// Returns tuple of (updated progress, translations map, cached unit IDs).
  Future<(TranslationProgress, Map<String, String>, Set<String>)>
      processSingleBatch({
    required String batchId,
    required List<TranslationUnit> unitsForLlm,
    required List<TranslationUnit> unitsToTranslate,
    required dynamic builtPrompt,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required CacheProcessingResult cacheResult,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress)
        onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    SubBatchTranslatedCallback? onSubBatchTranslated,
  }) async {
    // Build texts map for LLM request
    final textsMap = <String, String>{};
    for (final unit in unitsForLlm) {
      textsMap[unit.id] = unit.sourceText;
    }

    final maxTokens = _tokenEstimator.estimateMaxTokens(textsMap);

    final llmRequest = LlmRequest(
      requestId: batchId,
      texts: textsMap,
      targetLanguage: context.targetLanguage,
      systemPrompt: builtPrompt.systemMessage,
      modelName: context.modelId,
      providerCode: context.providerCode,
      gameContext: context.gameContext,
      glossaryTerms: context.glossaryTerms,
      maxTokens: maxTokens,
      timestamp: DateTime.now(),
    );

    // Track saved unit IDs for duplicate handling
    final savedUnitIds = <String>{};

    // Create tracking callback
    Future<void> trackingSaveCallback(
      List<TranslationUnit> units,
      Map<String, String> translations,
      Set<String> subBatchCachedIds,
    ) async {
      if (onSubBatchTranslated != null) {
        await onSubBatchTranslated(units, translations, subBatchCachedIds);
        savedUnitIds.addAll(translations.keys);
      }
    }

    try {
      final (finalProgress, llmTranslations) =
          await _translationSplitter.translateWithAutoSplit(
        batchId: batchId,
        rootBatchId: batchId,
        unitsToTranslate: unitsForLlm,
        llmRequest: llmRequest,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: trackingSaveCallback,
      );

      // Update cache and apply to duplicates
      await _cacheManager.updateCacheAndApplyDuplicates(
        llmTranslations: llmTranslations,
        sourceTextToUnits: cacheResult.sourceTextToUnits,
        registeredHashes: cacheResult.registeredHashes,
        allTranslations: cacheResult.allTranslations,
        cachedUnitIds: cacheResult.cachedUnitIds,
        context: context,
      );

      // Save any unsaved duplicate translations
      if (onSubBatchTranslated != null &&
          cacheResult.allTranslations.isNotEmpty) {
        await _saveUnsavedDuplicates(
          savedUnitIds: savedUnitIds,
          allTranslations: cacheResult.allTranslations,
          unitsToTranslate: unitsToTranslate,
          onSubBatchTranslated: onSubBatchTranslated,
        );
      }

      return (
        finalProgress,
        cacheResult.allTranslations,
        cacheResult.cachedUnitIds
      );
    } catch (e) {
      // On error, fail all registered cache entries
      _cacheManager.failRegisteredHashes(cacheResult.registeredHashes);
      rethrow;
    }
  }

  /// Save any duplicate translations that weren't saved during processing.
  Future<void> _saveUnsavedDuplicates({
    required Set<String> savedUnitIds,
    required Map<String, String> allTranslations,
    required List<TranslationUnit> unitsToTranslate,
    required SubBatchTranslatedCallback onSubBatchTranslated,
  }) async {
    final unsavedTranslations = Map.fromEntries(
      allTranslations.entries.where((e) => !savedUnitIds.contains(e.key)),
    );

    if (unsavedTranslations.isNotEmpty) {
      _logger.debug('Saving ${unsavedTranslations.length} duplicate units');
      final unsavedUnits = unitsToTranslate
          .where((u) => unsavedTranslations.containsKey(u.id))
          .toList();
      final unsavedCachedIds = unsavedTranslations.keys.toSet();
      try {
        await onSubBatchTranslated(
            unsavedUnits, unsavedTranslations, unsavedCachedIds);
      } catch (e) {
        _logger.warning('Failed to save duplicate translations: $e');
      }
    }
  }
}
