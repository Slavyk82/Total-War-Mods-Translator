import 'dart:async';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

/// Signature for translating a single batch
typedef BatchTranslator = Stream<Result<TranslationProgress, TranslationOrchestrationException>> Function({
  required String batchId,
  required TranslationContext context,
});

/// Handles parallel batch translation orchestration
///
/// Responsibilities:
/// - Manage concurrent batch processing with configurable parallelism
/// - Forward progress events from multiple batches to a single stream
/// - Track completion state across all batches
class ParallelBatchHandler {
  final LoggingService _logger;

  ParallelBatchHandler({
    required LoggingService logger,
  }) : _logger = logger;

  /// Translate multiple batches in parallel with controlled concurrency
  ///
  /// [batchIds]: List of batch IDs to process
  /// [context]: Translation context for all batches
  /// [maxParallel]: Maximum concurrent batches (clamped to 1-10)
  /// [translateBatch]: Function to translate a single batch
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatchesParallel({
    required List<String> batchIds,
    required TranslationContext context,
    int maxParallel = AppConstants.maxParallelBatches,
    required BatchTranslator translateBatch,
  }) async* {
    _logger.info('Starting parallel batch translation', {
      'batchCount': batchIds.length,
      'maxParallel': maxParallel,
    });

    // Validate maxParallel
    final parallelism = maxParallel.clamp(1, AppConstants.maxParallelBatchLimit);

    // Use proper semaphore pattern with Completers to track completion
    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();
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
            translateBatch,
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
    StreamController<Result<TranslationProgress, TranslationOrchestrationException>>
        controller,
    BatchTranslator translateBatch,
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
}
