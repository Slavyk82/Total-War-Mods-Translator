import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/batch_translation_cache.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/llm_exchange_log.dart';
import 'package:twmt/services/translation/utils/translation_text_utils.dart';

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

  /// Estimate maxTokens based on source text content, not just unit count.
  ///
  /// For long texts, 120 tokens/unit is insufficient. Uses character count
  /// as a more accurate proxy (roughly 4 chars per token for most languages).
  int _estimateMaxTokens(Map<String, String> textsMap) {
    // Calculate based on actual text length
    int totalChars = 0;
    for (final text in textsMap.values) {
      totalChars += text.length;
    }

    // Estimate: ~4 chars per token, translation may be 1.2x longer than source
    // Add buffer for JSON structure overhead
    final textBasedEstimate = ((totalChars / 4) * 1.3).ceil() + 500;

    // Also consider unit count for JSON key overhead
    final unitBasedEstimate = (textsMap.length * 150) + 500;

    // Use the larger of the two estimates
    final estimate = textBasedEstimate > unitBasedEstimate
        ? textBasedEstimate
        : unitBasedEstimate;

    // Clamp to reasonable bounds: minimum 1000, maximum 80000
    return estimate.clamp(1000, 80000);
  }

  /// Perform LLM translation for units not matched by TM
  ///
  /// Returns tuple of (updated progress, translations map)
  ///
  /// [tmMatchedUnitIds] contains IDs of units already translated by TM lookup.
  /// This avoids redundant database checks for each unit.
  ///
  /// [onSubBatchTranslated] is called after each successful LLM sub-batch
  /// to allow progressive saving. This prevents data loss on failures.
  ///
  /// [checkPauseOrCancel] is called with the root batchId to check for
  /// stop/cancel requests before starting new work.
  ///
  /// Uses [BatchTranslationCache] for:
  /// - Intra-batch deduplication (same source text within batch)
  /// - Cross-batch deduplication (parallel batches share translations)
  ///
  /// Returns tuple of (progress, translations, cachedUnitIds) where:
  /// - translations: Map of unitId -> translated text
  /// - cachedUnitIds: Set of unit IDs that were translated via cache/deduplication
  ///   (not directly by LLM). These should be marked as TM matches, not LLM.
  ///
  /// [onSubBatchTranslated] callback now receives a third parameter: Set of cached unit IDs
  /// in this sub-batch. These are units that got their translation from cache/deduplication.
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
    final cache = BatchTranslationCache.instance;

    // Filter units that need translation (not already matched by TM) - O(1) lookup per unit
    final unitsToTranslate = units
        .where((unit) => !tmMatchedUnitIds.contains(unit.id))
        .toList();

    if (unitsToTranslate.isEmpty) {
      return (currentProgress, <String, String>{}, <String>{});
    }

    // === DEDUPLICATION: Group units by source text ===
    // This reduces LLM calls when the same text appears multiple times
    // For large batches, yield periodically to keep UI responsive
    final sourceTextToUnits = <String, List<TranslationUnit>>{};
    var yieldCounter = 0;
    const yieldInterval = 500; // Yield every N iterations

    // Update progress for large batches
    if (unitsToTranslate.length > 1000) {
      onProgressUpdate(
        batchId,
        currentProgress.copyWith(
          phaseDetail: 'Deduplicating ${unitsToTranslate.length} units...',
          timestamp: DateTime.now(),
        ),
      );
    }

    for (final unit in unitsToTranslate) {
      sourceTextToUnits.putIfAbsent(unit.sourceText, () => []).add(unit);

      // Yield to event loop periodically to prevent UI freeze
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    final uniqueSourceTexts = sourceTextToUnits.keys.toList();
    final duplicateCount = unitsToTranslate.length - uniqueSourceTexts.length;

    if (duplicateCount > 0) {
      _logger.info('Deduplication: ${unitsToTranslate.length} units -> ${uniqueSourceTexts.length} unique texts ($duplicateCount duplicates)');
    }

    // === CACHE CHECK: Find cached and pending translations ===
    // Hash computation and cache lookups can be slow for large batches
    // NOTE: When skipTranslationMemory=true, we skip cache lookups to force fresh
    // LLM translations that will then update Translation Memory.
    final cachedTranslations = <String, String>{}; // sourceText -> translation
    final pendingFutures = <String, Future<String?>>{}; // sourceText -> future
    final uncachedSourceTexts = <String>[]; // source texts to translate

    // When skipTranslationMemory is true, bypass cache to get fresh LLM translations
    // This ensures new translations replace existing TM entries
    final skipCacheLookup = context.skipTranslationMemory;

    // Update progress for large batches
    if (uniqueSourceTexts.length > 1000) {
      onProgressUpdate(
        batchId,
        currentProgress.copyWith(
          phaseDetail: skipCacheLookup 
              ? 'Preparing ${uniqueSourceTexts.length} unique texts for fresh LLM translation...'
              : 'Checking cache for ${uniqueSourceTexts.length} unique texts...',
          timestamp: DateTime.now(),
        ),
      );
    }

    yieldCounter = 0;
    for (final sourceText in uniqueSourceTexts) {
      final hash = cache.computeHash(sourceText, context.targetLanguage);
      
      // Skip cache lookup when skipTranslationMemory=true to force fresh translations
      if (skipCacheLookup) {
        uncachedSourceTexts.add(sourceText);
      } else {
        final result = cache.lookup(hash);

        switch (result) {
          case CacheHit(:final translation):
            cachedTranslations[sourceText] = translation;
          case CachePending(:final future):
            pendingFutures[sourceText] = future;
          case CacheMiss():
            uncachedSourceTexts.add(sourceText);
        }
      }

      // Yield to event loop periodically to prevent UI freeze
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    if (skipCacheLookup) {
      _logger.info('Cache bypassed (skipTranslationMemory=true)', {
        'uniqueTexts': uniqueSourceTexts.length,
        'reason': 'Force fresh LLM translations to update Translation Memory',
      });
    } else if (cachedTranslations.isNotEmpty || pendingFutures.isNotEmpty) {
      _logger.info('Cache status', {
        'cached': cachedTranslations.length,
        'pending': pendingFutures.length,
        'uncached': uncachedSourceTexts.length,
      });
    }

    // === WAIT FOR PENDING: Get translations from other batches ===
    if (pendingFutures.isNotEmpty) {
      var progress = currentProgress.copyWith(
        phaseDetail: 'Waiting for ${pendingFutures.length} translations from parallel batches...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      for (final entry in pendingFutures.entries) {
        final translation = await entry.value;
        if (translation != null) {
          cachedTranslations[entry.key] = translation;
        } else {
          // Other batch failed, we need to translate this ourselves
          uncachedSourceTexts.add(entry.key);
        }
      }
    }

    // === BUILD FINAL TRANSLATIONS MAP ===
    final allTranslations = <String, String>{}; // unitId -> translation
    final cachedUnitIds = <String>{}; // IDs of units translated via cache/deduplication

    // Apply cached translations to all units with same source text
    // These are all "cached" - they come from cross-batch cache or pending results
    yieldCounter = 0;
    for (final entry in cachedTranslations.entries) {
      final unitsWithSameSource = sourceTextToUnits[entry.key] ?? [];
      for (final unit in unitsWithSameSource) {
        allTranslations[unit.id] = entry.value;
        cachedUnitIds.add(unit.id); // Mark as cached
      }

      // Yield to event loop periodically to prevent UI freeze
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // If all translations came from cache, we're done
    if (uncachedSourceTexts.isEmpty) {
      _logger.info('All ${unitsToTranslate.length} translations served from cache');

      // Save cached translations - all units are cached
      if (onSubBatchTranslated != null && allTranslations.isNotEmpty) {
        try {
          await onSubBatchTranslated(unitsToTranslate, allTranslations, cachedUnitIds);
        } catch (e) {
          _logger.warning('Failed to save cached translations: $e');
        }
      }

      return (currentProgress, allTranslations, cachedUnitIds);
    }

    // === REGISTER PENDING: Mark our translations as in-progress ===
    final registeredHashes = <String, String>{}; // sourceText -> hash
    yieldCounter = 0;
    for (final sourceText in uncachedSourceTexts) {
      final hash = cache.computeHash(sourceText, context.targetLanguage);
      if (cache.registerPending(hash, batchId)) {
        registeredHashes[sourceText] = hash;
      }

      // Yield to event loop periodically to prevent UI freeze
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // === BUILD UNITS FOR LLM: One unit per unique source text ===
    // Select representative unit for each unique source text
    final unitsForLlm = <TranslationUnit>[];
    final sourceTextToRepresentativeUnit = <String, TranslationUnit>{};

    for (final sourceText in uncachedSourceTexts) {
      final units = sourceTextToUnits[sourceText]!;
      final representative = units.first;
      unitsForLlm.add(representative);
      sourceTextToRepresentativeUnit[sourceText] = representative;
    }

    _logger.info('LLM translation: ${unitsForLlm.length} unique texts (${unitsToTranslate.length} total units) via ${context.providerId ?? "default"}/${context.modelId ?? "default"}');

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
      units: unitsForLlm, // Use deduplicated units
      context: context,
      includeExamples: true,
      maxExamples: 3,
    );

    if (promptResult.isErr) {
      // Fail registered pending translations
      for (final hash in registeredHashes.values) {
        cache.fail(hash);
      }
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

    // Split units into parallel chunks if parallelBatches > 1
    final parallelBatches = context.parallelBatches;
    if (parallelBatches > 1 && unitsForLlm.length > parallelBatches) {
      // Check cancellation before starting parallel processing
      await checkPauseOrCancel(batchId);

      progress = progress.copyWith(
        phaseDetail: 'Splitting into $parallelBatches parallel batches for faster processing...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      _logger.debug('Splitting into $parallelBatches parallel batches');

      // Calculate chunk size (use unitsForLlm - deduplicated)
      final chunkSize = (unitsForLlm.length / parallelBatches).ceil();
      final chunks = <List<TranslationUnit>>[];

      for (var i = 0; i < unitsForLlm.length; i += chunkSize) {
        final end = (i + chunkSize < unitsForLlm.length)
            ? i + chunkSize
            : unitsForLlm.length;
        chunks.add(unitsForLlm.sublist(i, end));
      }

      _logger.debug('Created ${chunks.length} parallel chunks');

      // Track saved unit IDs to avoid double-counting at the end
      final savedUnitIds = <String>{};

      // Wrapper callback that tracks saved units for progress updates
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

      // Update progress to indicate LLM calls are starting
      progress = progress.copyWith(
        phaseDetail: 'Waiting LLM API response (${chunks.length} parallel requests)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      // Process chunks in parallel, wrapping each in error handling
      // to continue with other chunks even if one fails
      final futures = <Future<(TranslationProgress, Map<String, String>, String?)>>[];

      // Create a wrapper for onProgressUpdate that only updates phaseDetail
      // to prevent counter regression from parallel chunks overwriting each other.
      // The counters will be properly accumulated after all chunks complete.
      void parallelProgressUpdate(String id, TranslationProgress chunkProgress) {
        // Only update phaseDetail, keep the original counters stable
        final stableProgress = progress.copyWith(
          phaseDetail: chunkProgress.phaseDetail,
          currentPhase: chunkProgress.currentPhase,
          // Keep logs for visibility but don't update counters
          llmLogs: chunkProgress.llmLogs,
          timestamp: chunkProgress.timestamp,
        );
        onProgressUpdate(id, stableProgress);
      }

      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final chunkId = '$batchId-parallel-$i';

        // Create LLM request for this chunk
        final textsMap = <String, String>{};
        for (final unit in chunk) {
          textsMap[unit.id] = unit.sourceText;
        }

        final maxTokens = _estimateMaxTokens(textsMap);

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

        // Wrap each chunk translation in error handling to continue on failure
        futures.add(_translateChunkWithErrorHandling(
          chunkId: chunkId,
          rootBatchId: batchId,
          chunk: chunk,
          llmRequest: llmRequest,
          context: context,
          progress: progress,
          currentProgress: currentProgress,
          getCancellationToken: getCancellationToken,
          onProgressUpdate: parallelProgressUpdate, // Use wrapper to prevent counter regression
          checkPauseOrCancel: checkPauseOrCancel,
          onSubBatchTranslated: trackingSaveCallback,
        ));
      }

      // Wait for all parallel batches to complete
      final results = await Future.wait(futures);

      // Merge results, collecting any errors
      // Important: Accumulate tokensUsed and llmLogs from all chunks
      final llmTranslations = <String, String>{}; // unitId -> translation
      final chunkErrors = <String>[];
      int totalTokensUsed = currentProgress.tokensUsed;
      final allLlmLogs = <LlmExchangeLog>[...currentProgress.llmLogs];

      for (final (chunkProgress, chunkTranslations, chunkError) in results) {
        llmTranslations.addAll(chunkTranslations);
        if (chunkError != null) {
          chunkErrors.add(chunkError);
        }
        // Accumulate tokens (each chunk reports its own tokens, not cumulative)
        // We need to extract just the new logs from this chunk
        final newLogs = chunkProgress.llmLogs
            .where((log) => !allLlmLogs.any((existing) => existing.requestId == log.requestId))
            .toList();
        allLlmLogs.addAll(newLogs);
        // Sum up tokens from new logs
        for (final log in newLogs) {
          totalTokensUsed += log.inputTokens + log.outputTokens;
        }
      }

      // Log any errors that occurred but didn't block the batch
      if (chunkErrors.isNotEmpty) {
        _logger.warning(
          'Some chunks failed during parallel translation: ${chunkErrors.length} errors. '
          'Successfully translated ${llmTranslations.length} units.',
        );
      }

      _logger.debug('Parallel translation completed: ${llmTranslations.length} translations');

      // Update progress to indicate LLM calls completed
      // IMPORTANT: Use parallelProgressUpdate to avoid overwriting counter values
      // that were updated by ValidationPersistenceHandler during progressive saves
      final completionProgress = progress.copyWith(
        phaseDetail: 'LLM translation complete (${llmTranslations.length} translations received)',
        llmLogs: allLlmLogs,
        timestamp: DateTime.now(),
      );
      parallelProgressUpdate(batchId, completionProgress);

      // Build finalProgress for return value (read current state, only update tokens/logs)
      // The counters are managed by ValidationPersistenceHandler, not here
      var finalProgress = progress.copyWith(
        tokensUsed: totalTokensUsed,
        llmLogs: allLlmLogs,
        timestamp: DateTime.now(),
      );

      // === UPDATE CACHE & APPLY TO DUPLICATES ===
      await _updateCacheAndApplyDuplicates(
        llmTranslations: llmTranslations,
        sourceTextToUnits: sourceTextToUnits,
        registeredHashes: registeredHashes,
        allTranslations: allTranslations,
        cachedUnitIds: cachedUnitIds,
        cache: cache,
        context: context,
      );

      // Save only unsaved translations (duplicates that weren't in parallel chunks)
      if (onSubBatchTranslated != null && allTranslations.isNotEmpty) {
        // Filter to only unsaved units (duplicates)
        final unsavedTranslations = Map.fromEntries(
          allTranslations.entries.where((e) => !savedUnitIds.contains(e.key)),
        );

        if (unsavedTranslations.isNotEmpty) {
          _logger.debug('Saving ${unsavedTranslations.length} duplicate units');
          // Filter units to only unsaved ones
          final unsavedUnits = unitsToTranslate
              .where((u) => unsavedTranslations.containsKey(u.id))
              .toList();
          // All unsaved units are duplicates, so they're all cached
          final unsavedCachedIds = unsavedTranslations.keys.toSet();
          try {
            await onSubBatchTranslated(unsavedUnits, unsavedTranslations, unsavedCachedIds);
          } catch (e) {
            _logger.warning('Failed to save duplicate translations: $e');
          }
        }
      }

      return (finalProgress, allTranslations, cachedUnitIds);
    }

    // Single batch processing (parallelBatches == 1 or too few units)
    final textsMap = <String, String>{};
    for (final unit in unitsForLlm) {
      textsMap[unit.id] = unit.sourceText;
    }

    final maxTokens = _estimateMaxTokens(textsMap);

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

    // Track saved unit IDs for single batch mode too
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

      // === UPDATE CACHE & APPLY TO DUPLICATES ===
      await _updateCacheAndApplyDuplicates(
        llmTranslations: llmTranslations,
        sourceTextToUnits: sourceTextToUnits,
        registeredHashes: registeredHashes,
        allTranslations: allTranslations,
        cachedUnitIds: cachedUnitIds,
        cache: cache,
        context: context,
      );

      // Save only unsaved translations (duplicates)
      if (onSubBatchTranslated != null && allTranslations.isNotEmpty) {
        final unsavedTranslations = Map.fromEntries(
          allTranslations.entries.where((e) => !savedUnitIds.contains(e.key)),
        );

        if (unsavedTranslations.isNotEmpty) {
          _logger.debug('Saving ${unsavedTranslations.length} duplicate units');
          final unsavedUnits = unitsToTranslate
              .where((u) => unsavedTranslations.containsKey(u.id))
              .toList();
          // All unsaved units are duplicates, so they're all cached
          final unsavedCachedIds = unsavedTranslations.keys.toSet();
          try {
            await onSubBatchTranslated(unsavedUnits, unsavedTranslations, unsavedCachedIds);
          } catch (e) {
            _logger.warning('Failed to save duplicate translations: $e');
          }
        }
      }

      return (finalProgress, allTranslations, cachedUnitIds);
    } catch (e) {
      // Fail all registered pending translations on error
      for (final hash in registeredHashes.values) {
        cache.fail(hash);
      }
      rethrow;
    }
  }

  /// Update cache with LLM translations and apply to all duplicate units
  ///
  /// [cachedUnitIds] is updated with IDs of duplicate units (not the representative
  /// unit that was actually translated by LLM)
  Future<void> _updateCacheAndApplyDuplicates({
    required Map<String, String> llmTranslations,
    required Map<String, List<TranslationUnit>> sourceTextToUnits,
    required Map<String, String> registeredHashes,
    required Map<String, String> allTranslations,
    required Set<String> cachedUnitIds,
    required BatchTranslationCache cache,
    required TranslationContext context,
  }) async {
    const yieldInterval = 500;
    var yieldCounter = 0;

    // For each LLM translation, update cache and apply to all units with same source
    for (final entry in llmTranslations.entries) {
      final unitId = entry.key;
      final translation = entry.value;

      // Find the source text for this unit
      String? sourceText;
      for (final stEntry in sourceTextToUnits.entries) {
        if (stEntry.value.any((u) => u.id == unitId)) {
          sourceText = stEntry.key;
          break;
        }
      }

      if (sourceText == null) continue;

      // Update cache
      final hash = registeredHashes[sourceText];
      if (hash != null) {
        cache.complete(hash, translation);
      }

      // Apply translation to all units with same source text
      // Mark duplicates (units other than the representative) as cached
      final unitsWithSameSource = sourceTextToUnits[sourceText] ?? [];
      for (final unit in unitsWithSameSource) {
        allTranslations[unit.id] = translation;
        // If this is not the unit that was actually translated by LLM, mark as cached
        if (unit.id != unitId) {
          cachedUnitIds.add(unit.id);
        }
      }

      // Yield to event loop periodically to prevent UI freeze
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // Fail any registered hashes that didn't get a translation
    for (final entry in registeredHashes.entries) {
      final sourceText = entry.key;
      final hash = entry.value;

      // Check if we got a translation for this source text
      final units = sourceTextToUnits[sourceText] ?? [];
      final hasTranslation = units.any((u) => allTranslations.containsKey(u.id));

      if (!hasTranslation) {
        cache.fail(hash);
      }
    }
  }

  /// Wrapper for chunk translation that catches errors and continues
  ///
  /// Returns a tuple of (progress, translations, errorMessage).
  /// If an error occurs, translations will be empty but the batch can continue.
  /// This prevents a single problematic unit from blocking the entire batch.
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
    Future<void> Function(
            List<TranslationUnit> units, Map<String, String> translations, Set<String> cachedUnitIds)?
        onSubBatchTranslated,
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
      // Log the error but don't rethrow - allow other chunks to continue
      _logger.warning(
        'Chunk $chunkId failed: ${e.message}. Skipping ${chunk.length} units.',
      );

      // Create error log for progress tracking
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

      // Return empty translations for this chunk - units will remain untranslated
      return (errorProgress, <String, String>{}, e.message);
    } catch (e) {
      // Unexpected error - log and continue
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
    Future<void> Function(List<TranslationUnit> units, Map<String, String> translations, Set<String> cachedUnitIds)? onSubBatchTranslated,
    int depth = 0,
  }) async {
    // Check cancellation before doing any work (use root batchId, not sub-batch)
    await checkPauseOrCancel(rootBatchId);
    
    // Safety limit to prevent infinite recursion
    // Depth limit of 25 allows for:
    // - Pre-emptive splitting from large batches (~12 levels for 4000+ units)
    // - Content filter splitting down to single units (~10 levels from 1000 units)
    // - Some margin for edge cases
    if (depth > 25) {
      throw TranslationOrchestrationException(
        'Batch splitting depth limit exceeded (depth=$depth). '
        'This may indicate an issue with the translation content or batch configuration.',
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

      // Update progress detail - use rootBatchId for UI visibility
      final splitProgress = progress.copyWith(
        phaseDetail: 'Batch too large (~$estimatedTokens tokens), auto-splitting into smaller chunks...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(rootBatchId, splitProgress);

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
      final firstHalfTexts = {for (var unit in firstHalf) unit.id: unit.sourceText};
      final firstHalfRequest = llmRequest.copyWith(
        requestId: '$batchId-preempt1-depth$depth',
        texts: firstHalfTexts,
        maxTokens: _estimateMaxTokens(firstHalfTexts),
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

      final secondHalfTexts = {for (var unit in secondHalf) unit.id: unit.sourceText};
      final secondHalfRequest = llmRequest.copyWith(
        requestId: '$batchId-preempt2-depth$depth',
        texts: secondHalfTexts,
        maxTokens: _estimateMaxTokens(secondHalfTexts),
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

    // Update progress with LLM call info - use rootBatchId for UI visibility
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

    // Try translation with retry for transient errors (429, 529, etc.)
    final llmResult = await _translateWithRetry(
      llmRequest: llmRequest,
      batchId: batchId,
      dioCancelToken: dioCancelToken,
      maxRetries: 3,
    );

    // Check for errors that indicate batch is too large or content issues
    if (llmResult.isErr) {
      final error = llmResult.unwrapErr();

      // Detect errors that suggest batch should be split:
      // 1. Token limit exceeded
      // 2. Response parsing failures (often due to truncated responses)
      // 3. Content filtered - split to isolate problematic unit(s)
      final isContentFiltered = error is LlmContentFilteredException;
      final isBatchTooLarge = (error is LlmTokenLimitException) ||
          (error is LlmResponseParseException && unitsToTranslate.length > 1);
      final shouldSplit = (isBatchTooLarge || isContentFiltered) && unitsToTranslate.length > 1;

      // If batch should be split and has more than 1 unit, split and retry
      if (shouldSplit) {
        final errorType = error is LlmTokenLimitException
            ? 'Token limit'
            : (isContentFiltered ? 'Content filtered' : 'Response parsing');

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
        final firstHalfTextsErr = {for (var unit in firstHalf) unit.id: unit.sourceText};
        final firstHalfRequest = llmRequest.copyWith(
          requestId: '$batchId-part1-depth$depth',
          texts: firstHalfTextsErr,
          maxTokens: _estimateMaxTokens(firstHalfTextsErr),
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
        final secondHalfTextsErr = {for (var unit in secondHalf) unit.id: unit.sourceText};
        final secondHalfRequest = llmRequest.copyWith(
          requestId: '$batchId-part2-depth$depth',
          texts: secondHalfTextsErr,
          maxTokens: _estimateMaxTokens(secondHalfTextsErr),
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

      // Single unit that failed - handle based on error type
      // Parse error on single unit: retry with higher maxTokens (truncation issue)
      if (error is LlmResponseParseException &&
          unitsToTranslate.length == 1 &&
          depth < 2) {
      final unit = unitsToTranslate.first;
      final currentMaxTokens = llmRequest.maxTokens ?? 4000;
      // Double maxTokens, cap at 80000 for very long texts
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
          progress: progress.copyWith(
            llmLogs: [...currentProgress.llmLogs, retryLog],
          ),
          currentProgress: currentProgress,
          getCancellationToken: getCancellationToken,
          onProgressUpdate: onProgressUpdate,
          checkPauseOrCancel: checkPauseOrCancel,
          onSubBatchTranslated: onSubBatchTranslated,
          depth: depth + 1,
        );
      }

      // Content filter on single unit: skip gracefully and continue
      if (isContentFiltered && unitsToTranslate.length == 1) {
        final unit = unitsToTranslate.first;
        _logger.warning(
          'Content filtered for unit "${unit.key}" - skipping. '
          'Consider using a different provider (Claude/DeepL) for this content.',
        );

        // Create warning log for filtered content
        final filterLog = LlmExchangeLog.fromError(
          requestId: '$batchId-filtered',
          providerCode: context.providerId ?? 'unknown',
          modelName: context.modelId ?? 'unknown',
          unitsCount: 1,
          errorMessage: 'Content filtered by provider moderation for key "${unit.key}". '
              'The source text may contain content that violates the provider\'s usage policies.',
        );

        // Update progress with filter warning and increment failed count - use rootBatchId for UI visibility
        final filterProgress = progress.copyWith(
          phaseDetail: 'Skipped filtered content: "${unit.key}"',
          llmLogs: [...currentProgress.llmLogs, filterLog],
          failedUnits: currentProgress.failedUnits + 1,
          timestamp: DateTime.now(),
        );
        onProgressUpdate(rootBatchId, filterProgress);

        // Return empty translations - the unit will remain untranslated
        // but the batch continues processing other units (counted as failed)
        return (filterProgress, <String, String>{});
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
      // Normalize: \\n → \n
      translations[unit.id] = TranslationTextUtils.normalizeTranslation(translatedText);
    }

    final apiCallDuration = DateTime.now().difference(apiCallStart);
    _logger.debug(
      'LLM API call completed in ${apiCallDuration.inSeconds}s: '
      '${llmResponse.translations.length} units, ${llmResponse.totalTokens} tokens',
    );

    // Update progress with completion info - use rootBatchId for UI visibility
    final completionProgress = progress.copyWith(
      phaseDetail: 'LLM returned ${llmResponse.translations.length} translations (${llmResponse.totalTokens} tokens used)',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(rootBatchId, completionProgress);

    // Progressive save: call callback to save translations immediately
    // These are direct LLM translations, not cached, so pass empty set
    if (onSubBatchTranslated != null && translations.isNotEmpty) {
      try {
        await onSubBatchTranslated(unitsToTranslate, translations, <String>{});
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
      phaseDetail: 'Chunk saved (${translations.length} units), processing continues...',
      tokensUsed: currentProgress.tokensUsed + llmResponse.totalTokens,
      llmLogs: updatedLogs,
      timestamp: DateTime.now(),
    );

    // Emit progress update after successful LLM call - use rootBatchId for UI visibility
    onProgressUpdate(rootBatchId, updatedProgress);

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

    // Handle auto mode (unitsPerBatch = 0) vs manual limit
    final int optimalSize;
    if (context.unitsPerBatch == 0) {
      // Auto mode: use calculated size with reasonable max (1000)
      optimalSize = calculatedSize.clamp(1, 1000);
      _logger.debug('Optimal batch size: $optimalSize (auto mode, calculated: $calculatedSize)');
    } else {
      // Manual mode: clamp to user-defined max batch size
      optimalSize = calculatedSize.clamp(1, context.unitsPerBatch);
      _logger.debug('Optimal batch size: $optimalSize (from $calculatedSize calculated, max: ${context.unitsPerBatch})');
    }

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
