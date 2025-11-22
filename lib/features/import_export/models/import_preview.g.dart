// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportPreview _$ImportPreviewFromJson(Map<String, dynamic> json) =>
    ImportPreview(
      filePath: json['file_path'] as String,
      headers: (json['headers'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      previewRows: (json['preview_rows'] as List<dynamic>)
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
      totalRows: (json['total_rows'] as num).toInt(),
      fileSize: (json['file_size'] as num).toInt(),
      encoding: json['encoding'] as String,
      suggestedMapping:
          (json['suggested_mapping'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
    );

Map<String, dynamic> _$ImportPreviewToJson(ImportPreview instance) =>
    <String, dynamic>{
      'file_path': instance.filePath,
      'headers': instance.headers,
      'preview_rows': instance.previewRows,
      'total_rows': instance.totalRows,
      'file_size': instance.fileSize,
      'encoding': instance.encoding,
      'suggested_mapping': instance.suggestedMapping,
    };
