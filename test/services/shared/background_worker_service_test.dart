import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/shared/background_worker_service.dart';
import 'package:twmt/services/shared/models/background_task.dart';

void main() {
  late BackgroundWorkerService worker;

  setUp(() {
    worker = BackgroundWorkerService.instance;
    worker.maxConcurrentTasks = 4;
  });

  /// Completes with the task once it reaches a terminal status.
  Future<BackgroundTask<dynamic>> waitForTerminal(String taskId) {
    final completer = Completer<BackgroundTask<dynamic>>();
    late StreamSubscription sub;
    sub = worker.taskUpdates.listen((task) {
      if (task.id != taskId) return;
      if (task.status == TaskStatus.completed ||
          task.status == TaskStatus.failed ||
          task.status == TaskStatus.cancelled) {
        if (!completer.isCompleted) {
          completer.complete(task);
          sub.cancel();
        }
      }
    });
    return completer.future;
  }

  group('registerExecutor + enqueue', () {
    test('runs an executor to completion and stores the result', () async {
      worker.registerExecutor<int>('sum', (data, onProgress) async {
        onProgress(0.5, 'working');
        return (data['a'] as int) + (data['b'] as int);
      });

      final id = worker.enqueue(taskType: 'sum', data: {'a': 2, 'b': 3});
      final task = await waitForTerminal(id);

      expect(task.status, TaskStatus.completed);
      expect(task.result, 5);
      expect(task.progress, 1.0);
    });

    test('emits progress updates while running', () async {
      worker.registerExecutor<String>('progressing', (data, onProgress) async {
        onProgress(0.25, 'a quarter');
        onProgress(0.75, 'three quarters');
        return 'done';
      });

      // Subscribe BEFORE enqueue: progress events are emitted synchronously
      // during enqueue(), so a late listener would miss them.
      final progresses = <TaskProgress>[];
      final sub = worker.taskProgress.listen(progresses.add);

      final id = worker.enqueue(taskType: 'progressing', data: {});
      await waitForTerminal(id);
      await sub.cancel();

      final mine = progresses.where((p) => p.taskId == id).toList();
      expect(mine, isNotEmpty);
      expect(mine.map((p) => p.message), contains('a quarter'));
    });

    test('throws when enqueueing an unregistered task type', () {
      expect(
        () => worker.enqueue(taskType: 'never_registered', data: {}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('failure handling', () {
    test('marks a task failed when the executor throws', () async {
      worker.registerExecutor<void>('boom', (data, onProgress) async {
        throw StateError('kaboom');
      });

      final id = worker.enqueue(taskType: 'boom', data: {});
      final task = await waitForTerminal(id);

      expect(task.status, TaskStatus.failed);
      expect(task.error, contains('kaboom'));
    });

    test('retries a flaky executor until it succeeds', () async {
      var attempts = 0;
      worker.registerExecutor<String>('flaky', (data, onProgress) async {
        attempts++;
        if (attempts < 2) {
          throw Exception('transient');
        }
        return 'recovered';
      });

      final id =
          worker.enqueue(taskType: 'flaky', data: {}, maxRetries: 3);
      final task = await waitForTerminal(id);

      expect(task.status, TaskStatus.completed);
      expect(task.result, 'recovered');
      expect(attempts, 2);
    });
  });

  group('cancel', () {
    test('cancels a queued task and returns true', () async {
      worker.registerExecutor<int>('idle', (data, onProgress) async => 1);
      // Block the queue so the task stays pending.
      worker.maxConcurrentTasks = 0;

      final id = worker.enqueue(taskType: 'idle', data: {});
      final cancelled = worker.cancel(id);

      expect(cancelled, isTrue);
      expect(worker.getTask(id)?.status, TaskStatus.cancelled);

      worker.maxConcurrentTasks = 4; // restore for other tests
    });

    test('returns false for an unknown task id', () {
      expect(worker.cancel('no-such-id'), isFalse);
    });
  });

  group('getTask', () {
    test('finds a completed task', () async {
      worker.registerExecutor<int>('quick', (data, onProgress) async => 42);
      final id = worker.enqueue(taskType: 'quick', data: {});
      await waitForTerminal(id);

      final found = worker.getTask(id);
      expect(found, isNotNull);
      expect(found!.result, 42);
    });

    test('returns null for an unknown id', () {
      expect(worker.getTask('ghost'), isNull);
    });
  });

  group('introspection', () {
    test('statistics expose queue/active/completed counts', () {
      final stats = worker.statistics;
      expect(stats.keys, containsAll(['queued', 'active', 'completed']));
      expect(stats['queued'], isA<int>());
    });

    test('accessor lists return list views', () {
      expect(worker.activeTasks, isA<List<BackgroundTask<dynamic>>>());
      expect(worker.queuedTasks, isA<List<BackgroundTask<dynamic>>>());
      expect(worker.completedTasks, isA<List<BackgroundTask<dynamic>>>());
    });
  });
}
