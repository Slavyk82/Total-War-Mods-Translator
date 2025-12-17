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
  lastUpdateCheck: (json['last_update_check'] as num?)?.toInt(),
  sourceModUpdated: (json['source_mod_updated'] as num?)?.toInt(),
  batchSize: (json['batch_size'] as num?)?.toInt() ?? 25,
  parallelBatches: (json['parallel_batches'] as num?)?.toInt() ?? 3,
  customPrompt: json['custom_prompt'] as String?,
  createdAt: (json['created_at'] as num).toInt(),
  updatedAt: (json['updated_at'] as num).toInt(),
  completedAt: (json['completed_at'] as num?)?.toInt(),
  metadata: json['metadata'] as String?,
  hasModUpdateImpact: json['has_mod_update_impact'] == null
      ? false
      : _boolFromInt(json['has_mod_update_impact']),
  projectType: json['project_type'] as String? ?? 'mod',
  sourceLanguageCode: json['source_language_code'] as String?,
);

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'mod_steam_id': instance.modSteamId,
  'mod_version': instance.modVersion,
  'game_installation_id': instance.gameInstallationId,
  'source_file_path': instance.sourceFilePath,
  'output_file_path': instance.outputFilePath,
  'last_update_check': instance.lastUpdateCheck,
  'source_mod_updated': instance.sourceModUpdated,
  'batch_size': instance.batchSize,
  'parallel_batches': instance.parallelBatches,
  'custom_prompt': instance.customPrompt,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'completed_at': instance.completedAt,
  'metadata': instance.metadata,
  'has_mod_update_impact': _boolToInt(instance.hasModUpdateImpact),
  'project_type': instance.projectType,
  'source_language_code': instance.sourceLanguageCode,
};
