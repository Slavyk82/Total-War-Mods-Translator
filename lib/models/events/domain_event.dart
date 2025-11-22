import 'package:uuid/uuid.dart';

/// Base class for all domain events in TWMT.
///
/// Domain events represent significant occurrences in the domain that
/// other parts of the system might be interested in. Events are immutable
/// and include a unique ID and timestamp.
///
/// All domain events should extend this class.
abstract class DomainEvent {
  /// Unique identifier for this event instance
  final String eventId;

  /// Timestamp when the event occurred (Unix epoch milliseconds)
  final DateTime timestamp;

  const DomainEvent({
    required this.eventId,
    required this.timestamp,
  });

  /// Create a new event with generated ID and current timestamp
  DomainEvent.now()
      : eventId = const Uuid().v4(),
        timestamp = DateTime.now();

  /// Event type name (used for logging and debugging)
  String get eventType => runtimeType.toString();

  /// Timestamp when the event occurred (alias for compatibility)
  DateTime get occurredAt => timestamp;

  /// Convert event to JSON (must be implemented by subclasses)
  Map<String, dynamic> toJson();

  @override
  String toString() => '$eventType(id: $eventId, timestamp: $timestamp)';
}
