// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_memory_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationMemoryEntry _$TranslationMemoryEntryFromJson(
  Map<String, dynamic> json,
) => TranslationMemoryEntry(
  id: json['id'] as String,
  sourceText: json['source_text'] as String,
  sourceHash: json['source_hash'] as String,
  targetLanguageId: json['target_language_id'] as String,
  translatedText: json['translated_text'] as String,
  gameContext: json['game_context'] as String?,
  translationProviderId: json['translation_provider_id'] as String?,
  qualityScore: (json['quality_score'] as num?)?.toDouble(),
  usageCount: (json['usage_count'] as num?)?.toInt() ?? 1,
  createdAt: (json['created_at'] as num).toInt(),
  lastUsedAt: (json['last_used_at'] as num).toInt(),
  updatedAt: (json['updated_at'] as num).toInt(),
);

Map<String, dynamic> _$TranslationMemoryEntryToJson(
  TranslationMemoryEntry instance,
) => <String, dynamic>{
  'id': instance.id,
  'source_text': instance.sourceText,
  'source_hash': instance.sourceHash,
  'target_language_id': instance.targetLanguageId,
  'translated_text': instance.translatedText,
  'game_context': instance.gameContext,
  'translation_provider_id': instance.translationProviderId,
  'quality_score': instance.qualityScore,
  'usage_count': instance.usageCount,
  'created_at': instance.createdAt,
  'last_used_at': instance.lastUsedAt,
  'updated_at': instance.updatedAt,
};
