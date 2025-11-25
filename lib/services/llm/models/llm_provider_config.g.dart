// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_provider_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlmProviderConfig _$LlmProviderConfigFromJson(Map<String, dynamic> json) =>
    LlmProviderConfig(
      providerCode: json['providerCode'] as String,
      providerName: json['providerName'] as String,
      apiBaseUrl: json['apiBaseUrl'] as String,
      supportsStreaming: json['supportsStreaming'] as bool,
      maxTokensPerRequest: (json['maxTokensPerRequest'] as num).toInt(),
      defaultRateLimitRpm: (json['defaultRateLimitRpm'] as num).toInt(),
      defaultRateLimitTpm: (json['defaultRateLimitTpm'] as num?)?.toInt(),
      retryConfig: RetryConfig.fromJson(
        json['retryConfig'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$LlmProviderConfigToJson(LlmProviderConfig instance) =>
    <String, dynamic>{
      'providerCode': instance.providerCode,
      'providerName': instance.providerName,
      'apiBaseUrl': instance.apiBaseUrl,
      'supportsStreaming': instance.supportsStreaming,
      'maxTokensPerRequest': instance.maxTokensPerRequest,
      'defaultRateLimitRpm': instance.defaultRateLimitRpm,
      'defaultRateLimitTpm': instance.defaultRateLimitTpm,
      'retryConfig': instance.retryConfig,
    };

RetryConfig _$RetryConfigFromJson(Map<String, dynamic> json) => RetryConfig(
  maxRetries: (json['maxRetries'] as num).toInt(),
  initialDelayMs: (json['initialDelayMs'] as num).toInt(),
  maxDelayMs: (json['maxDelayMs'] as num).toInt(),
  backoffMultiplier: (json['backoffMultiplier'] as num).toDouble(),
  retryOnRateLimit: json['retryOnRateLimit'] as bool,
  retryOnTimeout: json['retryOnTimeout'] as bool,
  retryOnServerError: json['retryOnServerError'] as bool,
);

Map<String, dynamic> _$RetryConfigToJson(RetryConfig instance) =>
    <String, dynamic>{
      'maxRetries': instance.maxRetries,
      'initialDelayMs': instance.initialDelayMs,
      'maxDelayMs': instance.maxDelayMs,
      'backoffMultiplier': instance.backoffMultiplier,
      'retryOnRateLimit': instance.retryOnRateLimit,
      'retryOnTimeout': instance.retryOnTimeout,
      'retryOnServerError': instance.retryOnServerError,
    };
