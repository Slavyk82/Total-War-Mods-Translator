// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExportResult _$ExportResultFromJson(Map<String, dynamic> json) => ExportResult(
  filePath: json['file_path'] as String,
  rowCount: (json['row_count'] as num).toInt(),
  fileSize: (json['file_size'] as num).toInt(),
  durationMs: (json['duration_ms'] as num).toInt(),
  isSuccess: json['is_success'] as bool? ?? true,
  errorMessage: json['error_message'] as String?,
);

Map<String, dynamic> _$ExportResultToJson(ExportResult instance) =>
    <String, dynamic>{
      'file_path': instance.filePath,
      'row_count': instance.rowCount,
      'file_size': instance.fileSize,
      'duration_ms': instance.durationMs,
      'is_success': instance.isSuccess,
      'error_message': instance.errorMessage,
    };

ExportPreview _$ExportPreviewFromJson(Map<String, dynamic> json) =>
    ExportPreview(
      previewRows: (json['preview_rows'] as List<dynamic>)
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
      totalRows: (json['total_rows'] as num).toInt(),
      estimatedSize: (json['estimated_size'] as num).toInt(),
      headers: (json['headers'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$ExportPreviewToJson(ExportPreview instance) =>
    <String, dynamic>{
      'preview_rows': instance.previewRows,
      'total_rows': instance.totalRows,
      'estimated_size': instance.estimatedSize,
      'headers': instance.headers,
    };
