// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diff_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiffSegment _$DiffSegmentFromJson(Map<String, dynamic> json) => DiffSegment(
  text: json['text'] as String,
  type: $enumDecode(_$DiffTypeEnumMap, json['type']),
);

Map<String, dynamic> _$DiffSegmentToJson(DiffSegment instance) =>
    <String, dynamic>{
      'text': instance.text,
      'type': _$DiffTypeEnumMap[instance.type]!,
    };

const _$DiffTypeEnumMap = {
  DiffType.unchanged: 'unchanged',
  DiffType.added: 'added',
  DiffType.removed: 'removed',
};

DiffStats _$DiffStatsFromJson(Map<String, dynamic> json) => DiffStats(
  charsAdded: (json['charsAdded'] as num?)?.toInt() ?? 0,
  charsRemoved: (json['charsRemoved'] as num?)?.toInt() ?? 0,
  wordsAdded: (json['wordsAdded'] as num?)?.toInt() ?? 0,
  wordsRemoved: (json['wordsRemoved'] as num?)?.toInt() ?? 0,
  charsChanged: (json['charsChanged'] as num?)?.toInt() ?? 0,
  wordsChanged: (json['wordsChanged'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$DiffStatsToJson(DiffStats instance) => <String, dynamic>{
  'charsAdded': instance.charsAdded,
  'charsRemoved': instance.charsRemoved,
  'wordsAdded': instance.wordsAdded,
  'wordsRemoved': instance.wordsRemoved,
  'charsChanged': instance.charsChanged,
  'wordsChanged': instance.wordsChanged,
};

VersionComparison _$VersionComparisonFromJson(Map<String, dynamic> json) =>
    VersionComparison(
      version1: TranslationVersionHistory.fromJson(
        json['version1'] as Map<String, dynamic>,
      ),
      version2: TranslationVersionHistory.fromJson(
        json['version2'] as Map<String, dynamic>,
      ),
      diff: (json['diff'] as List<dynamic>)
          .map((e) => DiffSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      stats: DiffStats.fromJson(json['stats'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$VersionComparisonToJson(VersionComparison instance) =>
    <String, dynamic>{
      'version1': instance.version1,
      'version2': instance.version2,
      'diff': instance.diff,
      'stats': instance.stats,
    };

HistoryStats _$HistoryStatsFromJson(Map<String, dynamic> json) => HistoryStats(
  totalEntries: (json['totalEntries'] as num?)?.toInt() ?? 0,
  manualEdits: (json['manualEdits'] as num?)?.toInt() ?? 0,
  llmTranslations: (json['llmTranslations'] as num?)?.toInt() ?? 0,
  reverts: (json['reverts'] as num?)?.toInt() ?? 0,
  systemChanges: (json['systemChanges'] as num?)?.toInt() ?? 0,
  changesByUser:
      (json['changesByUser'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const {},
  changesByLlm:
      (json['changesByLlm'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const {},
  mostRecentChange: (json['mostRecentChange'] as num?)?.toInt(),
  oldestChange: (json['oldestChange'] as num?)?.toInt(),
);

Map<String, dynamic> _$HistoryStatsToJson(HistoryStats instance) =>
    <String, dynamic>{
      'totalEntries': instance.totalEntries,
      'manualEdits': instance.manualEdits,
      'llmTranslations': instance.llmTranslations,
      'reverts': instance.reverts,
      'systemChanges': instance.systemChanges,
      'changesByUser': instance.changesByUser,
      'changesByLlm': instance.changesByLlm,
      'mostRecentChange': instance.mostRecentChange,
      'oldestChange': instance.oldestChange,
    };
