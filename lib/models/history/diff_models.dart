import 'package:json_annotation/json_annotation.dart';
import '../domain/translation_version_history.dart';

part 'diff_models.g.dart';

/// Type of difference in text comparison
enum DiffType {
  /// Text segment is unchanged
  unchanged,

  /// Text segment was added in new version
  added,

  /// Text segment was removed in old version
  removed,
}

/// Represents a segment of text in a diff comparison
@JsonSerializable()
class DiffSegment {
  /// The text content of this segment
  final String text;

  /// Type of difference (unchanged, added, removed)
  final DiffType type;

  const DiffSegment({
    required this.text,
    required this.type,
  });

  DiffSegment copyWith({
    String? text,
    DiffType? type,
  }) {
    return DiffSegment(
      text: text ?? this.text,
      type: type ?? this.type,
    );
  }

  factory DiffSegment.fromJson(Map<String, dynamic> json) =>
      _$DiffSegmentFromJson(json);

  Map<String, dynamic> toJson() => _$DiffSegmentToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiffSegment &&
        other.text == text &&
        other.type == type;
  }

  @override
  int get hashCode => text.hashCode ^ type.hashCode;

  @override
  String toString() => 'DiffSegment(text: $text, type: $type)';
}

/// Statistics about differences between two versions
@JsonSerializable()
class DiffStats {
  /// Number of characters added
  final int charsAdded;

  /// Number of characters removed
  final int charsRemoved;

  /// Number of words added
  final int wordsAdded;

  /// Number of words removed
  final int wordsRemoved;

  /// Number of characters changed (added + removed)
  final int charsChanged;

  /// Number of words changed (added + removed)
  final int wordsChanged;

  const DiffStats({
    this.charsAdded = 0,
    this.charsRemoved = 0,
    this.wordsAdded = 0,
    this.wordsRemoved = 0,
    this.charsChanged = 0,
    this.wordsChanged = 0,
  });

  /// Calculate stats from diff segments
  factory DiffStats.fromSegments(List<DiffSegment> segments) {
    int charsAdded = 0;
    int charsRemoved = 0;

    for (final segment in segments) {
      switch (segment.type) {
        case DiffType.added:
          charsAdded += segment.text.length;
          break;
        case DiffType.removed:
          charsRemoved += segment.text.length;
          break;
        case DiffType.unchanged:
          break;
      }
    }

    // Calculate word changes (simple word count by splitting on whitespace)
    final wordsAdded = segments
        .where((s) => s.type == DiffType.added)
        .map((s) => s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length)
        .fold<int>(0, (sum, count) => sum + count);

    final wordsRemoved = segments
        .where((s) => s.type == DiffType.removed)
        .map((s) => s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length)
        .fold<int>(0, (sum, count) => sum + count);

    return DiffStats(
      charsAdded: charsAdded,
      charsRemoved: charsRemoved,
      wordsAdded: wordsAdded,
      wordsRemoved: wordsRemoved,
      charsChanged: charsAdded + charsRemoved,
      wordsChanged: wordsAdded + wordsRemoved,
    );
  }

  DiffStats copyWith({
    int? charsAdded,
    int? charsRemoved,
    int? wordsAdded,
    int? wordsRemoved,
    int? charsChanged,
    int? wordsChanged,
  }) {
    return DiffStats(
      charsAdded: charsAdded ?? this.charsAdded,
      charsRemoved: charsRemoved ?? this.charsRemoved,
      wordsAdded: wordsAdded ?? this.wordsAdded,
      wordsRemoved: wordsRemoved ?? this.wordsRemoved,
      charsChanged: charsChanged ?? this.charsChanged,
      wordsChanged: wordsChanged ?? this.wordsChanged,
    );
  }

  factory DiffStats.fromJson(Map<String, dynamic> json) =>
      _$DiffStatsFromJson(json);

  Map<String, dynamic> toJson() => _$DiffStatsToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiffStats &&
        other.charsAdded == charsAdded &&
        other.charsRemoved == charsRemoved &&
        other.wordsAdded == wordsAdded &&
        other.wordsRemoved == wordsRemoved &&
        other.charsChanged == charsChanged &&
        other.wordsChanged == wordsChanged;
  }

  @override
  int get hashCode =>
      charsAdded.hashCode ^
      charsRemoved.hashCode ^
      wordsAdded.hashCode ^
      wordsRemoved.hashCode ^
      charsChanged.hashCode ^
      wordsChanged.hashCode;

  @override
  String toString() =>
      'DiffStats(charsAdded: $charsAdded, charsRemoved: $charsRemoved, wordsAdded: $wordsAdded, wordsRemoved: $wordsRemoved)';
}

/// Comparison between two translation version history entries
@JsonSerializable()
class VersionComparison {
  /// Older version (left side in comparison)
  final TranslationVersionHistory version1;

  /// Newer version (right side in comparison)
  final TranslationVersionHistory version2;

  /// List of diff segments showing the differences
  final List<DiffSegment> diff;

  /// Statistics about the differences
  final DiffStats stats;

  const VersionComparison({
    required this.version1,
    required this.version2,
    required this.diff,
    required this.stats,
  });

  VersionComparison copyWith({
    TranslationVersionHistory? version1,
    TranslationVersionHistory? version2,
    List<DiffSegment>? diff,
    DiffStats? stats,
  }) {
    return VersionComparison(
      version1: version1 ?? this.version1,
      version2: version2 ?? this.version2,
      diff: diff ?? this.diff,
      stats: stats ?? this.stats,
    );
  }

  factory VersionComparison.fromJson(Map<String, dynamic> json) =>
      _$VersionComparisonFromJson(json);

  Map<String, dynamic> toJson() => _$VersionComparisonToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VersionComparison &&
        other.version1 == version1 &&
        other.version2 == version2 &&
        _listEquals(other.diff, diff) &&
        other.stats == stats;
  }

  @override
  int get hashCode =>
      version1.hashCode ^
      version2.hashCode ^
      diff.hashCode ^
      stats.hashCode;

  @override
  String toString() =>
      'VersionComparison(version1: ${version1.id}, version2: ${version2.id}, diffSegments: ${diff.length})';

  bool _listEquals(List<DiffSegment> a, List<DiffSegment> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Statistics about translation history
@JsonSerializable()
class HistoryStats {
  /// Total number of history entries
  final int totalEntries;

  /// Number of manual edits by users
  final int manualEdits;

  /// Number of LLM translations
  final int llmTranslations;

  /// Number of reverts to previous versions
  final int reverts;

  /// Number of system changes
  final int systemChanges;

  /// Changes by user ID (user_id -> count)
  final Map<String, int> changesByUser;

  /// Changes by LLM provider (provider_code -> count)
  final Map<String, int> changesByLlm;

  /// Most recent change timestamp
  final int? mostRecentChange;

  /// Oldest change timestamp
  final int? oldestChange;

  const HistoryStats({
    this.totalEntries = 0,
    this.manualEdits = 0,
    this.llmTranslations = 0,
    this.reverts = 0,
    this.systemChanges = 0,
    this.changesByUser = const {},
    this.changesByLlm = const {},
    this.mostRecentChange,
    this.oldestChange,
  });

  HistoryStats copyWith({
    int? totalEntries,
    int? manualEdits,
    int? llmTranslations,
    int? reverts,
    int? systemChanges,
    Map<String, int>? changesByUser,
    Map<String, int>? changesByLlm,
    int? mostRecentChange,
    int? oldestChange,
  }) {
    return HistoryStats(
      totalEntries: totalEntries ?? this.totalEntries,
      manualEdits: manualEdits ?? this.manualEdits,
      llmTranslations: llmTranslations ?? this.llmTranslations,
      reverts: reverts ?? this.reverts,
      systemChanges: systemChanges ?? this.systemChanges,
      changesByUser: changesByUser ?? this.changesByUser,
      changesByLlm: changesByLlm ?? this.changesByLlm,
      mostRecentChange: mostRecentChange ?? this.mostRecentChange,
      oldestChange: oldestChange ?? this.oldestChange,
    );
  }

  factory HistoryStats.fromJson(Map<String, dynamic> json) =>
      _$HistoryStatsFromJson(json);

  Map<String, dynamic> toJson() => _$HistoryStatsToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryStats &&
        other.totalEntries == totalEntries &&
        other.manualEdits == manualEdits &&
        other.llmTranslations == llmTranslations &&
        other.reverts == reverts &&
        other.systemChanges == systemChanges &&
        _mapEquals(other.changesByUser, changesByUser) &&
        _mapEquals(other.changesByLlm, changesByLlm) &&
        other.mostRecentChange == mostRecentChange &&
        other.oldestChange == oldestChange;
  }

  @override
  int get hashCode =>
      totalEntries.hashCode ^
      manualEdits.hashCode ^
      llmTranslations.hashCode ^
      reverts.hashCode ^
      systemChanges.hashCode ^
      changesByUser.hashCode ^
      changesByLlm.hashCode ^
      mostRecentChange.hashCode ^
      oldestChange.hashCode;

  @override
  String toString() =>
      'HistoryStats(totalEntries: $totalEntries, manualEdits: $manualEdits, llmTranslations: $llmTranslations)';

  bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
