// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'background_task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TaskProgress _$TaskProgressFromJson(Map<String, dynamic> json) => TaskProgress(
  taskId: json['taskId'] as String,
  progress: (json['progress'] as num).toDouble(),
  message: json['message'] as String?,
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$TaskProgressToJson(TaskProgress instance) =>
    <String, dynamic>{
      'taskId': instance.taskId,
      'progress': instance.progress,
      'message': instance.message,
      'timestamp': instance.timestamp.toIso8601String(),
    };
