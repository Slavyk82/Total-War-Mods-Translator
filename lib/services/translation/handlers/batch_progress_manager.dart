import 'dart:async';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/llm/models/llm_cancellation_token.dart';

/// Manages batch translation progress, state, and lifecycle
///
/// Responsibilities:
/// - Track active batch states (in-memory)
/// - Handle pause/resume/cancel/stop operations
/// - Check pause/cancel flags during processing
/// - Manage batch stream controllers
/// - Manage LLM cancellation tokens
/// - Emit domain events for batch lifecycle
/// - Clean up batch state after completion
class BatchProgressManager {
  final TranslationBatchRepository _batchRepository;
  final EventBus _eventBus;
  final LoggingService _logger;

  /// Active batch states (in-memory tracking)
  final Map<String, TranslationProgress> _activeBatches = {};

  /// Pause flags (batchId -> paused)
  final Set<String> _pausedBatches = {};

  /// Cancellation flags (batchId -> cancelled)
  final Set<String> _cancelledBatches = {};

  /// Stop flags (batchId -> stopped immediately)
  final Set<String> _stoppedBatches = {};

  /// Resume completers for paused batches (batchId -> completer)
  final Map<String, Completer<void>> _resumeCompleters = {};

  /// LLM cancellation tokens for active batches
  final Map<String, LlmCancellationToken> _cancellationTokens = {};

  /// Stream controllers for each active batch
  final Map<String,
          StreamController<Result<TranslationProgress, TranslationOrchestrationException>>>
      _batchControllers = {};

  BatchProgressManager({
    required TranslationBatchRepository batchRepository,
    required EventBus eventBus,
    required LoggingService logger,
  })  : _batchRepository = batchRepository,
        _eventBus = eventBus,
        _logger = logger;

  /// Get or create stream controller for a batch
  StreamController<Result<TranslationProgress, TranslationOrchestrationException>>
      getOrCreateController(String batchId) {
    return _batchControllers.putIfAbsent(
      batchId,
      () => StreamController<Result<TranslationProgress, TranslationOrchestrationException>>.broadcast(),
    );
  }

  /// Get or create cancellation token for a batch
  LlmCancellationToken getOrCreateCancellationToken(String batchId) {
    return _cancellationTokens.putIfAbsent(
      batchId,
      () => LlmCancellationToken(),
    );
  }

  /// Get cancellation token for a batch (if exists)
  LlmCancellationToken? getCancellationToken(String batchId) {
    return _cancellationTokens[batchId];
  }

  /// Update active batch progress
  void updateProgress(String batchId, TranslationProgress progress) {
    _activeBatches[batchId] = progress;
  }

  /// Update progress and emit to stream
  void updateAndEmitProgress(String batchId, TranslationProgress progress) {
    _activeBatches[batchId] = progress;
    _batchControllers[batchId]?.add(Ok(progress));
  }

  /// Get current progress for a batch
  TranslationProgress? getProgress(String batchId) {
    return _activeBatches[batchId];
  }

  /// Pause translation batch
  Future<Result<void, TranslationOrchestrationException>> pause({
    required String batchId,
  }) async {
    try {
      final progress = _activeBatches[batchId];

      if (progress == null) {
        return Err(
          InvalidStateException(
            'Cannot pause batch that is not in progress',
            'not_active',
            'in_progress',
            batchId: batchId,
          ),
        );
      }

      if (progress.status == TranslationProgressStatus.paused) {
        return Err(
          InvalidStateException(
            'Batch is already paused',
            'paused',
            'in_progress',
            batchId: batchId,
          ),
        );
      }

      _pausedBatches.add(batchId);

      // Create resume completer for efficient waiting
      _resumeCompleters[batchId] = Completer<void>();

      // Update progress state
      final pausedProgress = progress.copyWith(
        status: TranslationProgressStatus.paused,
        timestamp: DateTime.now(),
      );
      _activeBatches[batchId] = pausedProgress;

      // Get batch to retrieve projectLanguageId
      final batchResult = await _batchRepository.getById(batchId);
      final batch = batchResult.isOk ? batchResult.unwrap() : null;

      // Emit pause event
      _eventBus.publish(BatchPausedEvent(
        batchId: batchId,
        projectLanguageId: batch?.projectLanguageId ?? '',
        completedUnits: progress.successfulUnits,
        totalUnits: progress.totalUnits,
      ));

      _logger.info('Batch translation paused', {'batchId': batchId});

      return Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to pause translation', e, stackTrace);
      return Err(
        TranslationOrchestrationException(
          'Failed to pause translation: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Resume paused translation batch
  Future<Result<void, TranslationOrchestrationException>> resume({
    required String batchId,
  }) async {
    try {
      if (!_pausedBatches.contains(batchId)) {
        return Err(
          InvalidStateException(
            'Cannot resume batch that is not paused',
            'not_paused',
            'paused',
            batchId: batchId,
          ),
        );
      }

      _pausedBatches.remove(batchId);

      // Complete the resume completer to wake up waiting operations
      final completer = _resumeCompleters.remove(batchId);
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }

      // Update progress state
      final progress = _activeBatches[batchId];
      if (progress != null) {
        final resumedProgress = progress.copyWith(
          status: TranslationProgressStatus.inProgress,
          timestamp: DateTime.now(),
        );
        _activeBatches[batchId] = resumedProgress;
      }

      // Get batch to retrieve projectLanguageId
      final batchResult = await _batchRepository.getById(batchId);
      final batch = batchResult.isOk ? batchResult.unwrap() : null;

      // Emit resume event
      _eventBus.publish(BatchResumedEvent(
        batchId: batchId,
        projectLanguageId: batch?.projectLanguageId ?? '',
        completedUnits: progress?.successfulUnits ?? 0,
        totalUnits: progress?.totalUnits ?? 0,
      ));

      _logger.info('Batch translation resumed', {'batchId': batchId});

      return Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to resume translation', e, stackTrace);
      return Err(
        TranslationOrchestrationException(
          'Failed to resume translation: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Cancel translation batch
  Future<Result<void, TranslationOrchestrationException>> cancel({
    required String batchId,
  }) async {
    try {
      _cancelledBatches.add(batchId);
      _pausedBatches.remove(batchId);

      // Get batch to retrieve projectLanguageId
      final batchResult = await _batchRepository.getById(batchId);
      final batch = batchResult.isOk ? batchResult.unwrap() : null;

      // Emit cancel event
      final progress = _activeBatches[batchId];
      _eventBus.publish(BatchCancelledEvent(
        batchId: batchId,
        projectLanguageId: batch?.projectLanguageId ?? '',
        completedUnits: progress?.successfulUnits ?? 0,
        totalUnits: progress?.totalUnits ?? 0,
        reason: 'User cancelled',
      ));

      _logger.info('Batch translation cancelled', {'batchId': batchId});

      return Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to cancel translation', e, stackTrace);
      return Err(
        TranslationOrchestrationException(
          'Failed to cancel translation: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get current status of a batch
  Future<Result<TranslationProgress?, TranslationOrchestrationException>>
      getStatus({
    required String batchId,
  }) async {
    try {
      final progress = _activeBatches[batchId];
      return Ok(progress);
    } catch (e, stackTrace) {
      return Err(
        TranslationOrchestrationException(
          'Failed to get batch status: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Check if a batch is currently active
  Future<bool> isActive({
    required String batchId,
  }) async {
    return _activeBatches.containsKey(batchId) ||
        _pausedBatches.contains(batchId);
  }

  /// Get list of all active batch IDs
  Future<List<String>> getActiveBatchIds() async {
    return _activeBatches.keys.toList();
  }

  /// Stop translation immediately without confirmation
  ///
  /// This cancels the LLM request in progress and marks batch as cancelled.
  Future<Result<void, TranslationOrchestrationException>> stop({
    required String batchId,
  }) async {
    try {
      _stoppedBatches.add(batchId);
      _cancelledBatches.add(batchId);
      _pausedBatches.remove(batchId);

      // Cancel LLM request immediately
      final token = _cancellationTokens[batchId];
      token?.cancel('Stopped by user');

      // Get batch to retrieve projectLanguageId
      final batchResult = await _batchRepository.getById(batchId);
      final batch = batchResult.isOk ? batchResult.unwrap() : null;

      // Emit stop event
      final progress = _activeBatches[batchId];
      _eventBus.publish(BatchCancelledEvent(
        batchId: batchId,
        projectLanguageId: batch?.projectLanguageId ?? '',
        completedUnits: progress?.successfulUnits ?? 0,
        totalUnits: progress?.totalUnits ?? 0,
        reason: 'Stopped immediately by user',
      ));

      _logger.info('Batch translation stopped immediately', {'batchId': batchId});

      return Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Failed to stop translation', e, stackTrace);
      return Err(
        TranslationOrchestrationException(
          'Failed to stop translation: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Check if batch is paused, cancelled, or stopped
  ///
  /// Waits efficiently while paused using Completer instead of polling.
  /// Throws CancelledException if cancelled or stopped.
  Future<void> checkPauseOrCancel(String batchId) async {
    // Check for stop (immediate cancellation)
    if (_stoppedBatches.contains(batchId)) {
      throw CancelledException('Batch was stopped immediately', batchId: batchId);
    }

    // Check for cancellation
    if (_cancelledBatches.contains(batchId)) {
      throw CancelledException('Batch was cancelled', batchId: batchId);
    }

    // Wait efficiently if paused
    if (_pausedBatches.contains(batchId)) {
      final completer = _resumeCompleters[batchId];
      if (completer != null) {
        // Wait for resume() to complete the completer
        await completer.future;
      }
    }

    // Check cancellation again after resume
    if (_cancelledBatches.contains(batchId) || _stoppedBatches.contains(batchId)) {
      throw CancelledException('Batch was cancelled', batchId: batchId);
    }
  }

  /// Clean up batch state after completion/failure/cancellation
  void cleanup(String batchId) {
    _activeBatches.remove(batchId);
    _pausedBatches.remove(batchId);
    _cancelledBatches.remove(batchId);
    _stoppedBatches.remove(batchId);

    // Complete any pending resume completer
    final completer = _resumeCompleters.remove(batchId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    // Cancel and remove cancellation token
    final token = _cancellationTokens.remove(batchId);
    token?.cancel();

    // Close stream controller
    final controller = _batchControllers.remove(batchId);
    controller?.close();
  }
}

/// Exception thrown when batch is cancelled
class CancelledException extends TranslationOrchestrationException {
  const CancelledException(
    super.message, {
    super.batchId,
    super.error,
    super.stackTrace,
  });
}
