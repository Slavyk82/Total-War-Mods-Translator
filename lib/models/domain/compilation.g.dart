// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compilation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Compilation _$CompilationFromJson(Map<String, dynamic> json) => Compilation(
  id: json['id'] as String,
  name: json['name'] as String,
  prefix: json['prefix'] as String,
  packName: json['pack_name'] as String,
  gameInstallationId: json['game_installation_id'] as String,
  languageId: json['language_id'] as String?,
  lastOutputPath: json['last_output_path'] as String?,
  lastGeneratedAt: (json['last_generated_at'] as num?)?.toInt(),
  createdAt: (json['created_at'] as num).toInt(),
  updatedAt: (json['updated_at'] as num).toInt(),
);

Map<String, dynamic> _$CompilationToJson(Compilation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'prefix': instance.prefix,
      'pack_name': instance.packName,
      'game_installation_id': instance.gameInstallationId,
      'language_id': instance.languageId,
      'last_output_path': instance.lastOutputPath,
      'last_generated_at': instance.lastGeneratedAt,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

CompilationProject _$CompilationProjectFromJson(Map<String, dynamic> json) =>
    CompilationProject(
      id: json['id'] as String,
      compilationId: json['compilation_id'] as String,
      projectId: json['project_id'] as String,
      sortOrder: (json['sort_order'] as num).toInt(),
      addedAt: (json['added_at'] as num).toInt(),
    );

Map<String, dynamic> _$CompilationProjectToJson(CompilationProject instance) =>
    <String, dynamic>{
      'id': instance.id,
      'compilation_id': instance.compilationId,
      'project_id': instance.projectId,
      'sort_order': instance.sortOrder,
      'added_at': instance.addedAt,
    };
