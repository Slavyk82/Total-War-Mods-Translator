import 'dart:async';
import 'dart:collection';
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
  /// [maxParallel]: Maximum concurrent batches (clamped to 1-20)
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

    // Use StreamController for result aggregation
    final controller = StreamController<
        Result<TranslationProgress, TranslationOrchestrationException>>();
    final activeFutures = <Future<void>>[];
    var activeCount = 0;
    var completedCount = 0;
    var hasError = false;

    // Queue of completers for proper slot signaling (FIFO order)
    // Each waiter gets its own completer to prevent race conditions
    final slotWaiters = Queue<Completer<void>>();

    /// Signal that a slot has become available
    void signalSlotAvailable() {
      if (slotWaiters.isNotEmpty) {
        final waiter = slotWaiters.removeFirst();
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
    }

    /// Wait for a slot to become available
    Future<void> waitForSlot() async {
      final completer = Completer<void>();
      slotWaiters.add(completer);
      await completer.future;
    }

    // Process batches maintaining parallel limit
    Future<void> processBatches() async {
      try {
        for (final batchId in batchIds) {
          // Check if consumer cancelled the stream
          if (controller.isClosed) {
            _logger.info('Stream cancelled by consumer, stopping batch processing');
            break;
          }

          // Wait if we've hit the parallelism limit
          while (activeCount >= parallelism) {
            await waitForSlot();
          }

          // Increment active count before starting
          activeCount++;

          // Start batch processing (don't await - run in parallel)
          final future = _processBatchWithStreaming(
            batchId,
            context,
            controller,
            translateBatch,
          ).then((_) {
            completedCount++;
            _logger.info('Batch completed ($completedCount/${batchIds.length})', {
              'batchId': batchId,
            });
          }).catchError((Object error, StackTrace stackTrace) {
            hasError = true;
            _logger.error('Batch failed in parallel execution', error, stackTrace);
            // Propagate error to the stream so caller knows which batch failed
            if (!controller.isClosed) {
              controller.add(Err(TranslationOrchestrationException(
                'Batch $batchId failed: $error',
                error: error,
                stackTrace: stackTrace,
              )));
            }
          }).whenComplete(() {
            // Decrement active count and signal slot available
            activeCount--;
            signalSlotAvailable();
          });

          activeFutures.add(future);
        }

        // Wait for all remaining batches to complete
        if (activeFutures.isNotEmpty) {
          await Future.wait(activeFutures, eagerError: false);
        }
      } finally {
        // Always close the controller when done
        if (!controller.isClosed) {
          await controller.close();
        }

        // Complete any remaining waiters to prevent hanging
        while (slotWaiters.isNotEmpty) {
          final waiter = slotWaiters.removeFirst();
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }

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
    // Use try-finally to ensure cleanup if the consumer cancels the stream
    try {
      await for (final result in controller.stream) {
        yield result;
      }
    } finally {
      // If consumer cancelled early, close the controller to stop processing
      if (!controller.isClosed) {
        await controller.close();
      }
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
