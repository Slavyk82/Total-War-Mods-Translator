// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conflict_resolution.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ConflictInfo _$ConflictInfoFromJson(Map<String, dynamic> json) => ConflictInfo(
  id: json['id'] as String,
  translationUnitId: json['translationUnitId'] as String,
  languageCode: json['languageCode'] as String,
  conflictType: $enumDecode(_$ConflictTypeEnumMap, json['conflictType']),
  currentValue: json['currentValue'] as String,
  currentVersion: (json['currentVersion'] as num).toInt(),
  currentSource: json['currentSource'] as String,
  currentTimestamp: DateTime.parse(json['currentTimestamp'] as String),
  incomingValue: json['incomingValue'] as String,
  incomingVersion: (json['incomingVersion'] as num).toInt(),
  incomingSource: json['incomingSource'] as String,
  incomingTimestamp: DateTime.parse(json['incomingTimestamp'] as String),
  similarityScore: (json['similarityScore'] as num).toDouble(),
  canAutoResolve: json['canAutoResolve'] as bool,
  suggestedStrategy: $enumDecodeNullable(
    _$ResolutionStrategyEnumMap,
    json['suggestedStrategy'],
  ),
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ConflictInfoToJson(
  ConflictInfo instance,
) => <String, dynamic>{
  'id': instance.id,
  'translationUnitId': instance.translationUnitId,
  'languageCode': instance.languageCode,
  'conflictType': _$ConflictTypeEnumMap[instance.conflictType]!,
  'currentValue': instance.currentValue,
  'currentVersion': instance.currentVersion,
  'currentSource': instance.currentSource,
  'currentTimestamp': instance.currentTimestamp.toIso8601String(),
  'incomingValue': instance.incomingValue,
  'incomingVersion': instance.incomingVersion,
  'incomingSource': instance.incomingSource,
  'incomingTimestamp': instance.incomingTimestamp.toIso8601String(),
  'similarityScore': instance.similarityScore,
  'canAutoResolve': instance.canAutoResolve,
  'suggestedStrategy': _$ResolutionStrategyEnumMap[instance.suggestedStrategy],
  'metadata': instance.metadata,
};

const _$ConflictTypeEnumMap = {
  ConflictType.manualVsLlm: 'manualVsLlm',
  ConflictType.manualVsManual: 'manualVsManual',
  ConflictType.llmVsLlm: 'llmVsLlm',
  ConflictType.versionMismatch: 'versionMismatch',
  ConflictType.lockTimeout: 'lockTimeout',
};

const _$ResolutionStrategyEnumMap = {
  ResolutionStrategy.keepUser: 'keepUser',
  ResolutionStrategy.keepLlm: 'keepLlm',
  ResolutionStrategy.keepNewer: 'keepNewer',
  ResolutionStrategy.keepOlder: 'keepOlder',
  ResolutionStrategy.merge: 'merge',
  ResolutionStrategy.manualResolve: 'manualResolve',
  ResolutionStrategy.keepCurrent: 'keepCurrent',
  ResolutionStrategy.discard: 'discard',
};

ConflictResolution _$ConflictResolutionFromJson(Map<String, dynamic> json) =>
    ConflictResolution(
      conflictId: json['conflictId'] as String,
      strategy: $enumDecode(_$ResolutionStrategyEnumMap, json['strategy']),
      resolvedValue: json['resolvedValue'] as String,
      resolvedVersion: (json['resolvedVersion'] as num).toInt(),
      resolvedSource: json['resolvedSource'] as String,
      resolvedAt: DateTime.parse(json['resolvedAt'] as String),
      resolvedBy: json['resolvedBy'] as String,
      wasAutomatic: json['wasAutomatic'] as bool,
      reason: json['reason'] as String?,
    );

Map<String, dynamic> _$ConflictResolutionToJson(ConflictResolution instance) =>
    <String, dynamic>{
      'conflictId': instance.conflictId,
      'strategy': _$ResolutionStrategyEnumMap[instance.strategy]!,
      'resolvedValue': instance.resolvedValue,
      'resolvedVersion': instance.resolvedVersion,
      'resolvedSource': instance.resolvedSource,
      'resolvedAt': instance.resolvedAt.toIso8601String(),
      'resolvedBy': instance.resolvedBy,
      'wasAutomatic': instance.wasAutomatic,
      'reason': instance.reason,
    };

ConflictResolutionConfig _$ConflictResolutionConfigFromJson(
  Map<String, dynamic> json,
) => ConflictResolutionConfig(
  autoResolveSimilarityThreshold:
      (json['autoResolveSimilarityThreshold'] as num?)?.toDouble() ?? 0.95,
  autoResolveVersionDelta:
      (json['autoResolveVersionDelta'] as num?)?.toInt() ?? 1,
  preferUserEdits: json['preferUserEdits'] as bool? ?? true,
  preferNewerVersions: json['preferNewerVersions'] as bool? ?? true,
  enableAutoMerge: json['enableAutoMerge'] as bool? ?? false,
  concurrentEditWindowMinutes:
      (json['concurrentEditWindowMinutes'] as num?)?.toInt() ?? 5,
);

Map<String, dynamic> _$ConflictResolutionConfigToJson(
  ConflictResolutionConfig instance,
) => <String, dynamic>{
  'autoResolveSimilarityThreshold': instance.autoResolveSimilarityThreshold,
  'autoResolveVersionDelta': instance.autoResolveVersionDelta,
  'preferUserEdits': instance.preferUserEdits,
  'preferNewerVersions': instance.preferNewerVersions,
  'enableAutoMerge': instance.enableAutoMerge,
  'concurrentEditWindowMinutes': instance.concurrentEditWindowMinutes,
};
