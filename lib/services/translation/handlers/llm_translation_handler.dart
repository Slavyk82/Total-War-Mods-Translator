import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/utils/translation_skip_filter.dart';
import 'llm_token_estimator.dart';
import 'llm_cache_manager.dart';
import 'llm_retry_handler.dart';
import 'translation_splitter.dart';
import 'parallel_batch_processor.dart';
import 'single_batch_processor.dart';

/// Handles LLM translation operations.
///
/// Responsibilities:
/// - Build contextual prompts with TM examples (few-shot learning)
/// - Orchestrate translation workflow
/// - Delegate batch processing to specialized handlers
/// - Track token usage
/// - Return translation results
///
/// Delegates to:
/// - [LlmTokenEstimator] for token calculation and batch size optimization
/// - [LlmCacheManager] for cache operations and deduplication
/// - [LlmRetryHandler] for retry logic on transient errors
/// - [TranslationSplitter] for auto-splitting large batches
/// - [ParallelBatchProcessor] for parallel batch processing
/// - [SingleBatchProcessor] for sequential batch processing
class LlmTranslationHandler {
  final IPromptBuilderService _promptBuilder;
  final LoggingService _logger;
  final LlmTokenEstimator _tokenEstimator = LlmTokenEstimator();
  late final LlmCacheManager _cacheManager;
  late final LlmRetryHandler _retryHandler;
  late final TranslationSplitter _translationSplitter;
  late final ParallelBatchProcessor _parallelBatchProcessor;
  late final SingleBatchProcessor _singleBatchProcessor;

  LlmTranslationHandler({
    required ILlmService llmService,
    required IPromptBuilderService promptBuilder,
    required LoggingService logger,
  })  : _promptBuilder = promptBuilder,
        _logger = logger {
    _cacheManager = LlmCacheManager(logger: logger);
    _retryHandler = LlmRetryHandler(llmService: llmService, logger: logger);
    _translationSplitter = TranslationSplitter(
      tokenEstimator: _tokenEstimator,
      retryHandler: _retryHandler,
      logger: logger,
    );
    _parallelBatchProcessor = ParallelBatchProcessor(
      tokenEstimator: _tokenEstimator,
      cacheManager: _cacheManager,
      translationSplitter: _translationSplitter,
      logger: logger,
    );
    _singleBatchProcessor = SingleBatchProcessor(
      tokenEstimator: _tokenEstimator,
      cacheManager: _cacheManager,
      translationSplitter: _translationSplitter,
      logger: logger,
    );
  }

  /// Perform LLM translation for units not matched by TM.
  ///
  /// Returns tuple of (updated progress, translations map, cachedUnitIds).
  ///
  /// [tmMatchedUnitIds] contains IDs of units already translated by TM lookup.
  /// [onSubBatchTranslated] is called after each successful LLM sub-batch.
  /// [checkPauseOrCancel] is called to check for stop/cancel requests.
  Future<(TranslationProgress, Map<String, String>, Set<String>)>
      performTranslation({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Set<String> tmMatchedUnitIds,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress)
        onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(
            List<TranslationUnit> units,
            Map<String, String> translations,
            Set<String> cachedUnitIds)?
        onSubBatchTranslated,
  }) async {
    // Filter units that need translation (not already matched by TM)
    final unitsNotMatchedByTm =
        units.where((unit) => !tmMatchedUnitIds.contains(unit.id)).toList();

    if (unitsNotMatchedByTm.isEmpty) {
      return (currentProgress, <String, String>{}, <String>{});
    }

    // Filter out skipped texts
    final (skippedUnits, unitsToTranslate) =
        _filterSkippedUnits(unitsNotMatchedByTm);

    if (skippedUnits.isNotEmpty) {
      _logger.info(
        'Excluding ${skippedUnits.length} units from LLM translation (bracketed placeholders or skip-list matches)',
      );
    }

    if (unitsToTranslate.isEmpty) {
      return (currentProgress, <String, String>{}, <String>{});
    }

    // Process cache and deduplication
    final cacheResult = await _cacheManager.processUnitsForCache(
      batchId: batchId,
      unitsToTranslate: unitsToTranslate,
      context: context,
      onProgressUpdate: (id, detail) {
        onProgressUpdate(
          id,
          currentProgress.copyWith(
              phaseDetail: detail, timestamp: DateTime.now()),
        );
      },
    );

    // If all translations came from cache, we're done
    if (cacheResult.uncachedSourceTexts.isEmpty) {
      return _handleAllFromCache(
        unitsToTranslate: unitsToTranslate,
        cacheResult: cacheResult,
        currentProgress: currentProgress,
        onSubBatchTranslated: onSubBatchTranslated,
      );
    }

    // Build units for LLM: one unit per unique source text
    final unitsForLlm = _buildUnitsForLlm(cacheResult);

    _logger.info(
      'LLM translation: ${unitsForLlm.length} unique texts (${unitsToTranslate.length} total units) via ${context.providerId ?? "default"}/${context.modelId ?? "default"}',
    );

    // Build prompt
    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.buildingPrompt,
      phaseDetail: 'Building translation prompt with context and examples...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    final builtPrompt = await _buildPrompt(
      batchId: batchId,
      unitsForLlm: unitsForLlm,
      context: context,
      progress: progress,
      cacheResult: cacheResult,
      onProgressUpdate: onProgressUpdate,
    );

    progress = progress.copyWith(
      currentPhase: TranslationPhase.llmTranslation,
      phaseDetail:
          'Starting LLM translation (${unitsForLlm.length} unique texts via ${context.providerCode ?? "default"})...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    // Choose processing strategy based on configuration
    if (context.parallelBatches > 1 &&
        unitsForLlm.length > context.parallelBatches) {
      return _parallelBatchProcessor.processParallelBatches(
        batchId: batchId,
        unitsForLlm: unitsForLlm,
        unitsToTranslate: unitsToTranslate,
        builtPrompt: builtPrompt,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        cacheResult: cacheResult,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
      );
    }

    return _singleBatchProcessor.processSingleBatch(
      batchId: batchId,
      unitsForLlm: unitsForLlm,
      unitsToTranslate: unitsToTranslate,
      builtPrompt: builtPrompt,
      context: context,
      progress: progress,
      currentProgress: currentProgress,
      cacheResult: cacheResult,
      getCancellationToken: getCancellationToken,
      onProgressUpdate: onProgressUpdate,
      checkPauseOrCancel: checkPauseOrCancel,
      onSubBatchTranslated: onSubBatchTranslated,
    );
  }

  /// Filter units that should be skipped from translation.
  ///
  /// Returns tuple of (skipped units, units to translate).
  (List<TranslationUnit>, List<TranslationUnit>) _filterSkippedUnits(
    List<TranslationUnit> units,
  ) {
    final skippedUnits = <TranslationUnit>[];
    final unitsToTranslate = <TranslationUnit>[];

    for (final unit in units) {
      if (TranslationSkipFilter.shouldSkip(unit.sourceText)) {
        skippedUnits.add(unit);
      } else {
        unitsToTranslate.add(unit);
      }
    }

    return (skippedUnits, unitsToTranslate);
  }

  /// Handle case where all translations came from cache.
  Future<(TranslationProgress, Map<String, String>, Set<String>)>
      _handleAllFromCache({
    required List<TranslationUnit> unitsToTranslate,
    required CacheProcessingResult cacheResult,
    required TranslationProgress currentProgress,
    Future<void> Function(
            List<TranslationUnit>, Map<String, String>, Set<String>)?
        onSubBatchTranslated,
  }) async {
    _logger.info(
        'All ${unitsToTranslate.length} translations served from cache');

    if (onSubBatchTranslated != null && cacheResult.allTranslations.isNotEmpty) {
      try {
        await onSubBatchTranslated(
          unitsToTranslate,
          cacheResult.allTranslations,
          cacheResult.cachedUnitIds,
        );
      } catch (e) {
        _logger.warning('Failed to save cached translations: $e');
      }
    }

    return (
      currentProgress,
      cacheResult.allTranslations,
      cacheResult.cachedUnitIds
    );
  }

  /// Build units list for LLM (one per unique source text).
  List<TranslationUnit> _buildUnitsForLlm(CacheProcessingResult cacheResult) {
    final unitsForLlm = <TranslationUnit>[];
    for (final sourceText in cacheResult.uncachedSourceTexts) {
      final units = cacheResult.sourceTextToUnits[sourceText]!;
      unitsForLlm.add(units.first);
    }
    return unitsForLlm;
  }

  /// Build the translation prompt with TM examples.
  Future<dynamic> _buildPrompt({
    required String batchId,
    required List<TranslationUnit> unitsForLlm,
    required TranslationContext context,
    required TranslationProgress progress,
    required CacheProcessingResult cacheResult,
    required void Function(String batchId, TranslationProgress progress)
        onProgressUpdate,
  }) async {
    var updatedProgress = progress.copyWith(
      phaseDetail: 'Loading few-shot examples from Translation Memory...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, updatedProgress);

    final promptResult = await _promptBuilder.buildPrompt(
      units: unitsForLlm,
      context: context,
      includeExamples: true,
      maxExamples: 3,
    );

    if (promptResult.isErr) {
      _cacheManager.failRegisteredHashes(cacheResult.registeredHashes);
      throw TranslationOrchestrationException(
        'Failed to build prompt: ${promptResult.unwrapErr()}',
        batchId: batchId,
      );
    }

    return promptResult.unwrap();
  }
}
