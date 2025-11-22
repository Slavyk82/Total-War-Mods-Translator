// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tm_match.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TmMatch _$TmMatchFromJson(Map<String, dynamic> json) => TmMatch(
  entryId: json['entryId'] as String,
  sourceText: json['sourceText'] as String,
  targetText: json['targetText'] as String,
  targetLanguageCode: json['targetLanguageCode'] as String,
  similarityScore: (json['similarityScore'] as num).toDouble(),
  matchType: $enumDecode(_$TmMatchTypeEnumMap, json['matchType']),
  breakdown: SimilarityBreakdown.fromJson(
    json['breakdown'] as Map<String, dynamic>,
  ),
  gameContext: json['gameContext'] as String?,
  category: json['category'] as String?,
  usageCount: (json['usageCount'] as num).toInt(),
  lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
  qualityScore: (json['qualityScore'] as num).toDouble(),
  autoApplied: json['autoApplied'] as bool? ?? false,
);

Map<String, dynamic> _$TmMatchToJson(TmMatch instance) => <String, dynamic>{
  'entryId': instance.entryId,
  'sourceText': instance.sourceText,
  'targetText': instance.targetText,
  'targetLanguageCode': instance.targetLanguageCode,
  'similarityScore': instance.similarityScore,
  'matchType': _$TmMatchTypeEnumMap[instance.matchType]!,
  'breakdown': instance.breakdown,
  'gameContext': instance.gameContext,
  'category': instance.category,
  'usageCount': instance.usageCount,
  'lastUsedAt': instance.lastUsedAt.toIso8601String(),
  'qualityScore': instance.qualityScore,
  'autoApplied': instance.autoApplied,
};

const _$TmMatchTypeEnumMap = {
  TmMatchType.exact: 'exact',
  TmMatchType.fuzzy: 'fuzzy',
  TmMatchType.context: 'context',
};

SimilarityBreakdown _$SimilarityBreakdownFromJson(Map<String, dynamic> json) =>
    SimilarityBreakdown(
      levenshteinScore: (json['levenshteinScore'] as num).toDouble(),
      jaroWinklerScore: (json['jaroWinklerScore'] as num).toDouble(),
      tokenScore: (json['tokenScore'] as num).toDouble(),
      contextBoost: (json['contextBoost'] as num).toDouble(),
      weights: ScoreWeights.fromJson(json['weights'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SimilarityBreakdownToJson(
  SimilarityBreakdown instance,
) => <String, dynamic>{
  'levenshteinScore': instance.levenshteinScore,
  'jaroWinklerScore': instance.jaroWinklerScore,
  'tokenScore': instance.tokenScore,
  'contextBoost': instance.contextBoost,
  'weights': instance.weights,
};

ScoreWeights _$ScoreWeightsFromJson(Map<String, dynamic> json) => ScoreWeights(
  levenshteinWeight: (json['levenshteinWeight'] as num?)?.toDouble() ?? 0.4,
  jaroWinklerWeight: (json['jaroWinklerWeight'] as num?)?.toDouble() ?? 0.3,
  tokenWeight: (json['tokenWeight'] as num?)?.toDouble() ?? 0.3,
);

Map<String, dynamic> _$ScoreWeightsToJson(ScoreWeights instance) =>
    <String, dynamic>{
      'levenshteinWeight': instance.levenshteinWeight,
      'jaroWinklerWeight': instance.jaroWinklerWeight,
      'tokenWeight': instance.tokenWeight,
    };
