import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/batch_estimate.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Service for orchestrating complete translation workflows
///
/// This service coordinates the entire translation process:
/// 1. Translation Memory lookup (exact and fuzzy)
/// 2. LLM translation for units without TM matches
/// 3. Validation of translations
/// 4. Saving to database
/// 5. Updating Translation Memory
/// 6. Emitting progress events
///
/// The orchestrator handles parallel batch processing, error recovery,
/// pause/resume functionality, and comprehensive statistics tracking.
abstract class ITranslationOrchestrator {
  /// Translate a batch using the complete workflow
  ///
  /// Workflow:
  /// 1. Check TM for exact matches (100% - skip LLM)
  /// 2. Check TM for fuzzy matches (>=85% - use as suggestions)
  /// 3. Build contextual prompt with TM examples (few-shot learning)
  /// 4. Call LLM for remaining units
  /// 5. Validate LLM response
  /// 6. Save translations to database
  /// 7. Update Translation Memory
  /// 8. Emit domain events
  ///
  /// Returns a stream of [TranslationProgress] events for real-time updates.
  /// Final event will have status [TranslationProgressStatus.completed] or [TranslationProgressStatus.failed].
  ///
  /// Throws:
  /// - [TranslationOrchestrationException] if workflow fails
  /// - [EmptyBatchException] if batch has no units
  /// - [InvalidContextException] if context is invalid
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatch({
    required String batchId,
    required TranslationContext context,
  });

  /// Translate multiple batches in parallel
  ///
  /// Processes multiple batches concurrently with configurable parallelism.
  /// Each batch emits its own progress events independently.
  ///
  /// [maxParallel]: Maximum number of batches to process simultaneously (1-20)
  ///
  /// Returns a stream of progress events for all batches combined.
  /// Each event includes the batch ID to distinguish between batches.
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatchesParallel({
    required List<String> batchIds,
    required TranslationContext context,
    int maxParallel = 3,
  });

  /// Estimate tokens for a batch
  ///
  /// Calculates:
  /// - Total input/output tokens
  /// - TM reuse rate
  /// - Number of units requiring LLM
  /// - Estimated duration
  ///
  /// This is a read-only operation that doesn't modify any data.
  ///
  /// Throws:
  /// - [TranslationOrchestrationException] if estimation fails
  /// - [EmptyBatchException] if batch has no units
  Future<Result<BatchEstimate, TranslationOrchestrationException>>
      estimateBatch({
    required String batchId,
    required TranslationContext context,
  });

  /// Pause an ongoing translation batch
  ///
  /// The batch can be resumed later using [resumeTranslation].
  /// Current progress is saved and can be continued.
  ///
  /// Throws:
  /// - [TranslationOrchestrationException] if batch cannot be paused
  /// - [InvalidStateException] if batch is not in progress
  Future<Result<void, TranslationOrchestrationException>> pauseTranslation({
    required String batchId,
  });

  /// Resume a paused translation batch
  ///
  /// Continues from where it was paused. Already processed units are skipped.
  ///
  /// Throws:
  /// - [TranslationOrchestrationException] if batch cannot be resumed
  /// - [InvalidStateException] if batch is not paused
  Future<Result<void, TranslationOrchestrationException>> resumeTranslation({
    required String batchId,
  });

  /// Cancel an ongoing or paused translation batch
  ///
  /// This is a permanent operation. The batch cannot be resumed after cancellation.
  /// Partial progress is preserved in the database.
  ///
  /// Throws:
  /// - [TranslationOrchestrationException] if batch cannot be cancelled
  Future<Result<void, TranslationOrchestrationException>> cancelTranslation({
    required String batchId,
  });

  /// Stop a batch translation immediately
  ///
  /// Immediately cancels any ongoing LLM requests and stops the batch.
  /// This is more aggressive than cancelTranslation - it interrupts
  /// HTTP requests in progress.
  ///
  /// Use this when user wants to stop immediately without waiting.
  ///
  /// Returns [Ok(void)] on success or [Err(TranslationOrchestrationException)] on failure
  Future<Result<void, TranslationOrchestrationException>> stopTranslation({
    required String batchId,
  });

  /// Get current status of a translation batch
  ///
  /// Returns the latest progress information without starting or resuming translation.
  ///
  /// Returns null if batch doesn't exist or has never been started.
  Future<Result<TranslationProgress?, TranslationOrchestrationException>>
      getBatchStatus({
    required String batchId,
  });

  /// Check if a batch is currently being processed
  ///
  /// Returns true if the batch is in progress, paused, or queued.
  Future<bool> isBatchActive({
    required String batchId,
  });

  /// Get list of all active batches
  ///
  /// Returns batch IDs that are currently in progress, paused, or queued.
  Future<List<String>> getActiveBatches();

  /// Validate batch before translation
  ///
  /// Checks:
  /// - Batch exists and has units
  /// - Context is valid
  /// - API keys are configured
  /// - Batch size is within limits
  ///
  /// Returns list of validation errors, or empty list if valid.
  Future<List<ValidationError>> validateBatch({
    required String batchId,
    required TranslationContext context,
  });

  /// Get statistics for completed batches
  ///
  /// Aggregates metrics across multiple batches for analysis.
  ///
  /// [batchIds]: List of batch IDs to include, or null for all batches
  /// [since]: Only include batches completed after this timestamp
  Future<BatchStatistics> getBatchStatistics({
    List<String>? batchIds,
    DateTime? since,
  });
}

/// Aggregated statistics for translation batches
class BatchStatistics {
  /// Total number of batches included
  final int totalBatches;

  /// Total units processed across all batches
  final int totalUnitsProcessed;

  /// Total successful translations
  final int totalSuccessful;

  /// Total failed translations
  final int totalFailed;

  /// Total skipped (TM matches, etc.)
  final int totalSkipped;

  /// Total tokens used
  final int totalTokensUsed;

  /// Average TM reuse rate (0.0 - 1.0)
  final double averageTmReuseRate;

  /// Average processing time per unit (in seconds)
  final double averageTimePerUnit;

  /// Success rate (0.0 - 1.0)
  double get successRate => totalUnitsProcessed > 0
      ? totalSuccessful / totalUnitsProcessed
      : 0.0;

  const BatchStatistics({
    required this.totalBatches,
    required this.totalUnitsProcessed,
    required this.totalSuccessful,
    required this.totalFailed,
    required this.totalSkipped,
    required this.totalTokensUsed,
    required this.averageTmReuseRate,
    required this.averageTimePerUnit,
  });

  @override
  String toString() {
    return 'BatchStatistics(batches: $totalBatches, units: $totalUnitsProcessed, '
        'success: ${(successRate * 100).toStringAsFixed(1)}%, '
        'tokens: $totalTokensUsed, '
        'TM reuse: ${(averageTmReuseRate * 100).toStringAsFixed(1)}%)';
  }
}

/// Exception for invalid state operations
class InvalidStateException extends TranslationOrchestrationException {
  final String currentState;
  final String expectedState;

  const InvalidStateException(
    super.message,
    this.currentState,
    this.expectedState, {
    super.batchId,
    super.error,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'InvalidStateException: $message '
        '(Current: $currentState, Expected: $expectedState)';
  }
}
