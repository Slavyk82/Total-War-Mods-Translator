import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/activity/models/activity_event.dart';

void main() {
  group('ActivityEventType', () {
    test('serialises every type to/from name stably', () {
      for (final type in ActivityEventType.values) {
        expect(ActivityEventType.fromName(type.name), type);
      }
    });

    test('fromName returns null for unknown value', () {
      expect(ActivityEventType.fromName('nope'), isNull);
    });
  });

  group('ActivityEvent', () {
    test('round-trips through toMap/fromMap', () {
      final original = ActivityEvent(
        id: 42,
        type: ActivityEventType.packCompiled,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1800000000000),
        projectId: 'abc-123',
        gameCode: 'warhammer_3',
        payload: {'projectName': 'X', 'packFileName': 'x.pack'},
      );
      final restored = ActivityEvent.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.timestamp, original.timestamp);
      expect(restored.projectId, original.projectId);
      expect(restored.gameCode, original.gameCode);
      expect(restored.payload, original.payload);
    });

    test('nullable projectId and gameCode are preserved', () {
      final event = ActivityEvent(
        id: 1,
        type: ActivityEventType.modUpdatesDetected,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1800000000000),
        projectId: null,
        gameCode: null,
        payload: {'count': 5},
      );
      final map = event.toMap();
      expect(map['project_id'], isNull);
      expect(map['game_code'], isNull);
      final restored = ActivityEvent.fromMap(map);
      expect(restored.projectId, isNull);
      expect(restored.gameCode, isNull);
    });
  });
}
