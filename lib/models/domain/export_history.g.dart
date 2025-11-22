// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExportHistory _$ExportHistoryFromJson(Map<String, dynamic> json) =>
    ExportHistory(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      languages: json['languages'] as String,
      format: $enumDecode(_$ExportFormatEnumMap, json['format']),
      validatedOnly: json['validated_only'] as bool,
      outputPath: json['output_path'] as String,
      fileSize: (json['file_size'] as num?)?.toInt(),
      entryCount: (json['entry_count'] as num).toInt(),
      exportedAt: (json['exported_at'] as num).toInt(),
    );

Map<String, dynamic> _$ExportHistoryToJson(ExportHistory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'project_id': instance.projectId,
      'languages': instance.languages,
      'format': _$ExportFormatEnumMap[instance.format]!,
      'validated_only': instance.validatedOnly,
      'output_path': instance.outputPath,
      'file_size': instance.fileSize,
      'entry_count': instance.entryCount,
      'exported_at': instance.exportedAt,
    };

const _$ExportFormatEnumMap = {
  ExportFormat.pack: 'pack',
  ExportFormat.csv: 'csv',
  ExportFormat.excel: 'excel',
  ExportFormat.tmx: 'tmx',
};
