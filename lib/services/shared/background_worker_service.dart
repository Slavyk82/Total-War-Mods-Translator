import 'dart:async';
import 'dart:collection';
import 'package:uuid/uuid.dart';

import 'models/background_task.dart';

/// Typedef for task executor function
typedef TaskExecutor<T> = Future<T> Function(
  Map<String, dynamic> data,
  void Function(double progress, String? message) onProgress,
);

/// Background worker service for async task processing
///
/// Features:
/// - Task queue with priority ordering
/// - Concurrent task execution (configurable)
/// - Progress reporting
/// - Automatic retry on failure
/// - Task cancellation
/// - Task lifecycle management
///
/// Note: This is a simplified implementation using Futures.
/// For true background processing, you would use Isolates.
///
/// Example:
/// ```dart
/// final worker = BackgroundWorkerService.instance;
///
/// // Register task executor
/// worker.registerExecutor<String>('fetch_data', (data, onProgress) async {
///   onProgress(0.5, 'Fetching...');
///   final result = await fetchData(data['url']);
///   onProgress(1.0, 'Done');
///   return result;
/// });
///
/// // Enqueue task
/// final taskId = worker.enqueue(
///   taskType: 'fetch_data',
///   data: {'url': 'https://api.example.com/data'},
/// );
///
/// // Listen to progress
/// worker.taskProgress.listen((progress) {
///   print('${progress.taskId}: ${progress.progress * 100}%');
/// });
/// ```
class BackgroundWorkerService {
  BackgroundWorkerService._();

  static final BackgroundWorkerService _instance = BackgroundWorkerService._();
  static BackgroundWorkerService get instance => _instance;

  final Uuid _uuid = const Uuid();

  /// Task executors by task type
  final Map<String, TaskExecutor<dynamic>> _executors = {};

  /// Task queue (priority-ordered)
  final Queue<BackgroundTask<dynamic>> _queue = Queue();

  /// Active tasks
  final Map<String, BackgroundTask<dynamic>> _activeTasks = {};

  /// Completed tasks (last 100)
  final Queue<BackgroundTask<dynamic>> _completedTasks = Queue();

  /// Maximum concurrent tasks
  int maxConcurrentTasks = 4;

  /// Maximum completed tasks to keep in memory
  static const int maxCompletedTasksInMemory = 100;

  /// Stream controller for task updates
  final StreamController<BackgroundTask<dynamic>> _taskController =
      StreamController<BackgroundTask<dynamic>>.broadcast();

  /// Stream controller for progress updates
  final StreamController<TaskProgress> _progressController =
      StreamController<TaskProgress>.broadcast();

  /// Stream of task updates
  Stream<BackgroundTask<dynamic>> get taskUpdates => _taskController.stream;

  /// Stream of progress updates
  Stream<TaskProgress> get taskProgress => _progressController.stream;

  /// Register a task executor
  ///
  /// Parameters:
  /// - [taskType]: Unique task type identifier
  /// - [executor]: Function that executes the task
  ///
  /// Example:
  /// ```dart
  /// worker.registerExecutor<UserData>('fetch_user', (data, onProgress) async {
  ///   final userId = data['userId'] as String;
  ///   onProgress(0.5, 'Fetching user $userId...');
  ///   final user = await api.fetchUser(userId);
  ///   onProgress(1.0, 'Done');
  ///   return user;
  /// });
  /// ```
  void registerExecutor<T>(String taskType, TaskExecutor<T> executor) {
    _executors[taskType] = executor;
  }

  /// Enqueue a background task
  ///
  /// Parameters:
  /// - [taskType]: Task type (must be registered)
  /// - [data]: Task input data
  /// - [priority]: Task priority (higher = more important)
  /// - [maxRetries]: Maximum retry attempts on failure
  ///
  /// Returns task ID
  String enqueue({
    required String taskType,
    required Map<String, dynamic> data,
    int priority = 0,
    int maxRetries = 0,
  }) {
    if (!_executors.containsKey(taskType)) {
      throw ArgumentError('No executor registered for task type: $taskType');
    }

    final task = BackgroundTask<dynamic>(
      id: _uuid.v4(),
      taskType: taskType,
      data: data,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      priority: priority,
      maxRetries: maxRetries,
    );

    _queue.add(task);
    _taskController.add(task);

    // Sort queue by priority (higher priority first)
    final sortedQueue = _queue.toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    _queue.clear();
    _queue.addAll(sortedQueue);

    // Start processing
    _processQueue();

    return task.id;
  }

  /// Cancel a task
  ///
  /// Only pending tasks can be cancelled.
  /// Running tasks cannot be cancelled in this simplified implementation.
  ///
  /// Returns true if task was cancelled
  bool cancel(String taskId) {
    // Check queue
    final task = _queue.firstWhere(
      (t) => t.id == taskId,
      orElse: () => BackgroundTask<dynamic>(
        id: '',
        taskType: '',
        data: {},
        status: TaskStatus.pending,
        createdAt: DateTime.now(),
      ),
    );

    if (task.id.isNotEmpty) {
      _queue.remove(task);

      final cancelled = task.copyWith(
        status: TaskStatus.cancelled,
        completedAt: DateTime.now(),
      );

      _taskController.add(cancelled);
      _addToCompleted(cancelled);

      return true;
    }

    return false;
  }

  /// Get task by ID
  BackgroundTask<dynamic>? getTask(String taskId) {
    // Check active tasks
    if (_activeTasks.containsKey(taskId)) {
      return _activeTasks[taskId];
    }

    // Check queue
    try {
      return _queue.firstWhere((t) => t.id == taskId);
    } catch (_) {
      // Not found in queue
    }

    // Check completed
    try {
      return _completedTasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  /// Get all active tasks
  List<BackgroundTask<dynamic>> get activeTasks => _activeTasks.values.toList();

  /// Get queued tasks
  List<BackgroundTask<dynamic>> get queuedTasks => _queue.toList();

  /// Get completed tasks (last 100)
  List<BackgroundTask<dynamic>> get completedTasks => _completedTasks.toList();

  /// Get task statistics
  Map<String, int> get statistics => {
        'queued': _queue.length,
        'active': _activeTasks.length,
        'completed': _completedTasks.length,
      };

  // Private methods

  Future<void> _processQueue() async {
    // Don't start more tasks if at max concurrency
    if (_activeTasks.length >= maxConcurrentTasks) {
      return;
    }

    // Get next task
    if (_queue.isEmpty) {
      return;
    }

    final task = _queue.removeFirst();

    // Start task
    await _executeTask(task);

    // Process next task
    if (_queue.isNotEmpty) {
      _processQueue();
    }
  }

  Future<void> _executeTask(BackgroundTask<dynamic> task) async {
    final executor = _executors[task.taskType];
    if (executor == null) {
      final failed = task.copyWith(
        status: TaskStatus.failed,
        error: 'No executor found for task type: ${task.taskType}',
        completedAt: DateTime.now(),
      );
      _taskController.add(failed);
      _addToCompleted(failed);
      return;
    }

    // Mark as running
    final running = task.copyWith(
      status: TaskStatus.running,
      startedAt: DateTime.now(),
    );
    _activeTasks[task.id] = running;
    _taskController.add(running);

    try {
      // Execute task with progress callback
      void onProgress(double progress, String? message) {
        final updated = running.copyWith(
          progress: progress.clamp(0.0, 1.0),
          progressMessage: message,
        );
        _activeTasks[task.id] = updated;

        _progressController.add(TaskProgress(
          taskId: task.id,
          progress: progress,
          message: message,
          timestamp: DateTime.now(),
        ));
      }

      final result = await executor(task.data, onProgress);

      // Mark as completed
      final completed = running.copyWith(
        status: TaskStatus.completed,
        result: result,
        completedAt: DateTime.now(),
        progress: 1.0,
      );

      _activeTasks.remove(task.id);
      _taskController.add(completed);
      _addToCompleted(completed);
    } catch (e, stackTrace) {
      // Check if should retry
      if (task.retryCount < task.maxRetries) {
        final retry = task.copyWith(
          status: TaskStatus.pending,
          retryCount: task.retryCount + 1,
        );
        _queue.addFirst(retry); // Add to front for immediate retry
        _activeTasks.remove(task.id);
        _taskController.add(retry);
        _processQueue();
        return;
      }

      // Mark as failed
      final failed = running.copyWith(
        status: TaskStatus.failed,
        error: e.toString(),
        stackTrace: stackTrace.toString(),
        completedAt: DateTime.now(),
      );

      _activeTasks.remove(task.id);
      _taskController.add(failed);
      _addToCompleted(failed);
    }

    // Continue processing queue
    _processQueue();
  }

  void _addToCompleted(BackgroundTask<dynamic> task) {
    _completedTasks.add(task);

    // Keep only last 100
    while (_completedTasks.length > maxCompletedTasksInMemory) {
      _completedTasks.removeFirst();
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _taskController.close();
    await _progressController.close();

    _queue.clear();
    _activeTasks.clear();
    _completedTasks.clear();
    _executors.clear();
  }
}
