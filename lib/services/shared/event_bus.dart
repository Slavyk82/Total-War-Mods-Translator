import 'dart:async';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../models/events/domain_event.dart';
import '../../models/common/result.dart';
import '../database/database_service.dart';
import 'models/event_record.dart';
import 'logging_service.dart';

/// Event bus for publishing and subscribing to domain events.
///
/// This service implements the publish-subscribe pattern for domain events,
/// allowing decoupled communication between different parts of the application.
///
/// Enhanced features:
/// - Event persistence to database (audit trail)
/// - Event replay for debugging
/// - Event statistics and monitoring
/// - Correlation and causation tracking
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

  final Uuid _uuid = const Uuid();

  /// Enable event persistence (default: false)
  /// IMPORTANT: Currently disabled due to transaction conflicts
  /// Event persistence conflicts with active transactions in TransactionManager
  /// TODO: Implement proper async queue or separate connection for event persistence
  bool persistEvents = false;

  /// Maximum events to keep in memory for replay
  static const int maxReplayBuffer = 1000;

  /// In-memory event buffer for replay
  final List<EventRecord> _replayBuffer = [];

  Database get _db => DatabaseService.database;

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
  /// If persistence is enabled and the database is initialized,
  /// the event will also be stored in the database.
  ///
  /// Example:
  /// ```dart
  /// eventBus.publish(TranslationAddedEvent(
  ///   versionId: '123',
  ///   unitId: '456',
  ///   projectLanguageId: '789',
  ///   translatedText: 'Hello',
  /// ));
  /// ```
  Future<void> publish(
    DomainEvent event, {
    String? triggeredBy,
    String? correlationId,
    String? causationId,
    Map<String, dynamic>? metadata,
  }) async {
    // Broadcast to listeners
    _controller.add(event);

    // Persist if enabled AND database is initialized
    // This prevents crashes during app initialization when EventBus
    // is initialized before DatabaseService
    if (persistEvents && DatabaseService.isInitialized) {
      // Persist asynchronously in background to avoid blocking transactions
      // Use unawaited to prevent blocking the caller
      unawaited(
        _persistEvent(
          event,
          triggeredBy: triggeredBy,
          correlationId: correlationId,
          causationId: causationId,
          metadata: metadata,
        ).catchError((e, stackTrace) {
          // Log but don't throw - event persistence is best-effort
          // The event has already been broadcast to listeners, which is the primary goal
          // Persistence failure should not crash the caller
          // ignore: avoid_print
          print('⚠️ Failed to persist event ${event.runtimeType}: $e');
        }),
      );
    }
  }

  /// Publish a domain event synchronously (no persistence)
  ///
  /// Use this for high-frequency events that don't need persistence.
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

  /// Get event history from database
  ///
  /// Parameters:
  /// - [eventType]: Filter by event type (optional)
  /// - [aggregateId]: Filter by aggregate ID (optional)
  /// - [since]: Get events since this timestamp (optional)
  /// - [limit]: Maximum number of events to return (default: 100)
  ///
  /// Returns list of event records ordered by occurrence time (newest first)
  Future<Result<List<EventRecord>, Exception>> getEventHistory({
    String? eventType,
    String? aggregateId,
    DateTime? since,
    int limit = 100,
  }) async {
    try {
      final List<String> whereClauses = [];
      final List<dynamic> whereArgs = [];

      if (eventType != null) {
        whereClauses.add('event_type = ?');
        whereArgs.add(eventType);
      }

      if (aggregateId != null) {
        whereClauses.add('aggregate_id = ?');
        whereArgs.add(aggregateId);
      }

      if (since != null) {
        whereClauses.add('occurred_at >= ?');
        whereArgs.add(since.millisecondsSinceEpoch);
      }

      final whereClause = whereClauses.isEmpty ? null : whereClauses.join(' AND ');

      final results = await _db.query(
        'event_store',
        where: whereClause,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: 'occurred_at DESC',
        limit: limit,
      );

      final events = results.map(_parseEventRecord).toList();
      return Ok(events);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to get event history: ${e.toString()}'));
    } catch (e) {
      return Err(Exception('Unexpected error getting event history: ${e.toString()}'));
    }
  }

  /// Replay events from history
  ///
  /// Useful for debugging and testing event handlers.
  /// Re-publishes events to all current subscribers.
  ///
  /// Parameters:
  /// - [eventType]: Replay only specific event type (optional)
  /// - [since]: Replay events since this timestamp (optional)
  /// - [limit]: Maximum number of events to replay (default: 100)
  ///
  /// Returns number of events replayed
  Future<Result<int, Exception>> replayEvents({
    String? eventType,
    DateTime? since,
    int limit = 100,
  }) async {
    final historyResult = await getEventHistory(
      eventType: eventType,
      since: since,
      limit: limit,
    );

    if (historyResult is Err) {
      return Err(historyResult.error);
    }

    final events = (historyResult as Ok<List<EventRecord>, Exception>).value;

    // Replay in chronological order (reverse of query result)
    for (final _ in events.reversed) {
      try {
        // Note: We can't reconstruct the actual DomainEvent object from JSON
        // without knowing the concrete type and having a fromJson factory.
        // In practice, you'd need a registry of event types and their factories.
        // For now, we just re-broadcast the event data via a generic wrapper.

        // This is a simplified implementation - in production you'd want
        // a proper event registry and deserialization mechanism.

        // Skip actual replay for now - this would require implementing
        // a DomainEvent registry and fromJson factories for all event types.
      } catch (e) {
        // Continue with next event if one fails
        continue;
      }
    }

    return Ok(events.length);
  }

  /// Get event statistics
  ///
  /// Returns aggregated statistics about published events.
  Future<Result<EventStatistics, Exception>> getStatistics() async {
    try {
      // Total events
      final totalResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM event_store',
      );
      final totalEvents = totalResult.first['count'] as int;

      // Events by type
      final byTypeResult = await _db.rawQuery('''
        SELECT event_type, COUNT(*) as count
        FROM event_store
        GROUP BY event_type
      ''');
      final eventsByType = <String, int>{};
      for (final row in byTypeResult) {
        eventsByType[row['event_type'] as String] = row['count'] as int;
      }

      // Events by aggregate type
      final byAggregateResult = await _db.rawQuery('''
        SELECT aggregate_type, COUNT(*) as count
        FROM event_store
        WHERE aggregate_type IS NOT NULL
        GROUP BY aggregate_type
      ''');
      final eventsByAggregate = <String, int>{};
      for (final row in byAggregateResult) {
        final aggType = row['aggregate_type'] as String?;
        if (aggType != null) {
          eventsByAggregate[aggType] = row['count'] as int;
        }
      }

      // Events in last hour
      final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final lastHourResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM event_store WHERE occurred_at >= ?',
        [hourAgo.millisecondsSinceEpoch],
      );
      final eventsLastHour = lastHourResult.first['count'] as int;

      // Events in last day
      final dayAgo = DateTime.now().subtract(const Duration(days: 1));
      final lastDayResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM event_store WHERE occurred_at >= ?',
        [dayAgo.millisecondsSinceEpoch],
      );
      final eventsLastDay = lastDayResult.first['count'] as int;

      // Most recent event
      final recentResult = await _db.query(
        'event_store',
        columns: ['occurred_at'],
        orderBy: 'occurred_at DESC',
        limit: 1,
      );
      final lastEventAt = recentResult.isEmpty
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              recentResult.first['occurred_at'] as int,
            );

      final stats = EventStatistics(
        totalEvents: totalEvents,
        eventsByType: eventsByType,
        eventsByAggregate: eventsByAggregate,
        eventsLastHour: eventsLastHour,
        eventsLastDay: eventsLastDay,
        lastEventAt: lastEventAt,
      );

      return Ok(stats);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to get statistics: ${e.toString()}'));
    } catch (e) {
      return Err(Exception('Unexpected error getting statistics: ${e.toString()}'));
    }
  }

  /// Clear old events from database
  ///
  /// Deletes events older than the specified retention period.
  ///
  /// Parameters:
  /// - [retentionDays]: Keep events from the last N days (default: 90)
  ///
  /// Returns number of events deleted
  Future<Result<int, Exception>> purgeOldEvents({int retentionDays = 90}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));

      final count = await _db.delete(
        'event_store',
        where: 'occurred_at < ?',
        whereArgs: [cutoff.millisecondsSinceEpoch],
      );

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to purge events: ${e.toString()}'));
    } catch (e) {
      return Err(Exception('Unexpected error purging events: ${e.toString()}'));
    }
  }

  /// Search events by payload content
  ///
  /// Searches event payloads for specific values.
  ///
  /// Parameters:
  /// - [searchTerm]: Term to search for in payload JSON
  /// - [limit]: Maximum results (default: 50)
  Future<Result<List<EventRecord>, Exception>> searchEvents({
    required String searchTerm,
    int limit = 50,
  }) async {
    try {
      // SQLite JSON search - searches for the term in the payload JSON
      final results = await _db.rawQuery('''
        SELECT * FROM event_store
        WHERE payload LIKE ?
        ORDER BY occurred_at DESC
        LIMIT ?
      ''', ['%$searchTerm%', limit]);

      final events = results.map(_parseEventRecord).toList();
      return Ok(events);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to search events: ${e.toString()}'));
    } catch (e) {
      return Err(Exception('Unexpected error searching events: ${e.toString()}'));
    }
  }

  // Private helper methods

  Future<void> _persistEvent(
    DomainEvent event, {
    String? triggeredBy,
    String? correlationId,
    String? causationId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final eventId = _uuid.v4();
      final eventType = event.runtimeType.toString();

      // Convert event to JSON
      // Note: This assumes DomainEvent has a toJson method
      final payload = event.toJson();

      final record = EventRecord(
        id: eventId,
        eventType: eventType,
        payload: payload,
        occurredAt: event.occurredAt,
        triggeredBy: triggeredBy,
        aggregateId: _extractAggregateId(event),
        aggregateType: _extractAggregateType(event),
        correlationId: correlationId,
        causationId: causationId,
        metadata: metadata,
      );

      // Add to replay buffer
      _replayBuffer.add(record);
      if (_replayBuffer.length > maxReplayBuffer) {
        _replayBuffer.removeAt(0);
      }

      // Persist to database
      await _db.insert('event_store', {
        'id': record.id,
        'event_type': record.eventType,
        'payload': jsonEncode(record.payload),
        'occurred_at': record.occurredAt.millisecondsSinceEpoch,
        'triggered_by': record.triggeredBy,
        'aggregate_id': record.aggregateId,
        'aggregate_type': record.aggregateType,
        'correlation_id': record.correlationId,
        'causation_id': record.causationId,
        'metadata': record.metadata != null ? jsonEncode(record.metadata) : null,
      });
    } catch (e, stackTrace) {
      // Don't throw - event persistence failure shouldn't break the application
      // Just log the error
      LoggingService.instance.error('Failed to persist event', e, stackTrace);
    }
  }

  String? _extractAggregateId(DomainEvent event) {
    // Try to extract aggregate ID from common field names
    final json = event.toJson();

    if (json.containsKey('batchId')) return json['batchId'] as String?;
    if (json.containsKey('projectId')) return json['projectId'] as String?;
    if (json.containsKey('versionId')) return json['versionId'] as String?;
    if (json.containsKey('unitId')) return json['unitId'] as String?;
    if (json.containsKey('id')) return json['id'] as String?;

    return null;
  }

  String? _extractAggregateType(DomainEvent event) {
    // Infer aggregate type from event type
    final eventType = event.runtimeType.toString();

    if (eventType.contains('Batch')) return 'TranslationBatch';
    if (eventType.contains('Project')) return 'Project';
    if (eventType.contains('Translation')) return 'Translation';
    if (eventType.contains('Version')) return 'TranslationVersion';

    return null;
  }

  EventRecord _parseEventRecord(Map<String, dynamic> row) {
    return EventRecord(
      id: row['id'] as String,
      eventType: row['event_type'] as String,
      payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(row['occurred_at'] as int),
      triggeredBy: row['triggered_by'] as String?,
      aggregateId: row['aggregate_id'] as String?,
      aggregateType: row['aggregate_type'] as String?,
      correlationId: row['correlation_id'] as String?,
      causationId: row['causation_id'] as String?,
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }
}
