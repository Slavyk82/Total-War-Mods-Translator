import 'dart:async';

import '../../models/events/domain_event.dart';

/// Event bus for publishing and subscribing to domain events.
///
/// This service implements the publish-subscribe pattern for domain events,
/// allowing decoupled communication between different parts of the application.
///
/// Example:
/// ```dart
/// // Subscribe to batch events
/// eventBus.on<BatchCompletedEvent>().listen((event) {
///   print('Batch ${event.batchId} completed');
/// });
///
/// // Publish an event
/// eventBus.publish(BatchCompletedEvent(...));
/// ```
class EventBus {
  EventBus._();

  static final EventBus _instance = EventBus._();
  static EventBus get instance => _instance;

  final StreamController<DomainEvent> _controller =
      StreamController<DomainEvent>.broadcast();

  /// Subscribe to events of a specific type.
  ///
  /// Returns a stream that emits only events of type [T].
  ///
  /// Example:
  /// ```dart
  /// eventBus.on<BatchStartedEvent>().listen((event) {
  ///   print('Batch started: ${event.batchId}');
  /// });
  /// ```
  Stream<T> on<T extends DomainEvent>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  /// Subscribe to all domain events.
  ///
  /// Returns a stream that emits all events published through the bus.
  Stream<DomainEvent> get events => _controller.stream;

  /// Publish a domain event.
  ///
  /// The event will be broadcast to all subscribers listening for this
  /// event type or all events.
  ///
  /// Example:
  /// ```dart
  /// eventBus.publish(BatchCompletedEvent(...));
  /// ```
  Future<void> publish(DomainEvent event) async {
    _controller.add(event);
  }

  /// Publish a domain event synchronously.
  ///
  /// Use this for high-frequency events where awaiting is unnecessary.
  void publishSync(DomainEvent event) {
    _controller.add(event);
  }

  /// Close the event bus and clean up resources.
  ///
  /// This should be called when the application is shutting down.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Get the number of active event listeners
  int get listenerCount => _controller.hasListener ? 1 : 0;

  /// Check if there are any active listeners
  bool get hasListeners => _controller.hasListener;
}
