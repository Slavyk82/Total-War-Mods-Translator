// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rpfm_pack_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RpfmPackInfo _$RpfmPackInfoFromJson(Map<String, dynamic> json) => RpfmPackInfo(
  packFilePath: json['packFilePath'] as String,
  fileName: json['fileName'] as String,
  sizeBytes: (json['sizeBytes'] as num).toInt(),
  fileCount: (json['fileCount'] as num).toInt(),
  localizationFileCount: (json['localizationFileCount'] as num).toInt(),
  formatVersion: (json['formatVersion'] as num?)?.toInt(),
  lastModified: DateTime.parse(json['lastModified'] as String),
  checksum: json['checksum'] as String?,
);

Map<String, dynamic> _$RpfmPackInfoToJson(RpfmPackInfo instance) =>
    <String, dynamic>{
      'packFilePath': instance.packFilePath,
      'fileName': instance.fileName,
      'sizeBytes': instance.sizeBytes,
      'fileCount': instance.fileCount,
      'localizationFileCount': instance.localizationFileCount,
      'formatVersion': instance.formatVersion,
      'lastModified': instance.lastModified.toIso8601String(),
      'checksum': instance.checksum,
    };
