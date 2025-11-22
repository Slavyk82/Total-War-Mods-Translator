import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../events/event_stream_providers.dart';

part 'batch_state_provider.g.dart';

/// Represents the current state of a translation batch
class BatchState {
  final String batchId;
  final BatchStatus status;
  final int totalUnits;
  final int completedUnits;
  final int failedUnits;
  final double progressPercent;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int batchNumber;
  final String? projectLanguageId;

  const BatchState({
    required this.batchId,
    required this.status,
    this.totalUnits = 0,
    this.completedUnits = 0,
    this.failedUnits = 0,
    this.progressPercent = 0.0,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
    this.batchNumber = 0,
    this.projectLanguageId,
  });

  BatchState copyWith({
    BatchStatus? status,
    int? totalUnits,
    int? completedUnits,
    int? failedUnits,
    double? progressPercent,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
    int? batchNumber,
    String? projectLanguageId,
  }) {
    return BatchState(
      batchId: batchId,
      status: status ?? this.status,
      totalUnits: totalUnits ?? this.totalUnits,
      completedUnits: completedUnits ?? this.completedUnits,
      failedUnits: failedUnits ?? this.failedUnits,
      progressPercent: progressPercent ?? this.progressPercent,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      batchNumber: batchNumber ?? this.batchNumber,
      projectLanguageId: projectLanguageId ?? this.projectLanguageId,
    );
  }

  bool get isActive =>
      status == BatchStatus.running || status == BatchStatus.paused;
  bool get isComplete =>
      status == BatchStatus.completed ||
      status == BatchStatus.failed ||
      status == BatchStatus.cancelled;
  bool get hasErrors => failedUnits > 0;
  int get remainingUnits => totalUnits - completedUnits - failedUnits;
}

enum BatchStatus {
  idle,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

/// Provider that maintains state for a specific batch by listening to events
@riverpod
class BatchStateNotifier extends _$BatchStateNotifier {
  @override
  BatchState build(String batchId) {
    // Initial state
    final initialState = BatchState(
      batchId: batchId,
      status: BatchStatus.idle,
    );

    // Listen to batch events and update state accordingly
    _listenToEvents();

    return initialState;
  }

  void _listenToEvents() {
    // Listen to BatchStartedEvent
    ref.listen(
      batchStartedEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          final event = next.value!;
          state = state.copyWith(
            status: BatchStatus.running,
            totalUnits: event.totalUnits,
            batchNumber: event.batchNumber,
            projectLanguageId: event.projectLanguageId,
            startedAt: event.timestamp,
          );
        }
      },
    );

    // Listen to BatchProgressEvent
    ref.listen(
      batchProgressEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          final event = next.value!;
          state = state.copyWith(
            completedUnits: event.completedUnits,
            failedUnits: event.failedUnits,
            progressPercent: event.progressPercent,
          );
        }
      },
    );

    // Listen to BatchCompletedEvent
    ref.listen(
      batchCompletedEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          final event = next.value!;
          state = state.copyWith(
            status: BatchStatus.completed,
            completedUnits: event.completedUnits,
            failedUnits: event.failedUnits,
            completedAt: event.timestamp,
          );
        }
      },
    );

    // Listen to BatchFailedEvent
    ref.listen(
      batchFailedEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          final event = next.value!;
          state = state.copyWith(
            status: BatchStatus.failed,
            errorMessage: event.errorMessage,
            completedAt: event.timestamp,
          );
        }
      },
    );

    // Listen to BatchPausedEvent
    ref.listen(
      batchPausedEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          state = state.copyWith(
            status: BatchStatus.paused,
          );
        }
      },
    );

    // Listen to BatchResumedEvent
    ref.listen(
      batchResumedEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          state = state.copyWith(
            status: BatchStatus.running,
          );
        }
      },
    );

    // Listen to BatchCancelledEvent
    ref.listen(
      batchCancelledEventsProvider,
      (previous, next) {
        if (next.hasValue && next.value?.batchId == batchId) {
          state = state.copyWith(
            status: BatchStatus.cancelled,
            completedAt: next.value!.timestamp,
          );
        }
      },
    );
  }
}
