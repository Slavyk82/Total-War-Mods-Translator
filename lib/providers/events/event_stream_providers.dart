import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../services/shared/event_bus.dart';
import '../../models/events/batch_events.dart';

part 'event_stream_providers.g.dart';

/// Event stream providers expose typed event streams from EventBus
///
/// These providers are lightweight adapters that don't hold state.
/// They enable selective subscription to specific event types.

// ========== Batch Event Streams ==========

@riverpod
Stream<BatchStartedEvent> batchStartedEvents(Ref ref) {
  return EventBus.instance.on<BatchStartedEvent>();
}

@riverpod
Stream<BatchProgressEvent> batchProgressEvents(Ref ref) {
  return EventBus.instance.on<BatchProgressEvent>();
}

@riverpod
Stream<BatchCompletedEvent> batchCompletedEvents(Ref ref) {
  return EventBus.instance.on<BatchCompletedEvent>();
}

@riverpod
Stream<BatchFailedEvent> batchFailedEvents(Ref ref) {
  return EventBus.instance.on<BatchFailedEvent>();
}

@riverpod
Stream<BatchPausedEvent> batchPausedEvents(Ref ref) {
  return EventBus.instance.on<BatchPausedEvent>();
}

@riverpod
Stream<BatchResumedEvent> batchResumedEvents(Ref ref) {
  return EventBus.instance.on<BatchResumedEvent>();
}

@riverpod
Stream<BatchCancelledEvent> batchCancelledEvents(Ref ref) {
  return EventBus.instance.on<BatchCancelledEvent>();
}

// ========== Filtered Event Streams ==========

/// Get progress events for a specific batch
@riverpod
Stream<BatchProgressEvent> batchProgressForBatch(
  Ref ref,
  String batchId,
) {
  return EventBus.instance
      .on<BatchProgressEvent>()
      .where((event) => event.batchId == batchId);
}

/// Get completion events for a specific batch
@riverpod
Stream<BatchCompletedEvent> batchCompletedForBatch(
  Ref ref,
  String batchId,
) {
  return EventBus.instance
      .on<BatchCompletedEvent>()
      .where((event) => event.batchId == batchId);
}

/// Get failure events for a specific batch
@riverpod
Stream<BatchFailedEvent> batchFailedForBatch(
  Ref ref,
  String batchId,
) {
  return EventBus.instance
      .on<BatchFailedEvent>()
      .where((event) => event.batchId == batchId);
}
