// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_provider_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlmProviderModel _$LlmProviderModelFromJson(Map<String, dynamic> json) =>
    LlmProviderModel(
      id: json['id'] as String,
      providerCode: json['provider_code'] as String,
      modelId: json['model_id'] as String,
      displayName: json['display_name'] as String?,
      isEnabled: json['is_enabled'] == null
          ? false
          : const BoolIntConverter().fromJson(json['is_enabled']),
      isDefault: json['is_default'] == null
          ? false
          : const BoolIntConverter().fromJson(json['is_default']),
      isArchived: json['is_archived'] == null
          ? false
          : const BoolIntConverter().fromJson(json['is_archived']),
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
      lastFetchedAt: (json['last_fetched_at'] as num).toInt(),
    );

Map<String, dynamic> _$LlmProviderModelToJson(LlmProviderModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'provider_code': instance.providerCode,
      'model_id': instance.modelId,
      'display_name': instance.displayName,
      'is_enabled': const BoolIntConverter().toJson(instance.isEnabled),
      'is_default': const BoolIntConverter().toJson(instance.isDefault),
      'is_archived': const BoolIntConverter().toJson(instance.isArchived),
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
      'last_fetched_at': instance.lastFetchedAt,
    };
