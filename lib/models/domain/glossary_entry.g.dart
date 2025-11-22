// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glossary_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GlossaryEntry _$GlossaryEntryFromJson(Map<String, dynamic> json) =>
    GlossaryEntry(
      id: json['id'] as String,
      glossaryId: json['glossary_id'] as String,
      targetLanguageCode: json['target_language_code'] as String,
      sourceTerm: json['source_term'] as String,
      targetTerm: json['target_term'] as String,
      category: json['category'] as String?,
      caseSensitive: json['case_sensitive'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
    );

Map<String, dynamic> _$GlossaryEntryToJson(GlossaryEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'glossary_id': instance.glossaryId,
      'target_language_code': instance.targetLanguageCode,
      'source_term': instance.sourceTerm,
      'target_term': instance.targetTerm,
      'category': instance.category,
      'case_sensitive': instance.caseSensitive,
      'notes': instance.notes,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };
