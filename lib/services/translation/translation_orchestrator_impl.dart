import 'dart:async';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/services/concurrency/batch_isolation_manager.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
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
import 'package:twmt/services/translation/handlers/parallel_batch_handler.dart';
import 'package:twmt/services/translation/handlers/batch_estimation_handler.dart';

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
  final TranslationBatchRepository _batchRepository;
  // ignore: unused_field
  final BatchIsolationManager _isolationManager;
  final EventBus _eventBus;
  final LoggingService _logger;

  // Handlers
  final TmLookupHandler _tmLookupHandler;
  final LlmTranslationHandler _llmTranslationHandler;
  final ValidationPersistenceHandler _validationPersistenceHandler;
  final BatchProgressManager _batchProgressManager;
  final ParallelBatchHandler _parallelBatchHandler;
  final BatchEstimationHandler _batchEstimationHandler;

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
  })  : _batchRepository = batchRepository,
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
        ),
        _parallelBatchHandler = ParallelBatchHandler(
          logger: logger,
        ),
        _batchEstimationHandler = BatchEstimationHandler(
          llmService: llmService,
          promptBuilder: promptBuilder,
          batchRepository: batchRepository,
          batchUnitRepository: batchUnitRepository,
          unitRepository: unitRepository,
          logger: logger,
        );

  @override
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatch({
    required String batchId,
    required TranslationContext context,
  }) {
    // Use the StreamController as the single source of truth for progress updates.
    // This ensures all progress updates (from TM lookup, LLM translation, validation)
    // are emitted through the same stream that the UI is listening to.
    final controller = _batchProgressManager.getOrCreateController(batchId);

    // Run the translation in a separate async context
    _translateBatchInternal(batchId, context);

    return controller.stream;
  }

  /// Internal implementation of batch translation
  ///
  /// All progress updates are emitted through the batch controller's stream
  /// to ensure the UI receives all updates in real-time.
  Future<void> _translateBatchInternal(
    String batchId,
    TranslationContext context,
  ) async {
    _logger.info('Starting batch translation', {
      'batchId': batchId,
      'provider': context.providerId ?? 'default',
      'model': context.modelId ?? 'default',
    });

    // Track actual processing duration
    final startTime = DateTime.now();

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
      final validationErrors = await _batchEstimationHandler.validateBatch(
        batchId: batchId,
        context: context,
      );

      if (validationErrors.isNotEmpty) {
        final error = TranslationOrchestrationException(
          'Batch validation failed: ${validationErrors.map((e) => e.message).join(', ')}',
          batchId: batchId,
        );
        _batchProgressManager.getOrCreateController(batchId).add(Err(error));
        await _cleanupBatch(batchId);
        return;
      }

      // Load translation units from database
      final unitsResult = await _batchEstimationHandler.loadBatchUnits(batchId);
      if (unitsResult.isErr) {
        _batchProgressManager.getOrCreateController(batchId).add(Err(unitsResult.unwrapErr()));
        await _cleanupBatch(batchId);
        return;
      }

      final units = unitsResult.unwrap();
      if (units.isEmpty) {
        _batchProgressManager.getOrCreateController(batchId).add(
          Err(EmptyBatchException('Batch has no units', batchId: batchId)),
        );
        await _cleanupBatch(batchId);
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
        phaseDetail: 'Loading ${units.length} translation units...',
        tokensUsed: 0,
        tmReuseRate: 0.0,
        timestamp: DateTime.now(),
      );

      _batchProgressManager.updateAndEmitProgress(batchId, initialProgress);

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
        onProgressUpdate: (batchId, progress) {
          _batchProgressManager.updateAndEmitProgress(batchId, progress);
        },
      );
      _batchProgressManager.updateAndEmitProgress(batchId, currentProgress);
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
        getCancellationToken: (batchId) =>
            _batchProgressManager.getCancellationToken(batchId),
        onProgressUpdate: (batchId, progress) {
          _batchProgressManager.updateAndEmitProgress(batchId, progress);
        },
        checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
        // Progressive save callback - saves immediately after each LLM sub-batch
        onSubBatchTranslated: (subBatchUnits, translations) async {
          final progressBeforeSave =
              _batchProgressManager.getProgress(batchId) ?? currentProgress;
          await _validationPersistenceHandler.validateAndSave(
            translations: translations,
            batchId: batchId,
            units: subBatchUnits,
            context: context,
            currentProgress: progressBeforeSave,
            checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
            onProgressUpdate: (batchId, progress) {
              _batchProgressManager.updateAndEmitProgress(batchId, progress);
            },
          );
          // Track saved unit IDs
          savedUnitIds.addAll(translations.keys);
        },
      );
      currentProgress =
          _batchProgressManager.getProgress(batchId) ?? progressAfterLlm;
      _batchProgressManager.updateAndEmitProgress(batchId, currentProgress);
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

        final remainingUnits =
            units.where((u) => remainingTranslations.containsKey(u.id)).toList();
        currentProgress = await _validationPersistenceHandler.validateAndSave(
          translations: remainingTranslations,
          batchId: batchId,
          units: remainingUnits,
          context: context,
          currentProgress: currentProgress,
          checkPauseOrCancel: _batchProgressManager.checkPauseOrCancel,
          onProgressUpdate: (batchId, progress) {
            _batchProgressManager.updateAndEmitProgress(batchId, progress);
          },
        );
        _batchProgressManager.updateAndEmitProgress(batchId, currentProgress);
      }

      // Mark as completed
      final successRate = units.isNotEmpty 
          ? ((currentProgress.successfulUnits / units.length) * 100).round() 
          : 0;
      final completedProgress = currentProgress.copyWith(
        status: TranslationProgressStatus.completed,
        currentPhase: TranslationPhase.completed,
        phaseDetail: 'Batch complete: ${currentProgress.successfulUnits}/${units.length} translations ($successRate% success)',
        processedUnits: units.length,
        timestamp: DateTime.now(),
      );

      _batchProgressManager.updateAndEmitProgress(batchId, completedProgress);

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
      await _handleCancellationInternal(batchId, context, e);
    } catch (e, stackTrace) {
      await _handleErrorInternal(batchId, context, batch, e, stackTrace);
    } finally {
      await _cleanupBatch(batchId);
    }
  }

  /// Handle batch cancellation (internal version using controller)
  Future<void> _handleCancellationInternal(
    String batchId,
    TranslationContext context,
    CancelledException e,
  ) async {
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

    _batchProgressManager.updateAndEmitProgress(batchId, cancelledProgress);

    _eventBus.publish(BatchCancelledEvent(
      batchId: batchId,
      projectLanguageId: context.projectLanguageId,
      completedUnits: _batchProgressManager.getProgress(batchId)?.successfulUnits ?? 0,
      totalUnits: _batchProgressManager.getProgress(batchId)?.totalUnits ?? 0,
      reason: e.message,
    ));

    _logger.info('Batch translation cancelled', {'batchId': batchId});
  }

  /// Handle batch error (internal version using controller)
  Future<void> _handleErrorInternal(
    String batchId,
    TranslationContext context,
    TranslationBatch? batch,
    Object e,
    StackTrace stackTrace,
  ) async {
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

    _batchProgressManager.updateAndEmitProgress(batchId, errorProgress);

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
      completedBeforeFailure:
          _batchProgressManager.getProgress(batchId)?.successfulUnits ?? 0,
      totalUnits: _batchProgressManager.getProgress(batchId)?.totalUnits ?? 0,
      retryCount: retryCount,
    ));
  }

  /// Cleanup batch state after completion/failure/cancellation
  Future<void> _cleanupBatch(String batchId) async {
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

  @override
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatchesParallel({
    required List<String> batchIds,
    required TranslationContext context,
    int maxParallel = AppConstants.maxParallelBatches,
  }) {
    return _parallelBatchHandler.translateBatchesParallel(
      batchIds: batchIds,
      context: context,
      maxParallel: maxParallel,
      translateBatch: translateBatch,
    );
  }

  @override
  Future<Result<BatchEstimate, TranslationOrchestrationException>>
      estimateBatch({
    required String batchId,
    required TranslationContext context,
  }) async {
    // Load units from database
    final unitsResult = await _batchEstimationHandler.loadBatchUnits(batchId);
    if (unitsResult.isErr) {
      return Err(unitsResult.unwrapErr());
    }

    return _batchEstimationHandler.estimateBatch(
      batchId: batchId,
      units: unitsResult.unwrap(),
      context: context,
      isUnitTranslated: _tmLookupHandler.isUnitTranslated,
    );
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
    return _batchEstimationHandler.validateBatch(
      batchId: batchId,
      context: context,
    );
  }

  @override
  Future<BatchStatistics> getBatchStatistics({
    List<String>? batchIds,
    DateTime? since,
  }) async {
    return _batchEstimationHandler.getBatchStatistics(
      batchIds: batchIds,
      since: since,
    );
  }
}
