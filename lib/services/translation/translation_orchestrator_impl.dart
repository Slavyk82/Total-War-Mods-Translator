import 'dart:async';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/services/concurrency/batch_isolation_manager.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/batch_estimate.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/services/translation/handlers/tm_lookup_handler.dart';
import 'package:twmt/services/translation/handlers/llm_translation_handler.dart';
import 'package:twmt/services/translation/handlers/validation_persistence_handler.dart';
import 'package:twmt/services/translation/handlers/batch_progress_manager.dart';

/// Implementation of translation orchestration service
///
/// Coordinates the complete translation workflow:
/// 1. TM exact match lookup (skip LLM if 100% match)
/// 2. TM fuzzy match lookup (>=85% similarity, auto-accept if >=95%)
/// 3. Build contextual prompt with TM examples (few-shot learning)
/// 4. Call LLM service for remaining units
/// 5. Validate LLM responses
/// 6. Save translations to database and update TM
/// 7. Emit domain events for progress tracking
class TranslationOrchestratorImpl implements ITranslationOrchestrator {
  final ILlmService _llmService;
  final IPromptBuilderService _promptBuilder;
  final TranslationUnitRepository _unitRepository;
  final TranslationBatchRepository _batchRepository;
  final TranslationBatchUnitRepository _batchUnitRepository;
  // ignore: unused_field
  final BatchIsolationManager _isolationManager;
  final EventBus _eventBus;
  final LoggingService _logger;

  // Handlers
  final TmLookupHandler _tmLookupHandler;
  final LlmTranslationHandler _llmTranslationHandler;
  final ValidationPersistenceHandler _validationPersistenceHandler;
  final BatchProgressManager _batchProgressManager;

  TranslationOrchestratorImpl({
    required ILlmService llmService,
    required ITranslationMemoryService tmService,
    required IPromptBuilderService promptBuilder,
    required IValidationService validation,
    required TranslationVersionRepository versionRepository,
    required TranslationUnitRepository unitRepository,
    required TranslationBatchRepository batchRepository,
    required TranslationBatchUnitRepository batchUnitRepository,
    required BatchIsolationManager isolationManager,
    required TransactionManager transactionManager,
    required EventBus eventBus,
    required LoggingService logger,
  })  : _llmService = llmService,
        _promptBuilder = promptBuilder,
        _unitRepository = unitRepository,
        _batchRepository = batchRepository,
        _batchUnitRepository = batchUnitRepository,
        _isolationManager = isolationManager,
        _eventBus = eventBus,
        _logger = logger,
        _tmLookupHandler = TmLookupHandler(
          tmService: tmService,
          versionRepository: versionRepository,
          transactionManager: transactionManager,
          logger: logger,
        ),
        _llmTranslationHandler = LlmTranslationHandler(
          llmService: llmService,
          promptBuilder: promptBuilder,
          logger: logger,
        ),
        _validationPersistenceHandler = ValidationPersistenceHandler(
          validation: validation,
          tmService: tmService,
          versionRepository: versionRepository,
          logger: logger,
        ),
        _batchProgressManager = BatchProgressManager(
          batchRepository: batchRepository,
          eventBus: eventBus,
          logger: logger,
        );

  @override
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatch({
    required String batchId,
    required TranslationContext context,
  }) async* {
    _logger.info('Starting batch translation', {
      'batchId': batchId,
      'provider': context.providerId ?? 'default',
      'model': context.modelId ?? 'default',
    });

    // Track actual processing duration
    final startTime = DateTime.now();

      // Create stream controller for this batch
      _batchProgressManager.getOrCreateController(batchId);

      // Create cancellation token for this batch
      _batchProgressManager.getOrCreateCancellationToken(batchId);

    // Get batch details for events (loaded once, used in all event emissions)
    TranslationBatch? batch;
    try {
      final batchResult = await _batchRepository.getById(batchId);
      batch = batchResult.isOk ? batchResult.unwrap() : null;
    } catch (e) {
      _logger.warning('Failed to load batch details for events', e);
    }

    try {
      // Validate batch first
      final validationErrors = await validateBatch(
        batchId: batchId,
        context: context,
      );

      if (validationErrors.isNotEmpty) {
        final error = TranslationOrchestrationException(
          'Batch validation failed: ${validationErrors.map((e) => e.message).join(', ')}',
          batchId: batchId,
        );
        yield Err(error);
        _batchProgressManager.cleanup(batchId);
        return;
      }

      // Load translation units from database
      final unitsResult = await _loadBatchUnits(batchId, context);
      if (unitsResult.isErr) {
        yield Err(unitsResult.unwrapErr());
        _batchProgressManager.cleanup(batchId);
        return;
      }

      final units = unitsResult.unwrap();
      if (units.isEmpty) {
        yield Err(EmptyBatchException('Batch has no units', batchId: batchId));
        _batchProgressManager.cleanup(batchId);
        return;
      }

      // Initialize progress
      final initialProgress = TranslationProgress(
        batchId: batchId,
        status: TranslationProgressStatus.inProgress,
        totalUnits: units.length,
        processedUnits: 0,
        successfulUnits: 0,
        failedUnits: 0,
        skippedUnits: 0,
        currentPhase: TranslationPhase.initializing,
        tokensUsed: 0,
        tmReuseRate: 0.0,
        timestamp: DateTime.now(),
      );

      _batchProgressManager.updateProgress(batchId, initialProgress);
      yield Ok(initialProgress);

      // Emit batch started event
      _eventBus.publish(BatchStartedEvent(
        batchId: batchId,
        projectLanguageId: context.projectLanguageId,
        providerId: context.providerId ?? 'unknown',
        batchNumber: batch?.batchNumber ?? 0,
        totalUnits: units.length,
      ));

      // Execute the 6-step workflow
      var currentProgress = initialProgress;

      // Step 1 & 2: TM Exact and Fuzzy Match Lookup
      currentProgress = await _tmLookupHandler.performLookup(
        batchId: batchId,
        units: units,
        context: context,
        currentProgress: currentProgress,
        checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
      );
      _batchProgressManager.updateProgress(batchId, currentProgress);
      yield Ok(currentProgress);
      await _batchProgressManager.checkPauseOrCancel(batchId);

      // Track units already saved progressively to avoid double-saving
      final savedUnitIds = <String>{};
      
      // Step 3 & 4: Build Prompt and Call LLM for remaining units
      // With progressive saving: save after each LLM sub-batch completes
      final (progressAfterLlm, llmTranslations) =
          await _llmTranslationHandler.performTranslation(
        batchId: batchId,
        units: units,
        context: context,
        currentProgress: currentProgress,
        isUnitTranslated: _tmLookupHandler.isUnitTranslated,
        getCancellationToken: (batchId) => _batchProgressManager.getCancellationToken(batchId),
        onProgressUpdate: (batchId, progress) {
          _batchProgressManager.updateAndEmitProgress(batchId, progress);
        },
        checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
        // Progressive save callback - saves immediately after each LLM sub-batch
        onSubBatchTranslated: (subBatchUnits, translations) async {
          final progressBeforeSave = _batchProgressManager.getProgress(batchId) ?? currentProgress;
          await _validationPersistenceHandler.validateAndSave(
            translations: translations,
            batchId: batchId,
            units: subBatchUnits,
            context: context,
            currentProgress: progressBeforeSave,
            checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
            onProgressUpdate: (batchId, progress) {
              _batchProgressManager.updateProgress(batchId, progress);
              final controller = _batchProgressManager.getOrCreateController(batchId);
              controller.add(Ok(progress));
            },
          );
          // Track saved unit IDs
          savedUnitIds.addAll(translations.keys);
        },
      );
      currentProgress = _batchProgressManager.getProgress(batchId) ?? progressAfterLlm;
      _batchProgressManager.updateProgress(batchId, currentProgress);
      yield Ok(currentProgress);
      await _batchProgressManager.checkPauseOrCancel(batchId);

      // Step 5 & 6: Validate and Save any remaining translations not saved progressively
      final remainingTranslations = Map<String, String>.from(llmTranslations)
        ..removeWhere((unitId, _) => savedUnitIds.contains(unitId));
      
      if (remainingTranslations.isNotEmpty) {
        _logger.info('Saving remaining translations', {
          'batchId': batchId,
          'remainingCount': remainingTranslations.length,
          'alreadySaved': savedUnitIds.length,
        });
        
        final remainingUnits = units.where((u) => remainingTranslations.containsKey(u.id)).toList();
        currentProgress = await _validationPersistenceHandler.validateAndSave(
          translations: remainingTranslations,
          batchId: batchId,
          units: remainingUnits,
          context: context,
          currentProgress: currentProgress,
          checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
          onProgressUpdate: (batchId, progress) {
            _batchProgressManager.updateProgress(batchId, progress);
            final controller = _batchProgressManager.getOrCreateController(batchId);
            controller.add(Ok(progress));
          },
        );
        _batchProgressManager.updateProgress(batchId, currentProgress);
        yield Ok(currentProgress);
      }

      // Mark as completed
      final completedProgress = currentProgress.copyWith(
        status: TranslationProgressStatus.completed,
        currentPhase: TranslationPhase.completed,
        processedUnits: units.length,
        timestamp: DateTime.now(),
      );

      _batchProgressManager.updateProgress(batchId, completedProgress);
      yield Ok(completedProgress);

      // Calculate actual processing duration
      final endTime = DateTime.now();
      final processingDuration = endTime.difference(startTime);

      // Emit batch completed event
      _eventBus.publish(BatchCompletedEvent(
        batchId: batchId,
        projectLanguageId: context.projectLanguageId,
        batchNumber: batch?.batchNumber ?? 0,
        totalUnits: units.length,
        completedUnits: completedProgress.successfulUnits,
        failedUnits: completedProgress.failedUnits,
        processingDuration: processingDuration,
      ));

      _logger.info('Batch translation completed', {
        'batchId': batchId,
        'totalUnits': units.length,
        'successfulUnits': completedProgress.successfulUnits,
        'failedUnits': completedProgress.failedUnits,
        'tokensUsed': completedProgress.tokensUsed,
      });
    } on CancelledException catch (e) {
      // Batch was cancelled
      final cancelledProgress = _batchProgressManager.getProgress(batchId)?.copyWith(
                status: TranslationProgressStatus.cancelled,
                currentPhase: TranslationPhase.completed,
                timestamp: DateTime.now(),
              ) ??
          TranslationProgress(
            batchId: batchId,
            status: TranslationProgressStatus.cancelled,
            totalUnits: 0,
            processedUnits: 0,
            successfulUnits: 0,
            failedUnits: 0,
            skippedUnits: 0,
            currentPhase: TranslationPhase.completed,
            tokensUsed: 0,
            tmReuseRate: 0.0,
            timestamp: DateTime.now(),
          );

      yield Ok(cancelledProgress);

      _eventBus.publish(BatchCancelledEvent(
        batchId: batchId,
        projectLanguageId: context.projectLanguageId,
        completedUnits: _batchProgressManager.getProgress(batchId)?.successfulUnits ?? 0,
        totalUnits: _batchProgressManager.getProgress(batchId)?.totalUnits ?? 0,
        reason: e.message,
      ));

      _logger.info('Batch translation cancelled', {'batchId': batchId});
    } catch (e, stackTrace) {
      _logger.error('Batch translation failed', e, stackTrace);

      final errorProgress = _batchProgressManager.getProgress(batchId)?.copyWith(
                status: TranslationProgressStatus.failed,
                currentPhase: TranslationPhase.completed,
                errorMessage: e.toString(),
                timestamp: DateTime.now(),
              ) ??
          TranslationProgress(
            batchId: batchId,
            status: TranslationProgressStatus.failed,
            totalUnits: 0,
            processedUnits: 0,
            successfulUnits: 0,
            failedUnits: 0,
            skippedUnits: 0,
            currentPhase: TranslationPhase.completed,
            tokensUsed: 0,
            tmReuseRate: 0.0,
            errorMessage: e.toString(),
            timestamp: DateTime.now(),
          );

      yield Ok(errorProgress);

      // Get current retry count from batch record
      var retryCount = 0;
      if (batch != null) {
        retryCount = batch.retryCount;

        // Increment retry count in database
        try {
          final updatedBatch = batch.copyWith(
            retryCount: retryCount + 1,
            status: TranslationBatchStatus.failed,
            errorMessage: e.toString(),
            completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
          await _batchRepository.update(updatedBatch);
        } catch (updateError) {
          _logger.warning('Failed to update batch retry count', updateError);
        }
      }

      _eventBus.publish(BatchFailedEvent(
        batchId: batchId,
        projectLanguageId: context.projectLanguageId,
        batchNumber: batch?.batchNumber ?? 0,
        errorMessage: e.toString(),
        completedBeforeFailure: _batchProgressManager.getProgress(batchId)?.successfulUnits ?? 0,
        totalUnits: _batchProgressManager.getProgress(batchId)?.totalUnits ?? 0,
        retryCount: retryCount,
      ));
    } finally {
      _batchProgressManager.cleanup(batchId);

      // Checkpoint WAL file if needed after batch operations
      // Only checkpoint when no other batches are active to prevent contention
      final activeBatches = await _batchProgressManager.getActiveBatchIds();
      if (activeBatches.isEmpty) {
        try {
          await DatabaseService.checkpointIfNeeded();
        } catch (e) {
          _logger.debug('WAL checkpoint failed (non-critical)', {'error': e});
        }
      }
    }
  }

  @override
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatchesParallel({
    required List<String> batchIds,
    required TranslationContext context,
    int maxParallel = AppConstants.maxParallelBatches,
  }) async* {
    _logger.info('Starting parallel batch translation', {
      'batchCount': batchIds.length,
      'maxParallel': maxParallel,
    });

    // Validate maxParallel
    final parallelism = maxParallel.clamp(1, AppConstants.maxParallelBatchLimit);

    // Use proper semaphore pattern with Completers to track completion
    final controller = StreamController<Result<TranslationProgress, TranslationOrchestrationException>>();
    final activeCompleters = <Completer<void>>[];
    var completedCount = 0;
    var hasError = false;

    // Process batches maintaining parallel limit
    Future<void> processBatches() async {
      try {
        for (final batchId in batchIds) {
          // Wait if we've hit the parallelism limit
          while (activeCompleters.length >= parallelism) {
            // Wait for the first task to complete
            await Future.any(
              activeCompleters.map((c) => c.future),
            );
            // Remove the completed completer
            activeCompleters.removeWhere((c) => c.isCompleted);
          }

          // Create a completer to track this batch's completion
          final completer = Completer<void>();
          activeCompleters.add(completer);

          // Start batch processing (don't await - run in parallel)
          _processBatchWithStreaming(
            batchId,
            context,
            controller,
          ).then((_) {
            completedCount++;
            _logger.info('Batch completed ($completedCount/${batchIds.length})', {
              'batchId': batchId,
            });
            if (!completer.isCompleted) {
              completer.complete();
            }
          }).catchError((error, stackTrace) {
            hasError = true;
            _logger.error('Batch failed in parallel execution', error, stackTrace);
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          });
        }

        // Wait for all remaining batches to complete
        if (activeCompleters.isNotEmpty) {
          await Future.wait(
            activeCompleters.map((c) => c.future),
            eagerError: false,
          );
        }
      } finally {
        // Always close the controller when done
        await controller.close();

        _logger.info('Parallel batch translation completed', {
          'totalBatches': batchIds.length,
          'completedCount': completedCount,
          'hadErrors': hasError,
        });
      }
    }

    // Start processing in background (don't await - run concurrently)
    // ignore: unawaited_futures
    processBatches();

    // Yield all progress events from the controller
    await for (final result in controller.stream) {
      yield result;
    }
  }

  /// Process a batch and forward its progress events to a stream controller
  Future<void> _processBatchWithStreaming(
    String batchId,
    TranslationContext context,
    StreamController<Result<TranslationProgress, TranslationOrchestrationException>> controller,
  ) async {
    await for (final result in translateBatch(
      batchId: batchId,
      context: context,
    )) {
      if (!controller.isClosed) {
        controller.add(result);
      }
    }
  }

  @override
  Future<Result<BatchEstimate, TranslationOrchestrationException>>
      estimateBatch({
    required String batchId,
    required TranslationContext context,
  }) async {
    try {
      _logger.info('Estimating batch', {'batchId': batchId});

      // Load units from database
      final unitsResult = await _loadBatchUnits(batchId, context);
      if (unitsResult.isErr) {
        return Err(unitsResult.unwrapErr());
      }

      final units = unitsResult.unwrap();
      if (units.isEmpty) {
        return Err(EmptyBatchException('Batch has no units', batchId: batchId));
      }

      // Check TM for exact/fuzzy matches to calculate TM reuse rate
      var tmMatchCount = 0;
      for (final unit in units) {
        if (await _tmLookupHandler.isUnitTranslated(unit, context)) {
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

  @override
  Future<Result<void, TranslationOrchestrationException>> pauseTranslation({
    required String batchId,
  }) async {
    return await _batchProgressManager.pause(batchId: batchId);
  }

  @override
  Future<Result<void, TranslationOrchestrationException>> resumeTranslation({
    required String batchId,
  }) async {
    return await _batchProgressManager.resume(batchId: batchId);
  }

  @override
  Future<Result<void, TranslationOrchestrationException>> cancelTranslation({
    required String batchId,
  }) async {
    return await _batchProgressManager.cancel(batchId: batchId);
  }

  @override
  Future<Result<void, TranslationOrchestrationException>> stopTranslation({
    required String batchId,
  }) async {
    return await _batchProgressManager.stop(batchId: batchId);
  }

  @override
  Future<Result<TranslationProgress?, TranslationOrchestrationException>>
      getBatchStatus({
    required String batchId,
  }) async {
    return await _batchProgressManager.getStatus(batchId: batchId);
  }

  @override
  Future<bool> isBatchActive({
    required String batchId,
  }) async {
    return await _batchProgressManager.isActive(batchId: batchId);
  }

  @override
  Future<List<String>> getActiveBatches() async {
    return await _batchProgressManager.getActiveBatchIds();
  }

  @override
  Future<List<ValidationError>> validateBatch({
    required String batchId,
    required TranslationContext context,
  }) async {
    final errors = <ValidationError>[];

    // Validate batch ID
    if (batchId.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Batch ID cannot be empty',
        field: 'batchId',
      ));
    }

    // Validate context
    if (context.projectId.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Project ID cannot be empty',
        field: 'projectId',
      ));
    }

    if (context.targetLanguage.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Target language cannot be empty',
        field: 'targetLanguage',
      ));
    }

    // Check if batch exists in database
    final batchResult = await _batchRepository.getById(batchId);
    if (batchResult.isErr) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Batch does not exist in database',
        field: 'batchId',
      ));
    }

    return errors;
  }

  @override
  Future<BatchStatistics> getBatchStatistics({
    List<String>? batchIds,
    DateTime? since,
  }) async {
    try {
      // Build query conditions
      final conditions = <String>[];
      final args = <dynamic>[];

      if (batchIds != null && batchIds.isNotEmpty) {
        final placeholders = List.filled(batchIds.length, '?').join(', ');
        conditions.add('tb.id IN ($placeholders)');
        args.addAll(batchIds);
      }

      if (since != null) {
        conditions.add('tb.started_at >= ?');
        args.add(since.millisecondsSinceEpoch ~/ 1000);
      }

      // Only include completed or failed batches for accurate statistics
      conditions.add("tb.status IN ('completed', 'failed')");

      final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

      // Query batch statistics from database
      final db = _batchRepository.database;
      final result = await db.rawQuery('''
        SELECT
          COUNT(DISTINCT tb.id) as total_batches,
          COALESCE(SUM(tb.units_count), 0) as total_units,
          COALESCE(SUM(tb.units_completed), 0) as total_completed,
          COALESCE(SUM(CASE WHEN tb.status = 'completed' THEN tb.units_completed ELSE 0 END), 0) as total_successful,
          COALESCE(SUM(CASE WHEN tb.status = 'failed' THEN tb.units_count - tb.units_completed ELSE 0 END), 0) as total_failed,
          COALESCE(AVG(CASE WHEN tb.completed_at IS NOT NULL AND tb.started_at IS NOT NULL
                       THEN (tb.completed_at - tb.started_at) * 1.0 / NULLIF(tb.units_count, 0)
                       ELSE NULL END), 0.0) as avg_time_per_unit
        FROM translation_batches tb
        $whereClause
      ''', args);

      final row = result.first;
      final totalBatches = row['total_batches'] as int;
      final totalUnits = row['total_units'] as int;
      final totalCompleted = row['total_completed'] as int;
      final totalSuccessful = row['total_successful'] as int;
      final totalFailed = row['total_failed'] as int;
      final avgTimePerUnit = (row['avg_time_per_unit'] as num).toDouble();

      // Calculate skipped units (units not requiring LLM translation due to TM matches)
      final totalSkipped = totalUnits - totalCompleted;

      return BatchStatistics(
        totalBatches: totalBatches,
        totalUnitsProcessed: totalCompleted,
        totalSuccessful: totalSuccessful,
        totalFailed: totalFailed,
        totalSkipped: totalSkipped > 0 ? totalSkipped : 0,
        totalTokensUsed: 0,
        averageTmReuseRate: 0.0,
        averageTimePerUnit: avgTimePerUnit,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to get batch statistics', e, stackTrace);

      // Return empty statistics on error
      return const BatchStatistics(
        totalBatches: 0,
        totalUnitsProcessed: 0,
        totalSuccessful: 0,
        totalFailed: 0,
        totalSkipped: 0,
        totalTokensUsed: 0,
        averageTmReuseRate: 0.0,
        averageTimePerUnit: 0.0,
      );
    }
  }

  // ========== PRIVATE HELPER METHODS ==========

  /// Load translation units for a batch from database
  ///
  /// Performance optimized: Uses batch query instead of N individual queries.
  /// For 100 units: 2 queries instead of 101 queries (50x reduction).
  Future<Result<List<TranslationUnit>, TranslationOrchestrationException>>
      _loadBatchUnits(String batchId, TranslationContext context) async {
    try {
      // Get batch-unit associations (1 query)
      final batchUnitsResult =
          await _batchUnitRepository.findByBatchId(batchId);
      if (batchUnitsResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to load batch units: ${batchUnitsResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      final batchUnits = batchUnitsResult.unwrap();
      final unitIds = batchUnits.map((bu) => bu.unitId).toList();

      // Load actual translation units in one batch query (1 query instead of N)
      final unitsResult = await _unitRepository.getByIds(unitIds);
      if (unitsResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to load translation units: ${unitsResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      return Ok(unitsResult.unwrap());
    } catch (e, stackTrace) {
      _logger.error('Failed to load batch units', e, stackTrace);
      return Err(TranslationOrchestrationException(
        'Failed to load batch units: ${e.toString()}',
        batchId: batchId,
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

}

/// Exception thrown when batch is empty
class EmptyBatchException extends TranslationOrchestrationException {
  const EmptyBatchException(
    super.message, {
    super.batchId,
    super.error,
    super.stackTrace,
  });
}
