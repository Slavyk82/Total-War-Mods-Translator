// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_provider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationProvider _$TranslationProviderFromJson(Map<String, dynamic> json) =>
    TranslationProvider(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      apiEndpoint: json['api_endpoint'] as String?,
      defaultModel: json['default_model'] as String?,
      maxContextTokens: (json['max_context_tokens'] as num?)?.toInt(),
      maxBatchSize: (json['max_batch_size'] as num?)?.toInt() ?? 30,
      rateLimitRpm: (json['rate_limit_rpm'] as num?)?.toInt(),
      rateLimitTpm: (json['rate_limit_tpm'] as num?)?.toInt(),
      isActive: json['is_active'] == null
          ? true
          : const BoolIntConverter().fromJson(json['is_active']),
      createdAt: (json['created_at'] as num).toInt(),
    );

Map<String, dynamic> _$TranslationProviderToJson(
  TranslationProvider instance,
) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'name': instance.name,
  'api_endpoint': instance.apiEndpoint,
  'default_model': instance.defaultModel,
  'max_context_tokens': instance.maxContextTokens,
  'max_batch_size': instance.maxBatchSize,
  'rate_limit_rpm': instance.rateLimitRpm,
  'rate_limit_tpm': instance.rateLimitTpm,
  'is_active': const BoolIntConverter().toJson(instance.isActive),
  'created_at': instance.createdAt,
};
