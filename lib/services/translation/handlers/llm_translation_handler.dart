import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';

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
  final TokenCalculator _tokenCalculator = TokenCalculator();

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
  /// 
  /// [onSubBatchTranslated] is called after each successful LLM sub-batch
  /// to allow progressive saving. This prevents data loss on failures.
  /// 
  /// [checkPauseOrCancel] is called with the root batchId to check for
  /// stop/cancel requests before starting new work.
  Future<(TranslationProgress, Map<String, String>)> performTranslation({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Future<bool> Function(TranslationUnit unit, TranslationContext context) isUnitTranslated,
    required Function(String batchId) getCancellationToken,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    Future<void> Function(List<TranslationUnit> units, Map<String, String> translations)? onSubBatchTranslated,
  }) async {
    // Get units that still need translation (not matched by TM)
    final unitsToTranslate = <TranslationUnit>[];
    for (final unit in units) {
      if (!await isUnitTranslated(unit, context)) {
        unitsToTranslate.add(unit);
      }
    }

    if (unitsToTranslate.isEmpty) {
      return (currentProgress, <String, String>{});
    }

    _logger.info('LLM translation: ${unitsToTranslate.length} units via ${context.providerId ?? "default"}/${context.modelId ?? "default"}');

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.buildingPrompt,
      phaseDetail: 'Building translation prompt with context and examples...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    // Build prompt with TM examples (few-shot learning)
    progress = progress.copyWith(
      phaseDetail: 'Loading few-shot examples from Translation Memory...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);
    
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
      phaseDetail: 'Starting LLM translation (${unitsToTranslate.length} units via ${context.providerCode ?? "default"})...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    // Split units into parallel chunks if parallelBatches > 1
    final parallelBatches = context.parallelBatches;
    if (parallelBatches > 1 && unitsToTranslate.length > parallelBatches) {
      // Check cancellation before starting parallel processing
      await checkPauseOrCancel(batchId);
      
      progress = progress.copyWith(
        phaseDetail: 'Splitting into $parallelBatches parallel batches for faster processing...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);
      
      _logger.debug('Splitting into $parallelBatches parallel batches');

      // Calculate chunk size
      final chunkSize = (unitsToTranslate.length / parallelBatches).ceil();
      final chunks = <List<TranslationUnit>>[];
      
      for (var i = 0; i < unitsToTranslate.length; i += chunkSize) {
        final end = (i + chunkSize < unitsToTranslate.length)
            ? i + chunkSize
            : unitsToTranslate.length;
        chunks.add(unitsToTranslate.sublist(i, end));
      }

      _logger.debug('Created ${chunks.length} parallel chunks');

      // Process chunks in parallel
      final futures = <Future<(TranslationProgress, Map<String, String>)>>[];
      
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final chunkId = '$batchId-parallel-$i';
        
        // Create LLM request for this chunk
        final textsMap = <String, String>{};
        for (final unit in chunk) {
          textsMap[unit.id] = unit.sourceText;
        }

        final estimatedResponseTokens = (chunk.length * 120) + 500;
        final maxTokens = estimatedResponseTokens.clamp(1000, 8000);

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

        futures.add(_translateWithAutoSplit(
          batchId: chunkId,
          rootBatchId: batchId,
          unitsToTranslate: chunk,
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

      // Wait for all parallel batches to complete, but don't fail on first error
      final results = await Future.wait(futures, eagerError: false);

      // Merge results
      var finalProgress = progress;
      final allTranslations = <String, String>{};
      
      for (final (chunkProgress, chunkTranslations) in results) {
        finalProgress = chunkProgress;
        allTranslations.addAll(chunkTranslations);
      }

      _logger.debug('Parallel translation completed: ${allTranslations.length} translations');

      return (finalProgress, allTranslations);
    }

    // Single batch processing (parallelBatches == 1 or too few units)
    final textsMap = <String, String>{};
    for (final unit in unitsToTranslate) {
      textsMap[unit.id] = unit.sourceText;
    }

    final estimatedResponseTokens = (unitsToTranslate.length * 120) + 500;
    final maxTokens = estimatedResponseTokens.clamp(1000, 8000);

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

    final (finalProgress, translations) = await _translateWithAutoSplit(
      batchId: batchId,
      rootBatchId: batchId,
      unitsToTranslate: unitsToTranslate,
      llmRequest: llmRequest,
      context: context,
      progress: progress,
      currentProgress: currentProgress,
      getCancellationToken: getCancellationToken,
      onProgressUpdate: onProgressUpdate,
      checkPauseOrCancel: checkPauseOrCancel,
      onSubBatchTranslated: onSubBatchTranslated,
    );

    return (finalProgress, translations);
  }

  /// Translate with automatic batch splitting if token limit is exceeded
  ///
  /// Proactively splits batches that are too large, then attempts translation.
  /// If token limit or parsing errors occur, automatically splits and retries recursively.
  /// Calls [onSubBatchTranslated] after each successful LLM call for progressive saving.
  /// 
  /// [rootBatchId] is used for cancellation checks - always check the root batch,
  /// not the sub-batch IDs derived from splits.
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
    Future<void> Function(List<TranslationUnit> units, Map<String, String> translations)? onSubBatchTranslated,
    int depth = 0,
  }) async {
    // Check cancellation before doing any work (use root batchId, not sub-batch)
    await checkPauseOrCancel(rootBatchId);
    
    // Safety limit to prevent infinite recursion
    if (depth > 10) {
      throw TranslationOrchestrationException(
        'Batch splitting depth limit exceeded. Units may be too large to translate individually.',
        batchId: batchId,
      );
    }

    // Calculate optimal batch size based on token estimation
    final optimalBatchSize = _calculateOptimalBatchSize(
      llmRequest: llmRequest,
      units: unitsToTranslate,
      context: context,
    );

    // Proactive split: If batch exceeds optimal size, split immediately
    if (unitsToTranslate.length > optimalBatchSize) {
      _logger.debug('Batch size ${unitsToTranslate.length} > optimal $optimalBatchSize, pre-splitting');

      // Estimate tokens for logging
      final estimatedTokens = _estimateTokensForUnits(
        llmRequest: llmRequest,
        units: unitsToTranslate,
      );

      // Update progress detail
      final splitProgress = progress.copyWith(
        phaseDetail: 'Batch too large (~$estimatedTokens tokens), auto-splitting into smaller chunks...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, splitProgress);

      // Create warning log
      final warningLog = LlmExchangeLog.fromError(
        requestId: '$batchId-preemptive-split-$depth',
        providerCode: context.providerId ?? 'unknown',
        modelName: context.modelId ?? 'unknown',
        unitsCount: unitsToTranslate.length,
        errorMessage: 'Batch too large (${unitsToTranslate.length} units, ~$estimatedTokens tokens > 140k limit), auto-splitting to ~$optimalBatchSize units',
      );

      // Split in half
      final midPoint = (unitsToTranslate.length / 2).ceil();
      final firstHalf = unitsToTranslate.sublist(0, midPoint);
      final secondHalf = unitsToTranslate.sublist(midPoint);

      _logger.debug('Pre-split: ${firstHalf.length} + ${secondHalf.length} units');

      // Process both halves SEQUENTIALLY (parallelism is handled at chunk level)
      // Recalculate maxTokens for the split size
      final firstHalfMaxTokens = (firstHalf.length * 120 + 500).clamp(1000, 8000);
      final firstHalfRequest = llmRequest.copyWith(
        requestId: '$batchId-preempt1-depth$depth',
        texts: {for (var unit in firstHalf) unit.id: unit.sourceText},
        maxTokens: firstHalfMaxTokens,
      );

      final (progressAfterFirst, firstTranslations) = await _translateWithAutoSplit(
        batchId: batchId,
        rootBatchId: rootBatchId,
        unitsToTranslate: firstHalf,
        llmRequest: firstHalfRequest,
        context: context,
        progress: progress.copyWith(
          llmLogs: [...currentProgress.llmLogs, warningLog],
        ),
        currentProgress: currentProgress,
        getCancellationToken: getCancellationToken,
        onProgressUpdate: onProgressUpdate,
        checkPauseOrCancel: checkPauseOrCancel,
        onSubBatchTranslated: onSubBatchTranslated,
        depth: depth + 1,
      );

      // Check cancellation before processing second half
      await checkPauseOrCancel(rootBatchId);

      final secondHalfMaxTokens = (secondHalf.length * 120 + 500).clamp(1000, 8000);
      final secondHalfRequest = llmRequest.copyWith(
        requestId: '$batchId-preempt2-depth$depth',
        texts: {for (var unit in secondHalf) unit.id: unit.sourceText},
        maxTokens: secondHalfMaxTokens,
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

    // Get cancellation token
    final cancellationToken = getCancellationToken(batchId);
    final dioCancelToken = cancellationToken?.dioToken;

    // Update progress with LLM call info
    final llmCallProgress = progress.copyWith(
      phaseDetail: 'Calling ${context.providerCode ?? "LLM"} API (${unitsToTranslate.length} units)...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, llmCallProgress);

    // Try translation with retry for transient errors (429, 529, etc.)
    final llmResult = await _translateWithRetry(
      llmRequest: llmRequest,
      batchId: batchId,
      dioCancelToken: dioCancelToken,
      maxRetries: 3,
    );

    // Check for errors that indicate batch is too large
    if (llmResult.isErr) {
      final error = llmResult.unwrapErr();

      // Detect errors that suggest batch is too large:
      // 1. Token limit exceeded
      // 2. Response parsing failures (often due to truncated responses)
      final isBatchTooLarge = (error is LlmTokenLimitException) ||
          (error is LlmResponseParseException && unitsToTranslate.length > 1);

      // If batch is too large and has more than 1 unit, split and retry
      if (isBatchTooLarge && unitsToTranslate.length > 1) {
        final errorType = error is LlmTokenLimitException ? 'Token limit' : 'Response parsing';

        _logger.debug('$errorType error, splitting ${unitsToTranslate.length} units');

        // Create warning log
        final warningLog = LlmExchangeLog.fromError(
          requestId: '$batchId-split-$depth',
          providerCode: context.providerId ?? 'unknown',
          modelName: context.modelId ?? 'unknown',
          unitsCount: unitsToTranslate.length,
          errorMessage: '$errorType error, auto-splitting batch (${unitsToTranslate.length} units)',
        );

        // Split units in half
        final midPoint = (unitsToTranslate.length / 2).ceil();
        final firstHalf = unitsToTranslate.sublist(0, midPoint);
        final secondHalf = unitsToTranslate.sublist(midPoint);

        _logger.debug('Split: ${firstHalf.length} + ${secondHalf.length} units');

        // Process both halves SEQUENTIALLY (parallelism is handled at chunk level)
        // Recalculate maxTokens for the split size
        final firstHalfMaxTokens = (firstHalf.length * 120 + 500).clamp(1000, 8000);
        final firstHalfRequest = llmRequest.copyWith(
          requestId: '$batchId-part1-depth$depth',
          texts: {for (var unit in firstHalf) unit.id: unit.sourceText},
          maxTokens: firstHalfMaxTokens,
        );

        final (progressAfterFirst, firstTranslations) = await _translateWithAutoSplit(
          batchId: batchId,
          rootBatchId: rootBatchId,
          unitsToTranslate: firstHalf,
          llmRequest: firstHalfRequest,
          context: context,
          progress: progress.copyWith(
            llmLogs: [...currentProgress.llmLogs, warningLog],
          ),
          currentProgress: currentProgress,
          getCancellationToken: getCancellationToken,
          onProgressUpdate: onProgressUpdate,
          checkPauseOrCancel: checkPauseOrCancel,
          onSubBatchTranslated: onSubBatchTranslated,
          depth: depth + 1,
        );

        // Check cancellation before processing second half
        await checkPauseOrCancel(rootBatchId);

        // Process second half
        final secondHalfMaxTokens = (secondHalf.length * 120 + 500).clamp(1000, 8000);
        final secondHalfRequest = llmRequest.copyWith(
          requestId: '$batchId-part2-depth$depth',
          texts: {for (var unit in secondHalf) unit.id: unit.sourceText},
          maxTokens: secondHalfMaxTokens,
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

      // Other errors or single unit that's too large
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

    // Success - process response
    final llmResponse = llmResult.unwrap();

    final translations = <String, String>{};
    for (var i = 0;
        i < unitsToTranslate.length && i < llmResponse.translations.length;
        i++) {
      final unit = unitsToTranslate[i];
      final translatedText = llmResponse.translations.values.elementAt(i);
      translations[unit.id] = translatedText;
    }

    _logger.debug('LLM batch done: ${llmResponse.translations.length} units, ${llmResponse.totalTokens} tokens');

    // Update progress with completion info
    final completionProgress = progress.copyWith(
      phaseDetail: 'LLM returned ${llmResponse.translations.length} translations (${llmResponse.totalTokens} tokens used)',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, completionProgress);

    // Progressive save: call callback to save translations immediately
    if (onSubBatchTranslated != null && translations.isNotEmpty) {
      try {
        await onSubBatchTranslated(unitsToTranslate, translations);
      } catch (e) {
        _logger.warning('Progressive save failed: $e');
        // Don't throw - translations are still in memory and will be saved at the end
      }
    }

    // Create success log
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
      tokensUsed: currentProgress.tokensUsed + llmResponse.totalTokens,
      llmLogs: updatedLogs,
      timestamp: DateTime.now(),
    );

    // Emit progress update after successful LLM call
    onProgressUpdate(batchId, updatedProgress);

    return (updatedProgress, translations);
  }

  /// Calculate optimal batch size based on token estimation
  ///
  /// Estimates:
  /// - Fixed tokens (system prompt, context, glossary)
  /// - Average tokens per unit (input + output + JSON overhead)
  /// - Maximum units that fit within Anthropic's 200k token limit with safety margin
  int _calculateOptimalBatchSize({
    required LlmRequest llmRequest,
    required List<TranslationUnit> units,
    required TranslationContext context,
  }) {
    // Provider max tokens (Anthropic: 200k for input+output combined)
    const int maxTokens = 200000;
    // Safety margin: use only 40% to account for estimation errors and response overhead
    // The output can be larger than input due to JSON structure
    const double safetyMargin = 0.4;
    final int safeMaxTokens = (maxTokens * safetyMargin).floor();

    // Calculate fixed context tokens (system prompt + context)
    int fixedTokens = 0;

    // System prompt
    fixedTokens += _tokenCalculator.calculateAnthropicTokens(llmRequest.systemPrompt);

    // Game context
    if (llmRequest.gameContext != null) {
      fixedTokens += _tokenCalculator.calculateAnthropicTokens(llmRequest.gameContext!);
    }

    // Project context
    if (llmRequest.projectContext != null) {
      fixedTokens += _tokenCalculator.calculateAnthropicTokens(llmRequest.projectContext!);
    }

    // Few-shot examples
    if (llmRequest.fewShotExamples != null) {
      for (final example in llmRequest.fewShotExamples!) {
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(example.source);
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(example.target);
      }
    }

    // Glossary terms
    if (llmRequest.glossaryTerms != null) {
      for (final entry in llmRequest.glossaryTerms!.entries) {
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(entry.key);
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(entry.value);
      }
    }

    // If fixed tokens already exceed safe limit, return minimum
    if (fixedTokens >= safeMaxTokens) {
      return 1;
    }

    // Calculate average tokens per unit from sample
    final sampleSize = units.length.clamp(1, 10);
    int totalUnitTokens = 0;

    for (var i = 0; i < sampleSize; i++) {
      final unit = units[i];
      
      // Input tokens (key + source text)
      totalUnitTokens += _tokenCalculator.calculateAnthropicTokens(unit.id);
      totalUnitTokens += _tokenCalculator.calculateAnthropicTokens(unit.sourceText);
      
      // Estimated output tokens (roughly equal to input for translations)
      totalUnitTokens += _tokenCalculator.calculateAnthropicTokens(unit.sourceText);
      
      // JSON overhead per unit: {"key": "uuid-36-chars", "translation": "..."},
      // Includes: JSON structure (~10 tokens) + UUID (~10 tokens) + punctuation (~15 tokens)
      totalUnitTokens += 35;
    }

    final avgTokensPerUnit = (totalUnitTokens / sampleSize).ceil();

    // Available tokens for units
    final availableTokens = safeMaxTokens - fixedTokens;

    // Calculate optimal batch size
    final calculatedSize = (availableTokens / avgTokensPerUnit).floor();

    // Clamp to user-defined max batch size
    final optimalSize = calculatedSize.clamp(1, context.unitsPerBatch);

    _logger.debug('Optimal batch size: $optimalSize (from $calculatedSize calculated)');

    return optimalSize;
  }

  /// Translate batch with automatic retry for transient errors
  ///
  /// Retries on:
  /// - LlmServerException (5xx errors including 529 Overloaded)
  /// - LlmRateLimitException (429 Too Many Requests)
  /// - LlmNetworkException (connection errors)
  ///
  /// Uses exponential backoff: 2s, 4s, 8s...
  Future<Result<LlmResponse, LlmServiceException>> _translateWithRetry({
    required LlmRequest llmRequest,
    required String batchId,
    required dynamic dioCancelToken,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    LlmServiceException? lastError;

    while (attempt <= maxRetries) {
      final result = await _llmService.translateBatch(
        llmRequest,
        cancelToken: dioCancelToken,
      );

      if (result.isOk) {
        return result;
      }

      final error = result.unwrapErr();
      lastError = error;

      // Check if error is retryable
      final isRetryable = error is LlmServerException ||
          error is LlmRateLimitException ||
          error is LlmNetworkException;

      if (!isRetryable || attempt >= maxRetries) {
        return result;
      }

      // Calculate delay with exponential backoff
      int delaySeconds;
      if (error is LlmRateLimitException && error.retryAfterSeconds != null) {
        // Use provider-suggested delay if available
        delaySeconds = error.retryAfterSeconds!;
      } else {
        // Exponential backoff: 2^attempt * 2 seconds (2s, 4s, 8s)
        delaySeconds = (1 << attempt) * 2;
      }

      _logger.warning('Retry ${attempt + 1}/$maxRetries after ${delaySeconds}s (${error.runtimeType})');

      await Future.delayed(Duration(seconds: delaySeconds));
      attempt++;
    }

    // Should not reach here, but return last error if it does
    return Err(lastError!);
  }

  /// Estimate total tokens for a batch of units
  ///
  /// Quick estimation without building full request
  int _estimateTokensForUnits({
    required LlmRequest llmRequest,
    required List<TranslationUnit> units,
  }) {
    // Create a mock request with these units for estimation
    final textsMap = {for (var unit in units) unit.id: unit.sourceText};
    final mockRequest = llmRequest.copyWith(texts: textsMap);
    
    return _tokenCalculator.estimateAnthropicRequestTokens(mockRequest);
  }
}
