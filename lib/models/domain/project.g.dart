// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
  id: json['id'] as String,
  name: json['name'] as String,
  modSteamId: json['mod_steam_id'] as String?,
  modVersion: json['mod_version'] as String?,
  gameInstallationId: json['game_installation_id'] as String,
  sourceFilePath: json['source_file_path'] as String?,
  outputFilePath: json['output_file_path'] as String?,
  status:
      $enumDecodeNullable(_$ProjectStatusEnumMap, json['status']) ??
      ProjectStatus.draft,
  lastUpdateCheck: (json['last_update_check'] as num?)?.toInt(),
  sourceModUpdated: (json['source_mod_updated'] as num?)?.toInt(),
  batchSize: (json['batch_size'] as num?)?.toInt() ?? 25,
  parallelBatches: (json['parallel_batches'] as num?)?.toInt() ?? 1,
  customPrompt: json['custom_prompt'] as String?,
  createdAt: (json['created_at'] as num).toInt(),
  updatedAt: (json['updated_at'] as num).toInt(),
  completedAt: (json['completed_at'] as num?)?.toInt(),
  metadata: json['metadata'] as String?,
);

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'mod_steam_id': instance.modSteamId,
  'mod_version': instance.modVersion,
  'game_installation_id': instance.gameInstallationId,
  'source_file_path': instance.sourceFilePath,
  'output_file_path': instance.outputFilePath,
  'status': _$ProjectStatusEnumMap[instance.status]!,
  'last_update_check': instance.lastUpdateCheck,
  'source_mod_updated': instance.sourceModUpdated,
  'batch_size': instance.batchSize,
  'parallel_batches': instance.parallelBatches,
  'custom_prompt': instance.customPrompt,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'completed_at': instance.completedAt,
  'metadata': instance.metadata,
};

const _$ProjectStatusEnumMap = {
  ProjectStatus.draft: 'draft',
  ProjectStatus.translating: 'translating',
  ProjectStatus.reviewing: 'reviewing',
  ProjectStatus.completed: 'completed',
};
