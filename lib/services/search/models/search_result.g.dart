// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchResult _$SearchResultFromJson(Map<String, dynamic> json) => SearchResult(
  id: json['id'] as String,
  type: $enumDecode(_$SearchResultTypeEnumMap, json['type']),
  projectId: json['projectId'] as String?,
  projectName: json['projectName'] as String?,
  languageCode: json['languageCode'] as String?,
  languageName: json['languageName'] as String?,
  key: json['key'] as String?,
  sourceText: json['sourceText'] as String?,
  translatedText: json['translatedText'] as String?,
  matchedField: json['matchedField'] as String,
  highlightedText: json['highlightedText'] as String,
  relevanceScore: (json['relevanceScore'] as num).toDouble(),
  context: json['context'] as String?,
  fileName: json['fileName'] as String?,
  category: json['category'] as String?,
  status: json['status'] as String?,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$SearchResultToJson(SearchResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$SearchResultTypeEnumMap[instance.type]!,
      'projectId': instance.projectId,
      'projectName': instance.projectName,
      'languageCode': instance.languageCode,
      'languageName': instance.languageName,
      'key': instance.key,
      'sourceText': instance.sourceText,
      'translatedText': instance.translatedText,
      'matchedField': instance.matchedField,
      'highlightedText': instance.highlightedText,
      'relevanceScore': instance.relevanceScore,
      'context': instance.context,
      'fileName': instance.fileName,
      'category': instance.category,
      'status': instance.status,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };

const _$SearchResultTypeEnumMap = {
  SearchResultType.translationUnit: 'translationUnit',
  SearchResultType.translationVersion: 'translationVersion',
  SearchResultType.translationMemory: 'translationMemory',
  SearchResultType.glossaryEntry: 'glossaryEntry',
};

SearchFilter _$SearchFilterFromJson(Map<String, dynamic> json) => SearchFilter(
  projectIds: (json['projectIds'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  languageCodes: (json['languageCodes'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  statuses: (json['statuses'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  fileNames: (json['fileNames'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  types: (json['types'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$SearchResultTypeEnumMap, e))
      .toList(),
  minDate: json['minDate'] == null
      ? null
      : DateTime.parse(json['minDate'] as String),
  maxDate: json['maxDate'] == null
      ? null
      : DateTime.parse(json['maxDate'] as String),
  minRelevanceScore: (json['minRelevanceScore'] as num?)?.toDouble(),
);

Map<String, dynamic> _$SearchFilterToJson(
  SearchFilter instance,
) => <String, dynamic>{
  'projectIds': instance.projectIds,
  'languageCodes': instance.languageCodes,
  'statuses': instance.statuses,
  'fileNames': instance.fileNames,
  'types': instance.types?.map((e) => _$SearchResultTypeEnumMap[e]!).toList(),
  'minDate': instance.minDate?.toIso8601String(),
  'maxDate': instance.maxDate?.toIso8601String(),
  'minRelevanceScore': instance.minRelevanceScore,
};

SavedSearch _$SavedSearchFromJson(Map<String, dynamic> json) => SavedSearch(
  id: json['id'] as String,
  name: json['name'] as String,
  query: json['query'] as String,
  filter: json['filter'] == null
      ? null
      : SearchFilter.fromJson(json['filter'] as Map<String, dynamic>),
  createdAt: DateTime.parse(json['createdAt'] as String),
  lastUsedAt: json['lastUsedAt'] == null
      ? null
      : DateTime.parse(json['lastUsedAt'] as String),
  usageCount: (json['usageCount'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$SavedSearchToJson(SavedSearch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'query': instance.query,
      'filter': instance.filter,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastUsedAt': instance.lastUsedAt?.toIso8601String(),
      'usageCount': instance.usageCount,
    };
