import 'package:json_annotation/json_annotation.dart';

part 'event_record.g.dart';

/// Persisted event record for audit trail and replay
///
/// Stores domain events in the database for:
/// - Audit trail (who did what when)
/// - Event replay for debugging
/// - Event sourcing patterns
@JsonSerializable()
class EventRecord {
  /// Unique event record ID
  final String id;

  /// Event type (e.g., 'BatchCompletedEvent')
  final String eventType;

  /// Event payload as JSON
  final Map<String, dynamic> payload;

  /// When the event occurred
  final DateTime occurredAt;

  /// User or system that triggered the event
  final String? triggeredBy;

  /// Aggregate ID (e.g., batch ID, project ID)
  final String? aggregateId;

  /// Aggregate type (e.g., 'TranslationBatch', 'Project')
  final String? aggregateType;

  /// Optional correlation ID for tracking related events
  final String? correlationId;

  /// Optional causation ID (ID of event that caused this event)
  final String? causationId;

  /// Event metadata (IP address, user agent, etc.)
  final Map<String, dynamic>? metadata;

  const EventRecord({
    required this.id,
    required this.eventType,
    required this.payload,
    required this.occurredAt,
    this.triggeredBy,
    this.aggregateId,
    this.aggregateType,
    this.correlationId,
    this.causationId,
    this.metadata,
  });

  factory EventRecord.fromJson(Map<String, dynamic> json) =>
      _$EventRecordFromJson(json);

  Map<String, dynamic> toJson() => _$EventRecordToJson(this);

  EventRecord copyWith({
    String? id,
    String? eventType,
    Map<String, dynamic>? payload,
    DateTime? occurredAt,
    String? triggeredBy,
    String? aggregateId,
    String? aggregateType,
    String? correlationId,
    String? causationId,
    Map<String, dynamic>? metadata,
  }) {
    return EventRecord(
      id: id ?? this.id,
      eventType: eventType ?? this.eventType,
      payload: payload ?? this.payload,
      occurredAt: occurredAt ?? this.occurredAt,
      triggeredBy: triggeredBy ?? this.triggeredBy,
      aggregateId: aggregateId ?? this.aggregateId,
      aggregateType: aggregateType ?? this.aggregateType,
      correlationId: correlationId ?? this.correlationId,
      causationId: causationId ?? this.causationId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EventRecord &&
        other.id == id &&
        other.eventType == eventType &&
        other.occurredAt == occurredAt;
  }

  @override
  int get hashCode => Object.hash(id, eventType, occurredAt);

  @override
  String toString() {
    return 'EventRecord(id: $id, eventType: $eventType, occurredAt: $occurredAt, aggregateId: $aggregateId)';
  }
}

/// Event statistics for monitoring
@JsonSerializable()
class EventStatistics {
  /// Total events published
  final int totalEvents;

  /// Events by type
  final Map<String, int> eventsByType;

  /// Events by aggregate type
  final Map<String, int> eventsByAggregate;

  /// Events in last hour
  final int eventsLastHour;

  /// Events in last day
  final int eventsLastDay;

  /// Most recent event timestamp
  final DateTime? lastEventAt;

  const EventStatistics({
    required this.totalEvents,
    required this.eventsByType,
    required this.eventsByAggregate,
    required this.eventsLastHour,
    required this.eventsLastDay,
    this.lastEventAt,
  });

  factory EventStatistics.fromJson(Map<String, dynamic> json) =>
      _$EventStatisticsFromJson(json);

  Map<String, dynamic> toJson() => _$EventStatisticsToJson(this);
}
