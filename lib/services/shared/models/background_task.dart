import 'package:json_annotation/json_annotation.dart';

part 'background_task.g.dart';

/// Task status
enum TaskStatus {
  /// Task is queued and waiting
  pending,

  /// Task is currently running
  running,

  /// Task completed successfully
  completed,

  /// Task failed with error
  failed,

  /// Task was cancelled
  cancelled,
}

/// Background task definition
/// Note: Not JSON serializable due to generic type parameter
class BackgroundTask<T> {
  /// Unique task ID
  final String id;

  /// Task type identifier (for task registry)
  final String taskType;

  /// Task input data
  final Map<String, dynamic> data;

  /// Task status
  final TaskStatus status;

  /// When the task was created
  final DateTime createdAt;

  /// When the task started running
  final DateTime? startedAt;

  /// When the task completed
  final DateTime? completedAt;

  /// Task result (if completed)
  final T? result;

  /// Error message (if failed)
  final String? error;

  /// Stack trace (if failed)
  final String? stackTrace;

  /// Task progress (0.0 - 1.0)
  final double progress;

  /// Current progress message
  final String? progressMessage;

  /// Task priority (higher = more important)
  final int priority;

  /// Number of retry attempts
  final int retryCount;

  /// Maximum retry attempts
  final int maxRetries;

  const BackgroundTask({
    required this.id,
    required this.taskType,
    required this.data,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.result,
    this.error,
    this.stackTrace,
    this.progress = 0.0,
    this.progressMessage,
    this.priority = 0,
    this.retryCount = 0,
    this.maxRetries = 0,
  });

  BackgroundTask<T> copyWith({
    String? id,
    String? taskType,
    Map<String, dynamic>? data,
    TaskStatus? status,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    T? result,
    String? error,
    String? stackTrace,
    double? progress,
    String? progressMessage,
    int? priority,
    int? retryCount,
    int? maxRetries,
  }) {
    return BackgroundTask<T>(
      id: id ?? this.id,
      taskType: taskType ?? this.taskType,
      data: data ?? this.data,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      result: result ?? this.result,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      priority: priority ?? this.priority,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BackgroundTask<T> && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'BackgroundTask(id: $id, type: $taskType, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}

/// Task progress update
@JsonSerializable()
class TaskProgress {
  /// Task ID
  final String taskId;

  /// Progress value (0.0 - 1.0)
  final double progress;

  /// Progress message
  final String? message;

  /// Timestamp
  final DateTime timestamp;

  const TaskProgress({
    required this.taskId,
    required this.progress,
    this.message,
    required this.timestamp,
  });

  factory TaskProgress.fromJson(Map<String, dynamic> json) =>
      _$TaskProgressFromJson(json);

  Map<String, dynamic> toJson() => _$TaskProgressToJson(this);

  @override
  String toString() {
    return 'TaskProgress(taskId: $taskId, progress: ${(progress * 100).toStringAsFixed(1)}%, message: $message)';
  }
}
