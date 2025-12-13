import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'llm_token_estimator.dart';

/// Callback type for progress updates.
typedef ProgressUpdateCallback = void Function(
    String batchId, TranslationProgress progress);

/// Callback type for sub-batch translation completion.
typedef SubBatchTranslatedCallback = Future<void> Function(
  List<TranslationUnit> units,
  Map<String, String> translations,
  Set<String> cachedUnitIds,
);

/// Callback type for recursive translation with auto-split.
typedef TranslateWithAutoSplitCallback
    = Future<(TranslationProgress, Map<String, String>)> Function({
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
  int depth,
});

/// Handles error recovery strategies for LLM translation.
///
/// Responsibilities:
/// - Determine if errors are recoverable by splitting
/// - Handle content filtered units
/// - Retry with increased token limits
/// - Log fatal errors appropriately
class TranslationErrorRecovery {
  final LlmTokenEstimator _tokenEstimator;
  final LoggingService _logger;

  TranslationErrorRecovery({
    required LlmTokenEstimator tokenEstimator,
    required LoggingService logger,
  })  : _tokenEstimator = tokenEstimator,
        _logger = logger;

  /// Handle LLM errors and determine recovery strategy.
  ///
  /// Returns tuple of (progress, translations) if recovery is possible,
  /// or throws if the error is fatal.
  Future<(TranslationProgress, Map<String, String>)> handleLlmError({
    required LlmServiceException error,
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
    required int depth,
    required TranslateWithAutoSplitCallback translateWithAutoSplit,
  }) async {
    final isContentFiltered = error is LlmContentFilteredException;
    final isBatchTooLarge = (error is LlmTokenLimitException) ||
        (error is LlmResponseParseException && unitsToTranslate.length > 1);
    final shouldSplit =
        (isBatchTooLarge || isContentFiltered) && unitsToTranslate.length > 1;

    if (shouldSplit) {
      return _handleSplittableError(
        error: error,
        batchId: batchId,
        rootBatchId: rootBatchId,
        unitsToTranslate: unitsToTranslate,
        llmRequest: llmRequest,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
        depth: depth,
        isContentFiltered: isContentFiltered,
        translateWithAutoSplit: translateWithAutoSplit,
      );
    }

    // Handle single unit parse error - retry with more tokens
    if (error is LlmResponseParseException &&
        unitsToTranslate.length == 1 &&
        depth < 2) {
      return _retryWithMoreTokens(
        batchId: batchId,
        rootBatchId: rootBatchId,
        unitsToTranslate: unitsToTranslate,
        llmRequest: llmRequest,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
        depth: depth,
        translateWithAutoSplit: translateWithAutoSplit,
      );
    }

    // Handle single unit content filtering - skip the unit
    if (isContentFiltered && unitsToTranslate.length == 1) {
      return _handleContentFilteredUnit(
        unit: unitsToTranslate.first,
        batchId: batchId,
        rootBatchId: rootBatchId,
        context: context,
        progress: progress,
        currentProgress: currentProgress,
        onProgressUpdate: onProgressUpdate,
      );
    }

    // Non-recoverable error
    return _handleFatalError(
      error: error,
      batchId: batchId,
      context: context,
      unitsToTranslate: unitsToTranslate,
    );
  }

  /// Handle errors that can be recovered by splitting the batch.
  Future<(TranslationProgress, Map<String, String>)> _handleSplittableError({
    required LlmServiceException error,
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
    required int depth,
    required bool isContentFiltered,
    required TranslateWithAutoSplitCallback translateWithAutoSplit,
  }) async {
    final errorType = error is LlmTokenLimitException
        ? 'Token limit'
        : (isContentFiltered ? 'Content filtered' : 'Response parsing');

    _logger.debug('$errorType error, splitting ${unitsToTranslate.length} units');

    final warningLog = LlmExchangeLog.fromError(
      requestId: '$batchId-split-$depth',
      providerCode: context.providerId ?? 'unknown',
      modelName: context.modelId ?? 'unknown',
      unitsCount: unitsToTranslate.length,
      errorMessage:
          '$errorType error, auto-splitting batch (${unitsToTranslate.length} units)',
    );

    return _splitAndProcess(
      batchId: batchId,
      rootBatchId: rootBatchId,
      unitsToTranslate: unitsToTranslate,
      llmRequest: llmRequest,
      context: context,
      progress: progress.copyWith(llmLogs: [...currentProgress.llmLogs, warningLog]),
      currentProgress: currentProgress,
      getCancellationToken: getCancellationToken,
      onProgressUpdate: onProgressUpdate,
      checkPauseOrCancel: checkPauseOrCancel,
      onSubBatchTranslated: onSubBatchTranslated,
      depth: depth,
      splitPrefix: 'part',
      translateWithAutoSplit: translateWithAutoSplit,
    );
  }

  /// Split batch in half and process both halves.
  Future<(TranslationProgress, Map<String, String>)> _splitAndProcess({
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
    required int depth,
    required String splitPrefix,
    required TranslateWithAutoSplitCallback translateWithAutoSplit,
  }) async {
    final midPoint = (unitsToTranslate.length / 2).ceil();
    final firstHalf = unitsToTranslate.sublist(0, midPoint);
    final secondHalf = unitsToTranslate.sublist(midPoint);

    _logger.debug('Split: ${firstHalf.length} + ${secondHalf.length} units');

    // Process first half
    final firstHalfTexts = {for (var unit in firstHalf) unit.id: unit.sourceText};
    final firstHalfRequest = llmRequest.copyWith(
      requestId: '$batchId-${splitPrefix}1-depth$depth',
      texts: firstHalfTexts,
      maxTokens: _tokenEstimator.estimateMaxTokens(firstHalfTexts),
    );

    final (progressAfterFirst, firstTranslations) = await translateWithAutoSplit(
      batchId: batchId,
      rootBatchId: rootBatchId,
      unitsToTranslate: firstHalf,
      llmRequest: firstHalfRequest,
      context: context,
      progress: progress,
      currentProgress: currentProgress,
      getCancellationToken: getCancellationToken,
      onProgressUpdate: onProgressUpdate,
      checkPauseOrCancel: checkPauseOrCancel,
      onSubBatchTranslated: onSubBatchTranslated,
      depth: depth + 1,
    );

    await checkPauseOrCancel(rootBatchId);

    // Process second half
    final secondHalfTexts = {for (var unit in secondHalf) unit.id: unit.sourceText};
    final secondHalfRequest = llmRequest.copyWith(
      requestId: '$batchId-${splitPrefix}2-depth$depth',
      texts: secondHalfTexts,
      maxTokens: _tokenEstimator.estimateMaxTokens(secondHalfTexts),
    );

    final (progressAfterSecond, secondTranslations) = await translateWithAutoSplit(
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

  /// Retry translation with increased max tokens for truncated response.
  Future<(TranslationProgress, Map<String, String>)> _retryWithMoreTokens({
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
    required int depth,
    required TranslateWithAutoSplitCallback translateWithAutoSplit,
  }) async {
    final unit = unitsToTranslate.first;
    final currentMaxTokens = llmRequest.maxTokens ?? 4000;
    final newMaxTokens =
        (currentMaxTokens * 2).clamp(currentMaxTokens + 2000, 80000);

    _logger.debug(
      'Parse error for unit "${unit.key}" - retrying with maxTokens: '
      '$currentMaxTokens -> $newMaxTokens (likely truncated response)',
    );

    final retryLog = LlmExchangeLog.fromError(
      requestId: '$batchId-retry-$depth',
      providerCode: context.providerId ?? 'unknown',
      modelName: context.modelId ?? 'unknown',
      unitsCount: 1,
      errorMessage:
          'Response truncated for "${unit.key}", retrying with maxTokens=$newMaxTokens',
    );

    final retryRequest = llmRequest.copyWith(
      requestId: '$batchId-retry-depth$depth',
      maxTokens: newMaxTokens,
    );

    return translateWithAutoSplit(
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

  /// Handle content filtered single unit - skip it.
  (TranslationProgress, Map<String, String>) _handleContentFilteredUnit({
    required TranslationUnit unit,
    required String batchId,
    required String rootBatchId,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required ProgressUpdateCallback onProgressUpdate,
  }) {
    _logger.warning(
      'Content filtered for unit "${unit.key}" - skipping. '
      'Consider using a different provider (Claude/DeepL) for this content.',
    );

    final filterLog = LlmExchangeLog.fromError(
      requestId: '$batchId-filtered',
      providerCode: context.providerId ?? 'unknown',
      modelName: context.modelId ?? 'unknown',
      unitsCount: 1,
      errorMessage:
          'Content filtered by provider moderation for key "${unit.key}". '
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

  /// Handle non-recoverable LLM error.
  (TranslationProgress, Map<String, String>) _handleFatalError({
    required LlmServiceException error,
    required String batchId,
    required TranslationContext context,
    required List<TranslationUnit> unitsToTranslate,
  }) {
    final errorLog = LlmExchangeLog.fromError(
      requestId: batchId,
      providerCode: context.providerId ?? 'unknown',
      modelName: context.modelId ?? 'unknown',
      unitsCount: unitsToTranslate.length,
      errorMessage: error.toString(),
    );

    // Log is created for tracking but exception is thrown immediately
    _logger.debug('Fatal LLM error logged: ${errorLog.errorMessage}');

    throw TranslationOrchestrationException(
      'LLM translation failed: $error',
      batchId: batchId,
    );
  }

  /// Pre-emptively split batch before LLM call based on optimal size.
  Future<(TranslationProgress, Map<String, String>)> preemptiveSplit({
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
    required int depth,
    required int optimalBatchSize,
    required int estimatedTokens,
    required TranslateWithAutoSplitCallback translateWithAutoSplit,
  }) async {
    final splitProgress = progress.copyWith(
      phaseDetail:
          'Batch too large (~$estimatedTokens tokens), auto-splitting into smaller chunks...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(rootBatchId, splitProgress);

    final warningLog = LlmExchangeLog.fromError(
      requestId: '$batchId-preemptive-split-$depth',
      providerCode: context.providerId ?? 'unknown',
      modelName: context.modelId ?? 'unknown',
      unitsCount: unitsToTranslate.length,
      errorMessage:
          'Batch too large (${unitsToTranslate.length} units, ~$estimatedTokens tokens > 140k limit), auto-splitting to ~$optimalBatchSize units',
    );

    return _splitAndProcess(
      batchId: batchId,
      rootBatchId: rootBatchId,
      unitsToTranslate: unitsToTranslate,
      llmRequest: llmRequest,
      context: context,
      progress: progress.copyWith(llmLogs: [...currentProgress.llmLogs, warningLog]),
      currentProgress: currentProgress,
      getCancellationToken: getCancellationToken,
      onProgressUpdate: onProgressUpdate,
      checkPauseOrCancel: checkPauseOrCancel,
      onSubBatchTranslated: onSubBatchTranslated,
      depth: depth,
      splitPrefix: 'preempt',
      translateWithAutoSplit: translateWithAutoSplit,
    );
  }
}
