// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EventRecord _$EventRecordFromJson(Map<String, dynamic> json) => EventRecord(
  id: json['id'] as String,
  eventType: json['eventType'] as String,
  payload: json['payload'] as Map<String, dynamic>,
  occurredAt: DateTime.parse(json['occurredAt'] as String),
  triggeredBy: json['triggeredBy'] as String?,
  aggregateId: json['aggregateId'] as String?,
  aggregateType: json['aggregateType'] as String?,
  correlationId: json['correlationId'] as String?,
  causationId: json['causationId'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$EventRecordToJson(EventRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'eventType': instance.eventType,
      'payload': instance.payload,
      'occurredAt': instance.occurredAt.toIso8601String(),
      'triggeredBy': instance.triggeredBy,
      'aggregateId': instance.aggregateId,
      'aggregateType': instance.aggregateType,
      'correlationId': instance.correlationId,
      'causationId': instance.causationId,
      'metadata': instance.metadata,
    };

EventStatistics _$EventStatisticsFromJson(Map<String, dynamic> json) =>
    EventStatistics(
      totalEvents: (json['totalEvents'] as num).toInt(),
      eventsByType: Map<String, int>.from(json['eventsByType'] as Map),
      eventsByAggregate: Map<String, int>.from(
        json['eventsByAggregate'] as Map,
      ),
      eventsLastHour: (json['eventsLastHour'] as num).toInt(),
      eventsLastDay: (json['eventsLastDay'] as num).toInt(),
      lastEventAt: json['lastEventAt'] == null
          ? null
          : DateTime.parse(json['lastEventAt'] as String),
    );

Map<String, dynamic> _$EventStatisticsToJson(EventStatistics instance) =>
    <String, dynamic>{
      'totalEvents': instance.totalEvents,
      'eventsByType': instance.eventsByType,
      'eventsByAggregate': instance.eventsByAggregate,
      'eventsLastHour': instance.eventsLastHour,
      'eventsLastDay': instance.eventsLastDay,
      'lastEventAt': instance.lastEventAt?.toIso8601String(),
    };
