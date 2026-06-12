import 'dart:convert';

/// Kinds of persistent activity events surfaced on the Home dashboard.
enum ActivityEventType {
  translationBatchCompleted,
  packCompiled,
  projectPublished,
  modUpdatesDetected,
  glossaryEnriched;

  static ActivityEventType? fromName(String name) {
    for (final v in ActivityEventType.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Immutable record of a user-visible activity.
class ActivityEvent {
  final int id;
  final ActivityEventType type;
  final DateTime timestamp;
  final String? projectId;
  final String? gameCode;
  final Map<String, dynamic> payload;

  const ActivityEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.projectId,
    required this.gameCode,
    required this.payload,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'project_id': projectId,
        'game_code': gameCode,
        'payload': jsonEncode(payload),
      };

  factory ActivityEvent.fromMap(Map<String, Object?> row) {
    final typeName = row['type'] as String;
    final type = ActivityEventType.fromName(typeName);
    if (type == null) {
      throw FormatException('Unknown ActivityEventType: $typeName');
    }
    final ts = row['timestamp'] as int;
    final payloadJson = row['payload'] as String;
    return ActivityEvent(
      id: row['id'] as int,
      type: type,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      projectId: row['project_id'] as String?,
      gameCode: row['game_code'] as String?,
      payload: (jsonDecode(payloadJson) as Map).cast<String, dynamic>(),
    );
  }
}
