import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../events/event_stream_providers.dart';
import 'batch_state_provider.dart';

part 'active_batches_provider.g.dart';

/// Tracks all active batches across the application
@riverpod
class ActiveBatches extends _$ActiveBatches {
  @override
  Map<String, BatchState> build() {
    final initialBatches = <String, BatchState>{};

    // Listen to batch lifecycle events
    _listenToEvents();

    return initialBatches;
  }

  void _listenToEvents() {
    // Add batch when started
    ref.listen(
      batchStartedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          state = {
            ...state,
            event.batchId: BatchState(
              batchId: event.batchId,
              status: BatchStatus.running,
              totalUnits: event.totalUnits,
              batchNumber: event.batchNumber,
              projectLanguageId: event.projectLanguageId,
              startedAt: event.timestamp,
            ),
          };
        }
      },
    );

    // Update progress
    ref.listen(
      batchProgressEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          final current = state[event.batchId];
          if (current != null) {
            state = {
              ...state,
              event.batchId: current.copyWith(
                completedUnits: event.completedUnits,
                failedUnits: event.failedUnits,
                progressPercent: event.progressPercent,
              ),
            };
          }
        }
      },
    );

    // Update when paused
    ref.listen(
      batchPausedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          final current = state[event.batchId];
          if (current != null) {
            state = {
              ...state,
              event.batchId: current.copyWith(
                status: BatchStatus.paused,
              ),
            };
          }
        }
      },
    );

    // Update when resumed
    ref.listen(
      batchResumedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          final current = state[event.batchId];
          if (current != null) {
            state = {
              ...state,
              event.batchId: current.copyWith(
                status: BatchStatus.running,
              ),
            };
          }
        }
      },
    );

    // Remove batch when completed
    ref.listen(
      batchCompletedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final newState = Map<String, BatchState>.from(state);
          newState.remove(next.value!.batchId);
          state = newState;
        }
      },
    );

    // Remove batch when failed
    ref.listen(
      batchFailedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final newState = Map<String, BatchState>.from(state);
          newState.remove(next.value!.batchId);
          state = newState;
        }
      },
    );

    // Remove batch when cancelled
    ref.listen(
      batchCancelledEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final newState = Map<String, BatchState>.from(state);
          newState.remove(next.value!.batchId);
          state = newState;
        }
      },
    );
  }

  /// Number of currently active batches
  int get activeCount => state.length;

  /// Check if there are any active batches
  bool get hasActiveBatches => state.isNotEmpty;

  /// Get list of all active batches
  List<BatchState> get activeBatchList => state.values.toList();

  /// Get batch by ID
  BatchState? getBatch(String batchId) => state[batchId];

  /// Check if a specific batch is active
  bool isBatchActive(String batchId) => state.containsKey(batchId);
}
