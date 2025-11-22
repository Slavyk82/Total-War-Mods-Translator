// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_query_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchOptions _$SearchOptionsFromJson(Map<String, dynamic> json) =>
    SearchOptions(
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      wholeWord: json['wholeWord'] as bool? ?? false,
      useRegex: json['useRegex'] as bool? ?? false,
      phraseSearch: json['phraseSearch'] as bool? ?? false,
      prefixSearch: json['prefixSearch'] as bool? ?? false,
      includeObsolete: json['includeObsolete'] as bool? ?? false,
      resultsPerPage: (json['resultsPerPage'] as num?)?.toInt() ?? 50,
    );

Map<String, dynamic> _$SearchOptionsToJson(SearchOptions instance) =>
    <String, dynamic>{
      'caseSensitive': instance.caseSensitive,
      'wholeWord': instance.wholeWord,
      'useRegex': instance.useRegex,
      'phraseSearch': instance.phraseSearch,
      'prefixSearch': instance.prefixSearch,
      'includeObsolete': instance.includeObsolete,
      'resultsPerPage': instance.resultsPerPage,
    };

SearchQueryModel _$SearchQueryModelFromJson(Map<String, dynamic> json) =>
    SearchQueryModel(
      text: json['text'] as String,
      scope: $enumDecode(_$SearchScopeEnumMap, json['scope']),
      operator: $enumDecode(_$SearchOperatorEnumMap, json['operator']),
      filter: json['filter'] == null
          ? null
          : SearchFilter.fromJson(json['filter'] as Map<String, dynamic>),
      options: SearchOptions.fromJson(json['options'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SearchQueryModelToJson(SearchQueryModel instance) =>
    <String, dynamic>{
      'text': instance.text,
      'scope': _$SearchScopeEnumMap[instance.scope]!,
      'operator': _$SearchOperatorEnumMap[instance.operator]!,
      'filter': instance.filter,
      'options': instance.options,
    };

const _$SearchScopeEnumMap = {
  SearchScope.source: 'source',
  SearchScope.target: 'target',
  SearchScope.both: 'both',
  SearchScope.key: 'key',
  SearchScope.all: 'all',
};

const _$SearchOperatorEnumMap = {
  SearchOperator.and: 'and',
  SearchOperator.or: 'or',
  SearchOperator.not: 'not',
};

SearchResultsModel _$SearchResultsModelFromJson(Map<String, dynamic> json) =>
    SearchResultsModel(
      results: (json['results'] as List<dynamic>)
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: (json['totalCount'] as num).toInt(),
      currentPage: (json['currentPage'] as num).toInt(),
      pageSize: (json['pageSize'] as num).toInt(),
      query: SearchQueryModel.fromJson(json['query'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SearchResultsModelToJson(SearchResultsModel instance) =>
    <String, dynamic>{
      'results': instance.results,
      'totalCount': instance.totalCount,
      'currentPage': instance.currentPage,
      'pageSize': instance.pageSize,
      'query': instance.query,
    };
