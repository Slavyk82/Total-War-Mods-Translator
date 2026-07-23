import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'llm_token_estimator.dart';
import 'llm_cache_manager.dart';
import 'translation_splitter.dart';

/// Handles parallel batch processing for LLM translation.
///
/// Responsibilities:
/// - Split work into parallel chunks
/// - Execute chunks concurrently
/// - Aggregate results from all chunks
/// - Handle partial failures gracefully
class ParallelBatchProcessor {
  final LlmTokenEstimator _tokenEstimator;
  final LlmCacheManager _cacheManager;
  final TranslationSplitter _translationSplitter;
  final ILoggingService _logger;

  ParallelBatchProcessor({
    required LlmTokenEstimator tokenEstimator,
    required LlmCacheManager cacheManager,
    required TranslationSplitter translationSplitter,
    required ILoggingService logger,
  })  : _tokenEstimator = tokenEstimator,
        _cacheManager = cacheManager,
        _translationSplitter = translationSplitter,
        _logger = logger;

  /// Process units in parallel batches.
  ///
  /// Returns tuple of (updated progress, translations map, cached unit IDs).
  Future<(TranslationProgress, Map<String, String>, Set<String>)>
      processParallelBatches({
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
    await checkPauseOrCancel(batchId);

    final parallelBatches = context.parallelBatches;
    var updatedProgress = progress.copyWith(
      phaseDetail:
          'Splitting into $parallelBatches parallel batches for faster processing...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, updatedProgress);

    _logger.debug('Splitting into $parallelBatches parallel batches');

    // Create chunks
    final chunks = _createChunks(unitsForLlm, parallelBatches);
    _logger.debug('Created ${chunks.length} parallel chunks');

    // Track saved unit IDs across all chunks
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

    updatedProgress = updatedProgress.copyWith(
      phaseDetail:
          'Waiting LLM API response (${chunks.length} parallel requests)...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, updatedProgress);

    // Create progress update callback for parallel chunks
    void parallelProgressUpdate(String id, TranslationProgress chunkProgress) {
      final stableProgress = updatedProgress.copyWith(
        phaseDetail: chunkProgress.phaseDetail,
        currentPhase: chunkProgress.currentPhase,
        llmLogs: chunkProgress.llmLogs,
        timestamp: chunkProgress.timestamp,
      );
      onProgressUpdate(id, stableProgress);
    }

    // Execute all chunks in parallel
    final results = await _executeChunksInParallel(
      chunks: chunks,
      batchId: batchId,
      builtPrompt: builtPrompt,
      context: context,
      progress: updatedProgress,
      currentProgress: currentProgress,
      getCancellationToken: getCancellationToken,
      onProgressUpdate: parallelProgressUpdate,
      checkPauseOrCancel: checkPauseOrCancel,
      onSubBatchTranslated: trackingSaveCallback,
    );

    // Aggregate results
    final (
      llmTranslations,
      chunkErrors,
      totalTokensUsed,
      totalFailedUnits,
      allLlmLogs
    ) = _aggregateResults(results, currentProgress);

    if (chunkErrors.isNotEmpty) {
      _logger.warning(
        'Some chunks failed during parallel translation: ${chunkErrors.length} errors. '
        'Successfully translated ${llmTranslations.length} units.',
      );
    }

    _logger.debug(
        'Parallel translation completed: ${llmTranslations.length} translations');

    final completionProgress = updatedProgress.copyWith(
      phaseDetail:
          'LLM translation complete (${llmTranslations.length} translations received)',
      llmLogs: allLlmLogs,
      timestamp: DateTime.now(),
    );
    parallelProgressUpdate(batchId, completionProgress);

    var finalProgress = updatedProgress.copyWith(
      tokensUsed: totalTokensUsed,
      failedUnits: totalFailedUnits,
      llmLogs: allLlmLogs,
      timestamp: DateTime.now(),
    );

    // Update cache and apply duplicates
    await _cacheManager.updateCacheAndApplyDuplicates(
      llmTranslations: llmTranslations,
      sourceTextToUnits: cacheResult.sourceTextToUnits,
      registeredHashes: cacheResult.registeredHashes,
      allTranslations: cacheResult.allTranslations,
      cachedUnitIds: cacheResult.cachedUnitIds,
      context: context,
    );

    // Save any unsaved duplicate translations
    if (onSubBatchTranslated != null && cacheResult.allTranslations.isNotEmpty) {
      await _saveUnsavedDuplicates(
        savedUnitIds: savedUnitIds,
        allTranslations: cacheResult.allTranslations,
        unitsToTranslate: unitsToTranslate,
        onSubBatchTranslated: onSubBatchTranslated,
      );
    }

    return (finalProgress, cacheResult.allTranslations, cacheResult.cachedUnitIds);
  }

  /// Create evenly-sized chunks from units.
  List<List<TranslationUnit>> _createChunks(
    List<TranslationUnit> units,
    int numChunks,
  ) {
    final chunkSize = (units.length / numChunks).ceil();
    final chunks = <List<TranslationUnit>>[];

    for (var i = 0; i < units.length; i += chunkSize) {
      final end = (i + chunkSize < units.length) ? i + chunkSize : units.length;
      chunks.add(units.sublist(i, end));
    }

    return chunks;
  }

  /// Execute all chunks in parallel.
  Future<List<(TranslationProgress, Map<String, String>, String?)>>
      _executeChunksInParallel({
    required List<List<TranslationUnit>> chunks,
    required String batchId,
    required dynamic builtPrompt,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress)
        onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    SubBatchTranslatedCallback? onSubBatchTranslated,
  }) async {
    final futures =
        <Future<(TranslationProgress, Map<String, String>, String?)>>[];

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
        glossaryId: context.glossaryId,
        sourceLanguage: context.sourceLanguage,
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
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
      ));
    }

    return Future.wait(futures);
  }

  /// Translate a single chunk with error handling.
  Future<(TranslationProgress, Map<String, String>, String?)>
      _translateChunkWithErrorHandling({
    required String chunkId,
    required String rootBatchId,
    required List<TranslationUnit> chunk,
    required LlmRequest llmRequest,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress)
        onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    SubBatchTranslatedCallback? onSubBatchTranslated,
  }) async {
    // Track which of THIS chunk's units were already persisted (via
    // onSubBatchTranslated) before a later sub-batch failed. When an
    // auto-split chunk saves its first half then dies on the second half, only
    // the not-yet-saved units are real failures - the saved ones are already
    // on disk (and counted successful), so counting the whole chunk as failed
    // would double-count them.
    final savedInThisChunk = <String>{};
    SubBatchTranslatedCallback? countingCallback;
    if (onSubBatchTranslated != null) {
      countingCallback = (units, translations, cachedIds) async {
        await onSubBatchTranslated(units, translations, cachedIds);
        savedInThisChunk.addAll(translations.keys);
      };
    }

    int unsavedFailedCount() =>
        (chunk.length - savedInThisChunk.length).clamp(0, chunk.length);

    try {
      final (resultProgress, translations) =
          await _translationSplitter.translateWithAutoSplit(
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
        onSubBatchTranslated: countingCallback,
      );
      return (resultProgress, translations, null);
    } on TranslationOrchestrationException catch (e) {
      final failedInChunk = unsavedFailedCount();
      _logger.warning(
          'Chunk $chunkId failed: ${e.message}. Skipping $failedInChunk units.');

      final errorLog = LlmExchangeLog.fromError(
        requestId: chunkId,
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: failedInChunk,
        errorMessage: 'Chunk skipped: ${e.message}',
      );

      final errorProgress = progress.copyWith(
        llmLogs: [...currentProgress.llmLogs, errorLog],
        // Count only the NOT-yet-saved units of the dropped chunk as failed.
        // _aggregateResults diffs each chunk's returned failedUnits against the
        // shared currentProgress baseline, so building on that baseline makes
        // the delta equal the unsaved count. (Units already persisted via
        // onSubBatchTranslated are counted successful; counting the whole chunk
        // here would double-count them as failed too.) The delta stays > 0 as
        // long as anything was actually lost, so the batch is never wrongly
        // reported as fully completed.
        failedUnits: currentProgress.failedUnits + failedInChunk,
        phaseDetail: 'Chunk failed, continuing with others...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(rootBatchId, errorProgress);

      return (errorProgress, <String, String>{}, e.message);
    } catch (e) {
      final failedInChunk = unsavedFailedCount();
      _logger.error('Unexpected error in chunk $chunkId: $e');

      final errorLog = LlmExchangeLog.fromError(
        requestId: chunkId,
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: failedInChunk,
        errorMessage: 'Unexpected error: $e',
      );

      final errorProgress = progress.copyWith(
        llmLogs: [...currentProgress.llmLogs, errorLog],
        // See the TranslationOrchestrationException branch above: count only
        // the not-yet-saved units as failed so already-persisted units are not
        // double-counted, while the aggregate delta stays non-zero whenever
        // work was actually lost.
        failedUnits: currentProgress.failedUnits + failedInChunk,
        phaseDetail: 'Chunk error, continuing...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(rootBatchId, errorProgress);

      return (errorProgress, <String, String>{}, e.toString());
    }
  }

  /// Aggregate results from all parallel chunks.
  ///
  /// Returns (translations, chunk errors, total tokens used, total failed
  /// units, merged LLM logs). Token and failed-unit totals are aggregated
  /// here because per-chunk progress emissions are rebased onto a stable
  /// snapshot that strips those counters (to avoid parallel counter races),
  /// so the aggregate computed here is the only authoritative source.
  (Map<String, String>, List<String>, int, int, List<LlmExchangeLog>)
      _aggregateResults(
    List<(TranslationProgress, Map<String, String>, String?)> results,
    TranslationProgress currentProgress,
  ) {
    final llmTranslations = <String, String>{};
    final chunkErrors = <String>[];
    int totalTokensUsed = currentProgress.tokensUsed;
    // Every chunk computes failedUnits relative to the shared pre-LLM
    // `currentProgress` baseline, so the per-chunk delta is the number of
    // failures that chunk itself observed (e.g. units omitted from the LLM
    // response). When a chunk auto-splits, _splitAndProcess chains the
    // baseline through both halves (each half builds on the previous half's
    // progress), so the chunk's returned progress is cumulative and the
    // delta below covers every sub-batch. Sum the deltas on top of the
    // baseline.
    int totalFailedUnits = currentProgress.failedUnits;
    final allLlmLogs = <LlmExchangeLog>[...currentProgress.llmLogs];

    for (final (chunkProgress, chunkTranslations, chunkError) in results) {
      llmTranslations.addAll(chunkTranslations);
      if (chunkError != null) {
        chunkErrors.add(chunkError);
      }
      final chunkFailedDelta =
          chunkProgress.failedUnits - currentProgress.failedUnits;
      if (chunkFailedDelta > 0) {
        totalFailedUnits += chunkFailedDelta;
      }
      final newLogs = chunkProgress.llmLogs
          .where((log) =>
              !allLlmLogs.any((existing) => existing.requestId == log.requestId))
          .toList();
      allLlmLogs.addAll(newLogs);
      for (final log in newLogs) {
        totalTokensUsed += log.inputTokens + log.outputTokens;
      }
    }

    return (
      llmTranslations,
      chunkErrors,
      totalTokensUsed,
      totalFailedUnits,
      allLlmLogs
    );
  }

  /// Save any duplicate translations that weren't saved during chunk processing.
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
