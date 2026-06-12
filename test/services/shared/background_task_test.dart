import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/models/background_task.dart';

void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1000);

  BackgroundTask<int> task() => BackgroundTask<int>(
        id: 't1',
        taskType: 'translate',
        data: const {'k': 'v'},
        status: TaskStatus.pending,
        createdAt: created,
      );

  group('BackgroundTask', () {
    test('applies sensible defaults', () {
      final t = task();
      expect(t.progress, 0.0);
      expect(t.priority, 0);
      expect(t.retryCount, 0);
      expect(t.maxRetries, 0);
      expect(t.startedAt, isNull);
      expect(t.result, isNull);
    });

    test('copyWith overrides only the given fields', () {
      final t = task().copyWith(
        status: TaskStatus.running,
        progress: 0.5,
        result: 7,
      );
      expect(t.status, TaskStatus.running);
      expect(t.progress, 0.5);
      expect(t.result, 7);
      // Untouched fields are preserved.
      expect(t.id, 't1');
      expect(t.taskType, 'translate');
    });

    test('equality and hashCode are based on id only', () {
      final a = task();
      final b = task().copyWith(status: TaskStatus.failed, progress: 1.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      final c = task().copyWith(id: 'other');
      expect(a, isNot(equals(c)));
    });

    test('toString includes id, type, status and progress', () {
      final s = task().copyWith(progress: 0.25).toString();
      expect(s, contains('t1'));
      expect(s, contains('translate'));
      expect(s, contains('25.0%'));
    });
  });

  group('TaskProgress', () {
    test('round-trips through JSON', () {
      final progress = TaskProgress(
        taskId: 't1',
        progress: 0.75,
        message: 'almost there',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final restored = TaskProgress.fromJson(progress.toJson());

      expect(restored.taskId, 't1');
      expect(restored.progress, 0.75);
      expect(restored.message, 'almost there');
      expect(restored.timestamp, progress.timestamp);
    });

    test('toString reports the percentage', () {
      final s = TaskProgress(
        taskId: 't1',
        progress: 0.5,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ).toString();
      expect(s, contains('50.0%'));
    });
  });
}
