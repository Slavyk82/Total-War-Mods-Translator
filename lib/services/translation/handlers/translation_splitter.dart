import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/utils/translation_text_utils.dart';
import 'llm_token_estimator.dart';
import 'llm_retry_handler.dart';
import 'translation_error_recovery.dart';

/// Callback type for progress updates.
typedef ProgressUpdateCallback = void Function(
    String batchId, TranslationProgress progress);

/// Callback type for sub-batch translation completion.
typedef SubBatchTranslatedCallback = Future<void> Function(
  List<TranslationUnit> units,
  Map<String, String> translations,
  Set<String> cachedUnitIds,
);

/// Handles automatic batch splitting for LLM translation.
///
/// Responsibilities:
/// - Split batches that exceed token limits
/// - Delegate error handling to TranslationErrorRecovery
/// - Process split batches recursively
/// - Execute LLM calls via LlmRetryHandler
class TranslationSplitter {
  final LlmTokenEstimator _tokenEstimator;
  final LlmRetryHandler _retryHandler;
  final LoggingService _logger;
  late final TranslationErrorRecovery _errorRecovery;

  /// Maximum recursion depth for batch splitting.
  static const int maxSplitDepth = 25;

  TranslationSplitter({
    required LlmTokenEstimator tokenEstimator,
    required LlmRetryHandler retryHandler,
    required LoggingService logger,
  })  : _tokenEstimator = tokenEstimator,
        _retryHandler = retryHandler,
        _logger = logger {
    _errorRecovery = TranslationErrorRecovery(
      tokenEstimator: tokenEstimator,
      logger: logger,
    );
  }

  /// Translate units with automatic batch splitting when needed.
  ///
  /// Returns tuple of (updated progress, translations map).
  ///
  /// Automatically splits batches when:
  /// - Batch size exceeds optimal token limit
  /// - Token limit error is returned by LLM
  /// - Content filtering error requires isolation
  /// - Response parsing fails (may indicate truncation)
  Future<(TranslationProgress, Map<String, String>)> translateWithAutoSplit({
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
    await checkPauseOrCancel(rootBatchId);

    if (depth > maxSplitDepth) {
      throw TranslationOrchestrationException(
        'Batch splitting depth limit exceeded (depth=$depth). '
        'This may indicate an issue with the translation content or batch configuration.',
        batchId: batchId,
      );
    }

    // Check if pre-emptive split is needed based on optimal batch size
    final optimalBatchSize = _tokenEstimator.calculateOptimalBatchSize(
      llmRequest: llmRequest,
      units: unitsToTranslate,
      context: context,
    );

    if (unitsToTranslate.length > optimalBatchSize) {
      _logger.debug(
          'Batch size ${unitsToTranslate.length} > optimal $optimalBatchSize, pre-splitting');

      final estimatedTokens = _tokenEstimator.estimateTokensForUnits(
        llmRequest: llmRequest,
        units: unitsToTranslate,
      );

      return _errorRecovery.preemptiveSplit(
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
        optimalBatchSize: optimalBatchSize,
        estimatedTokens: estimatedTokens,
        translateWithAutoSplit: _createRecursiveCallback(),
      );
    }

    // Execute LLM call
    return _executeLlmCall(
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
    );
  }

  /// Create a callback for recursive translation calls.
  TranslateWithAutoSplitCallback _createRecursiveCallback() {
    return ({
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
    }) {
      return translateWithAutoSplit(
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
      );
    };
  }

  /// Execute the actual LLM call and handle errors.
  Future<(TranslationProgress, Map<String, String>)> _executeLlmCall({
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
  }) async {
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
      return _errorRecovery.handleLlmError(
        error: llmResult.unwrapErr(),
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
        translateWithAutoSplit: _createRecursiveCallback(),
      );
    }

    // Process successful response
    return _processSuccessfulResponse(
      llmResponse: llmResult.unwrap(),
      batchId: batchId,
      rootBatchId: rootBatchId,
      unitsToTranslate: unitsToTranslate,
      llmRequest: llmRequest,
      context: context,
      progress: progress,
      currentProgress: currentProgress,
      onProgressUpdate: onProgressUpdate,
      onSubBatchTranslated: onSubBatchTranslated,
      apiCallStart: apiCallStart,
    );
  }

  /// Process successful LLM response.
  Future<(TranslationProgress, Map<String, String>)> _processSuccessfulResponse({
    required dynamic llmResponse,
    required String batchId,
    required String rootBatchId,
    required List<TranslationUnit> unitsToTranslate,
    required LlmRequest llmRequest,
    required TranslationContext context,
    required TranslationProgress progress,
    required TranslationProgress currentProgress,
    required ProgressUpdateCallback onProgressUpdate,
    SubBatchTranslatedCallback? onSubBatchTranslated,
    required DateTime apiCallStart,
  }) async {
    final translations = <String, String>{};
    for (var i = 0;
        i < unitsToTranslate.length && i < llmResponse.translations.length;
        i++) {
      final unit = unitsToTranslate[i];
      final translatedText = llmResponse.translations.values.elementAt(i);
      translations[unit.id] =
          TranslationTextUtils.normalizeTranslation(translatedText);
    }

    final apiCallDuration = DateTime.now().difference(apiCallStart);
    _logger.debug(
      'LLM API call completed in ${apiCallDuration.inSeconds}s: '
      '${llmResponse.translations.length} units, ${llmResponse.totalTokens} tokens',
    );

    final completionProgress = progress.copyWith(
      phaseDetail:
          'LLM returned ${llmResponse.translations.length} translations (${llmResponse.totalTokens} tokens used)',
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

    final totalTokens = llmResponse.totalTokens as int;
    final updatedProgress = progress.copyWith(
      currentPhase: TranslationPhase.llmTranslation,
      phaseDetail: 'Chunk saved (${translations.length} units), processing continues...',
      tokensUsed: currentProgress.tokensUsed + totalTokens,
      llmLogs: updatedLogs,
      timestamp: DateTime.now(),
    );

    onProgressUpdate(rootBatchId, updatedProgress);

    return (updatedProgress, translations);
  }
}
