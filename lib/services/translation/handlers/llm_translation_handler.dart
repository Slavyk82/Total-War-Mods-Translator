import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/utils/translation_text_utils.dart';
import 'llm_token_estimator.dart';
import 'llm_cache_manager.dart';
import 'llm_retry_handler.dart';

/// Handles LLM translation operations.
///
/// Responsibilities:
/// - Build contextual prompts with TM examples (few-shot learning)
/// - Call LLM service for translation
/// - Track token usage
/// - Return translation results
///
/// Delegates to:
/// - [LlmTokenEstimator] for token calculation and batch size optimization
/// - [LlmCacheManager] for cache operations and deduplication
/// - [LlmRetryHandler] for retry logic on transient errors
class LlmTranslationHandler {
  /// Checks if the source text is entirely a simple bracketed placeholder.
  ///
  /// These texts are typically placeholders or non-translatable markers
  /// and should be copied as-is without translation.
  /// Example: "[PLACEHOLDER]", "[unit_name]"
  ///
  /// Does NOT match BBCode/Total War double-bracket tags like:
  /// "[[col:yellow]]text[[/col]]" - these should be translated
  static bool _isFullyBracketedText(String text) {
    final trimmed = text.trim();

    // Must start with [ and end with ]
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']') || trimmed.length <= 2) {
      return false;
    }

    // If it starts with [[ it's BBCode, not a placeholder - should translate
    if (trimmed.startsWith('[[')) {
      return false;
    }

    // Check if it's a simple single-bracketed expression: [something]
    // Should have exactly one [ at start and one ] at end
    final innerContent = trimmed.substring(1, trimmed.length - 1);

    // If inner content contains more brackets, it's not a simple placeholder
    if (innerContent.contains('[') || innerContent.contains(']')) {
      return false;
    }

    // Simple placeholder like [PLACEHOLDER] or [unit_name]
    return true;
  }

  final IPromptBuilderService _promptBuilder;
  final LoggingService _logger;
  final LlmTokenEstimator _tokenEstimator = LlmTokenEstimator();
  late final LlmCacheManager _cacheManager;
  late final LlmRetryHandler _retryHandler;

  LlmTranslationHandler({
    required ILlmService llmService,
    required IPromptBuilderService promptBuilder,
    required LoggingService logger,
  })  : _promptBuilder = promptBuilder,
        _logger = logger {
    _cacheManager = LlmCacheManager(logger: logger);
    _retryHandler = LlmRetryHandler(llmService: llmService, logger: logger);
  }

  /// Perform LLM translation for units not matched by TM.
  ///
  /// Returns tuple of (updated progress, translations map, cachedUnitIds).
  ///
  /// [tmMatchedUnitIds] contains IDs of units already translated by TM lookup.
  /// [onSubBatchTranslated] is called after each successful LLM sub-batch.
  /// [checkPauseOrCancel] is called to check for stop/cancel requests.
  Future<(TranslationProgress, Map<String, String>, Set<String>)> performTranslation({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Set<String> tmMatchedUnitIds,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(List<TranslationUnit> units, Map<String, String> translations, Set<String> cachedUnitIds)? onSubBatchTranslated,
  }) async {
    // Filter units that need translation (not already matched by TM)
    final unitsNotMatchedByTm = units
        .where((unit) => !tmMatchedUnitIds.contains(unit.id))
        .toList();

    if (unitsNotMatchedByTm.isEmpty) {
      return (currentProgress, <String, String>{}, <String>{});
    }

    // Separate fully bracketed texts (e.g., "[PLACEHOLDER]") - these are copied as-is
    final bracketedUnits = <TranslationUnit>[];
    final unitsToTranslate = <TranslationUnit>[];

    for (final unit in unitsNotMatchedByTm) {
      if (_isFullyBracketedText(unit.sourceText)) {
        bracketedUnits.add(unit);
      } else {
        unitsToTranslate.add(unit);
      }
    }

    // Log skipped bracketed units - these are excluded from translation entirely
    // (no translation_version created, excluded from statistics)
    if (bracketedUnits.isNotEmpty) {
      _logger.info(
        'Excluding ${bracketedUnits.length} fully-bracketed units from translation (e.g., [hidden], [PLACEHOLDER])',
      );
    }

    // If all remaining units are bracketed, nothing to translate
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
          currentProgress.copyWith(phaseDetail: detail, timestamp: DateTime.now()),
        );
      },
    );

    // If all translations came from cache, we're done
    if (cacheResult.uncachedSourceTexts.isEmpty) {
      _logger.info('All ${unitsToTranslate.length} translations served from cache');

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

      return (currentProgress, cacheResult.allTranslations, cacheResult.cachedUnitIds);
    }

    // Build units for LLM: one unit per unique source text
    final unitsForLlm = <TranslationUnit>[];
    for (final sourceText in cacheResult.uncachedSourceTexts) {
      final units = cacheResult.sourceTextToUnits[sourceText]!;
      unitsForLlm.add(units.first);
    }

    _logger.info(
      'LLM translation: ${unitsForLlm.length} unique texts (${unitsToTranslate.length} total units) via ${context.providerId ?? "default"}/${context.modelId ?? "default"}',
    );

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.buildingPrompt,
      phaseDetail: 'Building translation prompt with context and examples...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    // Build prompt with TM examples
    progress = progress.copyWith(
      phaseDetail: 'Loading few-shot examples from Translation Memory...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

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

    final builtPrompt = promptResult.unwrap();

    progress = progress.copyWith(
      currentPhase: TranslationPhase.llmTranslation,
      phaseDetail: 'Starting LLM translation (${unitsForLlm.length} unique texts via ${context.providerCode ?? "default"})...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    // Handle parallel batches if configured
    final parallelBatches = context.parallelBatches;
    if (parallelBatches > 1 && unitsForLlm.length > parallelBatches) {
      final (resultProgress, translations, cachedIds) = await _processParallelBatches(
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
      return (resultProgress, translations, cachedIds);
    }

    // Single batch processing
    final (resultProgress, translations, cachedIds) = await _processSingleBatch(
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
    return (resultProgress, translations, cachedIds);
  }

  Future<(TranslationProgress, Map<String, String>, Set<String>)> _processParallelBatches({
    required String batchId,
    required List<TranslationUnit> unitsForLlm,
    required List<TranslationUnit> unitsToTranslate,
    required dynamic builtPrompt,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required CacheProcessingResult cacheResult,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(List<TranslationUnit>, Map<String, String>, Set<String>)? onSubBatchTranslated,
  }) async {
    await checkPauseOrCancel(batchId);

    final parallelBatches = context.parallelBatches;
    progress = progress.copyWith(
      phaseDetail: 'Splitting into $parallelBatches parallel batches for faster processing...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    _logger.debug('Splitting into $parallelBatches parallel batches');

    final chunkSize = (unitsForLlm.length / parallelBatches).ceil();
    final chunks = <List<TranslationUnit>>[];

    for (var i = 0; i < unitsForLlm.length; i += chunkSize) {
      final end = (i + chunkSize < unitsForLlm.length) ? i + chunkSize : unitsForLlm.length;
      chunks.add(unitsForLlm.sublist(i, end));
    }

    _logger.debug('Created ${chunks.length} parallel chunks');

    final savedUnitIds = <String>{};

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

    progress = progress.copyWith(
      phaseDetail: 'Waiting LLM API response (${chunks.length} parallel requests)...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    void parallelProgressUpdate(String id, TranslationProgress chunkProgress) {
      final stableProgress = progress.copyWith(
        phaseDetail: chunkProgress.phaseDetail,
        currentPhase: chunkProgress.currentPhase,
        llmLogs: chunkProgress.llmLogs,
        timestamp: chunkProgress.timestamp,
      );
      onProgressUpdate(id, stableProgress);
    }

    final futures = <Future<(TranslationProgress, Map<String, String>, String?)>>[];

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final chunkId = '$batchId-parallel-$i';

      final textsMap = <String, String>{};
      for (final unit in chunk) {
        textsMap[unit.id] = unit.sourceText;
      }

      final maxTokens = _tokenEstimator.estimateMaxTokens(textsMap);

      final llmRequest = LlmRequest(
        requestId: chunkId,
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

      futures.add(_translateChunkWithErrorHandling(
        chunkId: chunkId,
        rootBatchId: batchId,
        chunk: chunk,
        llmRequest: llmRequest,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: parallelProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: trackingSaveCallback,
      ));
    }

    final results = await Future.wait(futures);

    final llmTranslations = <String, String>{};
    final chunkErrors = <String>[];
    int totalTokensUsed = currentProgress.tokensUsed;
    final allLlmLogs = <LlmExchangeLog>[...currentProgress.llmLogs];

    for (final (chunkProgress, chunkTranslations, chunkError) in results) {
      llmTranslations.addAll(chunkTranslations);
      if (chunkError != null) {
        chunkErrors.add(chunkError);
      }
      final newLogs = chunkProgress.llmLogs
          .where((log) => !allLlmLogs.any((existing) => existing.requestId == log.requestId))
          .toList();
      allLlmLogs.addAll(newLogs);
      for (final log in newLogs) {
        totalTokensUsed += log.inputTokens + log.outputTokens;
      }
    }

    if (chunkErrors.isNotEmpty) {
      _logger.warning(
        'Some chunks failed during parallel translation: ${chunkErrors.length} errors. '
        'Successfully translated ${llmTranslations.length} units.',
      );
    }

    _logger.debug('Parallel translation completed: ${llmTranslations.length} translations');

    final completionProgress = progress.copyWith(
      phaseDetail: 'LLM translation complete (${llmTranslations.length} translations received)',
      llmLogs: allLlmLogs,
      timestamp: DateTime.now(),
    );
    parallelProgressUpdate(batchId, completionProgress);

    var finalProgress = progress.copyWith(
      tokensUsed: totalTokensUsed,
      llmLogs: allLlmLogs,
      timestamp: DateTime.now(),
    );

    await _cacheManager.updateCacheAndApplyDuplicates(
      llmTranslations: llmTranslations,
      sourceTextToUnits: cacheResult.sourceTextToUnits,
      registeredHashes: cacheResult.registeredHashes,
      allTranslations: cacheResult.allTranslations,
      cachedUnitIds: cacheResult.cachedUnitIds,
      context: context,
    );

    if (onSubBatchTranslated != null && cacheResult.allTranslations.isNotEmpty) {
      final unsavedTranslations = Map.fromEntries(
        cacheResult.allTranslations.entries.where((e) => !savedUnitIds.contains(e.key)),
      );

      if (unsavedTranslations.isNotEmpty) {
        _logger.debug('Saving ${unsavedTranslations.length} duplicate units');
        final unsavedUnits = unitsToTranslate
            .where((u) => unsavedTranslations.containsKey(u.id))
            .toList();
        final unsavedCachedIds = unsavedTranslations.keys.toSet();
        try {
          await onSubBatchTranslated(unsavedUnits, unsavedTranslations, unsavedCachedIds);
        } catch (e) {
          _logger.warning('Failed to save duplicate translations: $e');
        }
      }
    }

    return (finalProgress, cacheResult.allTranslations, cacheResult.cachedUnitIds);
  }

  Future<(TranslationProgress, Map<String, String>, Set<String>)> _processSingleBatch({
    required String batchId,
    required List<TranslationUnit> unitsForLlm,
    required List<TranslationUnit> unitsToTranslate,
    required dynamic builtPrompt,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required CacheProcessingResult cacheResult,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(List<TranslationUnit>, Map<String, String>, Set<String>)? onSubBatchTranslated,
  }) async {
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

    final savedUnitIds = <String>{};

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
      final (finalProgress, llmTranslations) = await _translateWithAutoSplit(
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

      await _cacheManager.updateCacheAndApplyDuplicates(
        llmTranslations: llmTranslations,
        sourceTextToUnits: cacheResult.sourceTextToUnits,
        registeredHashes: cacheResult.registeredHashes,
        allTranslations: cacheResult.allTranslations,
        cachedUnitIds: cacheResult.cachedUnitIds,
        context: context,
      );

      if (onSubBatchTranslated != null && cacheResult.allTranslations.isNotEmpty) {
        final unsavedTranslations = Map.fromEntries(
          cacheResult.allTranslations.entries.where((e) => !savedUnitIds.contains(e.key)),
        );

        if (unsavedTranslations.isNotEmpty) {
          _logger.debug('Saving ${unsavedTranslations.length} duplicate units');
          final unsavedUnits = unitsToTranslate
              .where((u) => unsavedTranslations.containsKey(u.id))
              .toList();
          final unsavedCachedIds = unsavedTranslations.keys.toSet();
          try {
            await onSubBatchTranslated(unsavedUnits, unsavedTranslations, unsavedCachedIds);
          } catch (e) {
            _logger.warning('Failed to save duplicate translations: $e');
          }
        }
      }

      return (finalProgress, cacheResult.allTranslations, cacheResult.cachedUnitIds);
    } catch (e) {
      _cacheManager.failRegisteredHashes(cacheResult.registeredHashes);
      rethrow;
    }
  }

  Future<(TranslationProgress, Map<String, String>, String?)> _translateChunkWithErrorHandling({
    required String chunkId,
    required String rootBatchId,
    required List<TranslationUnit> chunk,
    required LlmRequest llmRequest,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(List<TranslationUnit>, Map<String, String>, Set<String>)? onSubBatchTranslated,
  }) async {
    try {
      final (resultProgress, translations) = await _translateWithAutoSplit(
        batchId: chunkId,
        rootBatchId: rootBatchId,
        unitsToTranslate: chunk,
        llmRequest: llmRequest,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
      );
      return (resultProgress, translations, null);
    } on TranslationOrchestrationException catch (e) {
      _logger.warning('Chunk $chunkId failed: ${e.message}. Skipping ${chunk.length} units.');

      final errorLog = LlmExchangeLog.fromError(
        requestId: chunkId,
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: chunk.length,
        errorMessage: 'Chunk skipped: ${e.message}',
      );

      final errorProgress = progress.copyWith(
        llmLogs: [...currentProgress.llmLogs, errorLog],
        phaseDetail: 'Chunk failed, continuing with others...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(rootBatchId, errorProgress);

      return (errorProgress, <String, String>{}, e.message);
    } catch (e) {
      _logger.error('Unexpected error in chunk $chunkId: $e');

      final errorLog = LlmExchangeLog.fromError(
        requestId: chunkId,
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: chunk.length,
        errorMessage: 'Unexpected error: $e',
      );

      final errorProgress = progress.copyWith(
        llmLogs: [...currentProgress.llmLogs, errorLog],
        phaseDetail: 'Chunk error, continuing...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(rootBatchId, errorProgress);

      return (errorProgress, <String, String>{}, e.toString());
    }
  }

  Future<(TranslationProgress, Map<String, String>)> _translateWithAutoSplit({
    required String batchId,
    required String rootBatchId,
    required List<TranslationUnit> unitsToTranslate,
    required LlmRequest llmRequest,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(List<TranslationUnit>, Map<String, String>, Set<String>)? onSubBatchTranslated,
    int depth = 0,
  }) async {
    await checkPauseOrCancel(rootBatchId);

    if (depth > 25) {
      throw TranslationOrchestrationException(
        'Batch splitting depth limit exceeded (depth=$depth). '
        'This may indicate an issue with the translation content or batch configuration.',
        batchId: batchId,
      );
    }

    final optimalBatchSize = _tokenEstimator.calculateOptimalBatchSize(
      llmRequest: llmRequest,
      units: unitsToTranslate,
      context: context,
    );

    if (unitsToTranslate.length > optimalBatchSize) {
      _logger.debug('Batch size ${unitsToTranslate.length} > optimal $optimalBatchSize, pre-splitting');

      final estimatedTokens = _tokenEstimator.estimateTokensForUnits(
        llmRequest: llmRequest,
        units: unitsToTranslate,
      );

      final splitProgress = progress.copyWith(
        phaseDetail: 'Batch too large (~$estimatedTokens tokens), auto-splitting into smaller chunks...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(rootBatchId, splitProgress);

      final warningLog = LlmExchangeLog.fromError(
        requestId: '$batchId-preemptive-split-$depth',
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: unitsToTranslate.length,
        errorMessage: 'Batch too large (${unitsToTranslate.length} units, ~$estimatedTokens tokens > 140k limit), auto-splitting to ~$optimalBatchSize units',
      );

      final midPoint = (unitsToTranslate.length / 2).ceil();
      final firstHalf = unitsToTranslate.sublist(0, midPoint);
      final secondHalf = unitsToTranslate.sublist(midPoint);

      _logger.debug('Pre-split: ${firstHalf.length} + ${secondHalf.length} units');

      final firstHalfTexts = {for (var unit in firstHalf) unit.id: unit.sourceText};
      final firstHalfRequest = llmRequest.copyWith(
        requestId: '$batchId-preempt1-depth$depth',
        texts: firstHalfTexts,
        maxTokens: _tokenEstimator.estimateMaxTokens(firstHalfTexts),
      );

      final (progressAfterFirst, firstTranslations) = await _translateWithAutoSplit(
        batchId: batchId,
        rootBatchId: rootBatchId,
        unitsToTranslate: firstHalf,
        llmRequest: firstHalfRequest,
        context: context,
        progress: progress.copyWith(llmLogs: [...currentProgress.llmLogs, warningLog]),
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
        depth: depth + 1,
      );

      await checkPauseOrCancel(rootBatchId);

      final secondHalfTexts = {for (var unit in secondHalf) unit.id: unit.sourceText};
      final secondHalfRequest = llmRequest.copyWith(
        requestId: '$batchId-preempt2-depth$depth',
        texts: secondHalfTexts,
        maxTokens: _tokenEstimator.estimateMaxTokens(secondHalfTexts),
      );

      final (progressAfterSecond, secondTranslations) = await _translateWithAutoSplit(
        batchId: batchId,
        rootBatchId: rootBatchId,
        unitsToTranslate: secondHalf,
        llmRequest: secondHalfRequest,
        context: context,
        progress: progressAfterFirst,
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
        depth: depth + 1,
      );

      return (progressAfterSecond, {...firstTranslations, ...secondTranslations});
    }

    final cancellationToken = getCancellationToken(batchId);
    final dioCancelToken = cancellationToken?.dioToken;

    final llmCallProgress = progress.copyWith(
      phaseDetail: 'Waiting ${context.providerCode ?? "LLM"} API response...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(rootBatchId, llmCallProgress);

    _logger.debug(
      'Waiting ${context.providerCode ?? "LLM"} API response for batch $batchId '
      '(${unitsToTranslate.length} units) - this may take a while for large batches...',
    );
    final apiCallStart = DateTime.now();

    final llmResult = await _retryHandler.translateWithRetry(
      llmRequest: llmRequest,
      batchId: batchId,
      dioCancelToken: dioCancelToken,
    );

    if (llmResult.isErr) {
      final error = llmResult.unwrapErr();

      final isContentFiltered = error is LlmContentFilteredException;
      final isBatchTooLarge = (error is LlmTokenLimitException) ||
          (error is LlmResponseParseException && unitsToTranslate.length > 1);
      final shouldSplit = (isBatchTooLarge || isContentFiltered) && unitsToTranslate.length > 1;

      if (shouldSplit) {
        final errorType = error is LlmTokenLimitException
            ? 'Token limit'
            : (isContentFiltered ? 'Content filtered' : 'Response parsing');

        _logger.debug('$errorType error, splitting ${unitsToTranslate.length} units');

        final warningLog = LlmExchangeLog.fromError(
          requestId: '$batchId-split-$depth',
          providerCode: context.providerId ?? 'unknown',
          modelName: context.modelId ?? 'unknown',
          unitsCount: unitsToTranslate.length,
          errorMessage: '$errorType error, auto-splitting batch (${unitsToTranslate.length} units)',
        );

        final midPoint = (unitsToTranslate.length / 2).ceil();
        final firstHalf = unitsToTranslate.sublist(0, midPoint);
        final secondHalf = unitsToTranslate.sublist(midPoint);

        _logger.debug('Split: ${firstHalf.length} + ${secondHalf.length} units');

        final firstHalfTextsErr = {for (var unit in firstHalf) unit.id: unit.sourceText};
        final firstHalfRequest = llmRequest.copyWith(
          requestId: '$batchId-part1-depth$depth',
          texts: firstHalfTextsErr,
          maxTokens: _tokenEstimator.estimateMaxTokens(firstHalfTextsErr),
        );

        final (progressAfterFirst, firstTranslations) = await _translateWithAutoSplit(
          batchId: batchId,
          rootBatchId: rootBatchId,
          unitsToTranslate: firstHalf,
          llmRequest: firstHalfRequest,
          context: context,
          progress: progress.copyWith(llmLogs: [...currentProgress.llmLogs, warningLog]),
          currentProgress: currentProgress,
          getCancellationToken: getCancellationToken,
          onProgressUpdate: onProgressUpdate,
          checkPauseOrCancel: checkPauseOrCancel,
          onSubBatchTranslated: onSubBatchTranslated,
          depth: depth + 1,
        );

        await checkPauseOrCancel(rootBatchId);

        final secondHalfTextsErr = {for (var unit in secondHalf) unit.id: unit.sourceText};
        final secondHalfRequest = llmRequest.copyWith(
          requestId: '$batchId-part2-depth$depth',
          texts: secondHalfTextsErr,
          maxTokens: _tokenEstimator.estimateMaxTokens(secondHalfTextsErr),
        );

        final (progressAfterSecond, secondTranslations) = await _translateWithAutoSplit(
          batchId: batchId,
          rootBatchId: rootBatchId,
          unitsToTranslate: secondHalf,
          llmRequest: secondHalfRequest,
          context: context,
          progress: progressAfterFirst,
          currentProgress: currentProgress,
          getCancellationToken: getCancellationToken,
          onProgressUpdate: onProgressUpdate,
          checkPauseOrCancel: checkPauseOrCancel,
          onSubBatchTranslated: onSubBatchTranslated,
          depth: depth + 1,
        );

        return (progressAfterSecond, {...firstTranslations, ...secondTranslations});
      }

      if (error is LlmResponseParseException && unitsToTranslate.length == 1 && depth < 2) {
        final unit = unitsToTranslate.first;
        final currentMaxTokens = llmRequest.maxTokens ?? 4000;
        final newMaxTokens = (currentMaxTokens * 2).clamp(currentMaxTokens + 2000, 80000);

        _logger.debug(
          'Parse error for unit "${unit.key}" - retrying with maxTokens: '
          '$currentMaxTokens -> $newMaxTokens (likely truncated response)',
        );

        final retryLog = LlmExchangeLog.fromError(
          requestId: '$batchId-retry-$depth',
          providerCode: context.providerId ?? 'unknown',
          modelName: context.modelId ?? 'unknown',
          unitsCount: 1,
          errorMessage: 'Response truncated for "${unit.key}", retrying with maxTokens=$newMaxTokens',
        );

        final retryRequest = llmRequest.copyWith(
          requestId: '$batchId-retry-depth$depth',
          maxTokens: newMaxTokens,
        );

        return _translateWithAutoSplit(
          batchId: batchId,
          rootBatchId: rootBatchId,
          unitsToTranslate: unitsToTranslate,
          llmRequest: retryRequest,
          context: context,
          progress: progress.copyWith(llmLogs: [...currentProgress.llmLogs, retryLog]),
          currentProgress: currentProgress,
          getCancellationToken: getCancellationToken,
          onProgressUpdate: onProgressUpdate,
          checkPauseOrCancel: checkPauseOrCancel,
          onSubBatchTranslated: onSubBatchTranslated,
          depth: depth + 1,
        );
      }

      if (isContentFiltered && unitsToTranslate.length == 1) {
        final unit = unitsToTranslate.first;
        _logger.warning(
          'Content filtered for unit "${unit.key}" - skipping. '
          'Consider using a different provider (Claude/DeepL) for this content.',
        );

        final filterLog = LlmExchangeLog.fromError(
          requestId: '$batchId-filtered',
          providerCode: context.providerId ?? 'unknown',
          modelName: context.modelId ?? 'unknown',
          unitsCount: 1,
          errorMessage: 'Content filtered by provider moderation for key "${unit.key}". '
              'The source text may contain content that violates the provider\'s usage policies.',
        );

        final filterProgress = progress.copyWith(
          phaseDetail: 'Skipped filtered content: "${unit.key}"',
          llmLogs: [...currentProgress.llmLogs, filterLog],
          failedUnits: currentProgress.failedUnits + 1,
          timestamp: DateTime.now(),
        );
        onProgressUpdate(rootBatchId, filterProgress);

        return (filterProgress, <String, String>{});
      }

      final errorLog = LlmExchangeLog.fromError(
        requestId: batchId,
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: unitsToTranslate.length,
        errorMessage: error.toString(),
      );

      final updatedLogs = [...currentProgress.llmLogs, errorLog];

      progress = progress.copyWith(
        llmLogs: updatedLogs,
        timestamp: DateTime.now(),
      );

      throw TranslationOrchestrationException(
        'LLM translation failed: $error',
        batchId: batchId,
      );
    }

    final llmResponse = llmResult.unwrap();

    final translations = <String, String>{};
    for (var i = 0; i < unitsToTranslate.length && i < llmResponse.translations.length; i++) {
      final unit = unitsToTranslate[i];
      final translatedText = llmResponse.translations.values.elementAt(i);
      translations[unit.id] = TranslationTextUtils.normalizeTranslation(translatedText);
    }

    final apiCallDuration = DateTime.now().difference(apiCallStart);
    _logger.debug(
      'LLM API call completed in ${apiCallDuration.inSeconds}s: '
      '${llmResponse.translations.length} units, ${llmResponse.totalTokens} tokens',
    );

    final completionProgress = progress.copyWith(
      phaseDetail: 'LLM returned ${llmResponse.translations.length} translations (${llmResponse.totalTokens} tokens used)',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(rootBatchId, completionProgress);

    if (onSubBatchTranslated != null && translations.isNotEmpty) {
      try {
        await onSubBatchTranslated(unitsToTranslate, translations, <String>{});
      } catch (e) {
        _logger.warning('Progressive save failed: $e');
      }
    }

    final successLog = LlmExchangeLog.fromResponse(
      requestId: llmRequest.requestId,
      providerCode: llmResponse.providerCode,
      modelName: llmResponse.modelName,
      unitsCount: llmResponse.translations.length,
      inputTokens: llmResponse.inputTokens,
      outputTokens: llmResponse.outputTokens,
      processingTimeMs: llmResponse.processingTimeMs,
      sampleTranslation: llmResponse.translations.values.isNotEmpty
          ? llmResponse.translations.values.first.substring(
              0,
              llmResponse.translations.values.first.length > 50
                  ? 50
                  : llmResponse.translations.values.first.length,
            )
          : null,
    );

    final updatedLogs = [...currentProgress.llmLogs, successLog];

    final updatedProgress = progress.copyWith(
      currentPhase: TranslationPhase.llmTranslation,
      phaseDetail: 'Chunk saved (${translations.length} units), processing continues...',
      tokensUsed: currentProgress.tokensUsed + llmResponse.totalTokens,
      llmLogs: updatedLogs,
      timestamp: DateTime.now(),
    );

    onProgressUpdate(rootBatchId, updatedProgress);

    return (updatedProgress, translations);
  }
}
