// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'localization_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalizationFile _$LocalizationFileFromJson(Map<String, dynamic> json) =>
    LocalizationFile(
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      languageCode: json['languageCode'] as String,
      encoding: json['encoding'] as String? ?? 'utf-8',
      entries: (json['entries'] as List<dynamic>)
          .map((e) => LocalizationEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      comments:
          (json['comments'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      metadata: json['metadata'] == null
          ? null
          : LocalizationFileMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$LocalizationFileToJson(LocalizationFile instance) =>
    <String, dynamic>{
      'fileName': instance.fileName,
      'filePath': instance.filePath,
      'languageCode': instance.languageCode,
      'encoding': instance.encoding,
      'entries': instance.entries,
      'comments': instance.comments,
      'metadata': instance.metadata,
    };

LocalizationFileMetadata _$LocalizationFileMetadataFromJson(
  Map<String, dynamic> json,
) => LocalizationFileMetadata(
  createdAt: DateTime.parse(json['createdAt'] as String),
  modifiedAt: DateTime.parse(json['modifiedAt'] as String),
  sizeBytes: (json['sizeBytes'] as num).toInt(),
  totalLines: (json['totalLines'] as num).toInt(),
  commentLines: (json['commentLines'] as num?)?.toInt() ?? 0,
  emptyLines: (json['emptyLines'] as num?)?.toInt() ?? 0,
  fileHash: json['fileHash'] as String?,
);

Map<String, dynamic> _$LocalizationFileMetadataToJson(
  LocalizationFileMetadata instance,
) => <String, dynamic>{
  'createdAt': instance.createdAt.toIso8601String(),
  'modifiedAt': instance.modifiedAt.toIso8601String(),
  'sizeBytes': instance.sizeBytes,
  'totalLines': instance.totalLines,
  'commentLines': instance.commentLines,
  'emptyLines': instance.emptyLines,
  'fileHash': instance.fileHash,
};
