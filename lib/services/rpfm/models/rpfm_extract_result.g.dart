// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rpfm_extract_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RpfmExtractResult _$RpfmExtractResultFromJson(Map<String, dynamic> json) =>
    RpfmExtractResult(
      packFilePath: json['packFilePath'] as String,
      outputDirectory: json['outputDirectory'] as String,
      extractedFiles: (json['extractedFiles'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      localizationFileCount: (json['localizationFileCount'] as num).toInt(),
      totalSizeBytes: (json['totalSizeBytes'] as num).toInt(),
      durationMs: (json['durationMs'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      warnings: (json['warnings'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$RpfmExtractResultToJson(RpfmExtractResult instance) =>
    <String, dynamic>{
      'packFilePath': instance.packFilePath,
      'outputDirectory': instance.outputDirectory,
      'extractedFiles': instance.extractedFiles,
      'localizationFileCount': instance.localizationFileCount,
      'totalSizeBytes': instance.totalSizeBytes,
      'durationMs': instance.durationMs,
      'timestamp': instance.timestamp.toIso8601String(),
      'warnings': instance.warnings,
    };
