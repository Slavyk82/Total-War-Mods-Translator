import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../services/shared/event_bus.dart';
import '../../models/events/batch_events.dart';
import '../../models/events/translation_events.dart';
import '../../models/events/project_events.dart';
import '../../models/events/tm_events.dart';

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

// ========== Translation Event Streams ==========

@riverpod
Stream<TranslationAddedEvent> translationAddedEvents(Ref ref) {
  return EventBus.instance.on<TranslationAddedEvent>();
}

@riverpod
Stream<TranslationEditedEvent> translationEditedEvents(Ref ref) {
  return EventBus.instance.on<TranslationEditedEvent>();
}

@riverpod
Stream<TranslationValidatedEvent> translationValidatedEvents(Ref ref) {
  return EventBus.instance.on<TranslationValidatedEvent>();
}

@riverpod
Stream<TranslationDeletedEvent> translationDeletedEvents(Ref ref) {
  return EventBus.instance.on<TranslationDeletedEvent>();
}

@riverpod
Stream<TranslationStatusChangedEvent> translationStatusChangedEvents(Ref ref) {
  return EventBus.instance.on<TranslationStatusChangedEvent>();
}

// ========== Project Event Streams ==========

@riverpod
Stream<ProjectCreatedEvent> projectCreatedEvents(Ref ref) {
  return EventBus.instance.on<ProjectCreatedEvent>();
}

@riverpod
Stream<ProjectUpdatedEvent> projectUpdatedEvents(Ref ref) {
  return EventBus.instance.on<ProjectUpdatedEvent>();
}

@riverpod
Stream<ProjectCompletedEvent> projectCompletedEvents(Ref ref) {
  return EventBus.instance.on<ProjectCompletedEvent>();
}

// ========== TM Event Streams ==========

@riverpod
Stream<TranslationAddedToTmEvent> translationAddedToTmEvents(Ref ref) {
  return EventBus.instance.on<TranslationAddedToTmEvent>();
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

/// Get all events for a specific project
@riverpod
Stream<ProjectEvent> projectEvents(
  Ref ref,
  String projectId,
) {
  return EventBus.instance.on<ProjectEvent>().where(
        (event) => event.projectId == projectId,
      );
}
