// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'process_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProcessResult _$ProcessResultFromJson(Map<String, dynamic> json) =>
    ProcessResult(
      exitCode: (json['exitCode'] as num).toInt(),
      stdout: json['stdout'] as String,
      stderr: json['stderr'] as String,
      executionTimeMs: (json['executionTimeMs'] as num).toInt(),
    );

Map<String, dynamic> _$ProcessResultToJson(ProcessResult instance) =>
    <String, dynamic>{
      'exitCode': instance.exitCode,
      'stdout': instance.stdout,
      'stderr': instance.stderr,
      'executionTimeMs': instance.executionTimeMs,
    };

ProcessProgress _$ProcessProgressFromJson(Map<String, dynamic> json) =>
    ProcessProgress(
      pid: (json['pid'] as num).toInt(),
      currentLine: json['currentLine'] as String?,
      isError: json['isError'] as bool,
      totalLines: (json['totalLines'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$ProcessProgressToJson(ProcessProgress instance) =>
    <String, dynamic>{
      'pid': instance.pid,
      'currentLine': instance.currentLine,
      'isError': instance.isError,
      'totalLines': instance.totalLines,
      'timestamp': instance.timestamp.toIso8601String(),
    };
