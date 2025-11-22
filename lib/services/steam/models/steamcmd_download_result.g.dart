// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'steamcmd_download_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SteamCmdDownloadResult _$SteamCmdDownloadResultFromJson(
  Map<String, dynamic> json,
) => SteamCmdDownloadResult(
  workshopId: json['workshopId'] as String,
  appId: (json['appId'] as num).toInt(),
  downloadPath: json['downloadPath'] as String,
  modTitle: json['modTitle'] as String?,
  sizeBytes: (json['sizeBytes'] as num).toInt(),
  durationMs: (json['durationMs'] as num).toInt(),
  timestamp: DateTime.parse(json['timestamp'] as String),
  wasUpdate: json['wasUpdate'] as bool? ?? false,
  previousVersionTimestamp: json['previousVersionTimestamp'] == null
      ? null
      : DateTime.parse(json['previousVersionTimestamp'] as String),
  downloadedFiles: (json['downloadedFiles'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  warnings: (json['warnings'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$SteamCmdDownloadResultToJson(
  SteamCmdDownloadResult instance,
) => <String, dynamic>{
  'workshopId': instance.workshopId,
  'appId': instance.appId,
  'downloadPath': instance.downloadPath,
  'modTitle': instance.modTitle,
  'sizeBytes': instance.sizeBytes,
  'durationMs': instance.durationMs,
  'timestamp': instance.timestamp.toIso8601String(),
  'wasUpdate': instance.wasUpdate,
  'previousVersionTimestamp': instance.previousVersionTimestamp
      ?.toIso8601String(),
  'downloadedFiles': instance.downloadedFiles,
  'warnings': instance.warnings,
};
