import 'package:json_annotation/json_annotation.dart';
import 'language.dart' show BoolIntConverter;

part 'mod_version.g.dart';

/// Represents a version of a source mod being translated.
///
/// Mod versions track changes to the source mod over time. When a mod is updated,
/// a new version is created to track what translation units were added, modified,
/// or deleted.
@JsonSerializable()
class ModVersion {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the parent project
  @JsonKey(name: 'project_id')
  final String projectId;

  /// Version string (e.g., '1.0.0', '2.3.4')
  @JsonKey(name: 'version_string')
  final String versionString;

  /// Unix timestamp of the mod release date
  @JsonKey(name: 'release_date')
  final int? releaseDate;

  /// Unix timestamp from Steam Workshop update
  @JsonKey(name: 'steam_update_timestamp')
  final int? steamUpdateTimestamp;

  /// Number of translation units added in this version
  @JsonKey(name: 'units_added')
  final int unitsAdded;

  /// Number of translation units modified in this version
  @JsonKey(name: 'units_modified')
  final int unitsModified;

  /// Number of translation units deleted in this version
  @JsonKey(name: 'units_deleted')
  final int unitsDeleted;

  /// Whether this is the current version of the mod
  @JsonKey(name: 'is_current')
  @BoolIntConverter()
  final bool isCurrent;

  /// Unix timestamp when this version was detected
  @JsonKey(name: 'detected_at')
  final int detectedAt;

  const ModVersion({
    required this.id,
    required this.projectId,
    required this.versionString,
    this.releaseDate,
    this.steamUpdateTimestamp,
    this.unitsAdded = 0,
    this.unitsModified = 0,
    this.unitsDeleted = 0,
    this.isCurrent = true,
    required this.detectedAt,
  });

  /// Returns true if this is the current version
  bool get isCurrentVersion => isCurrent;

  /// Returns true if this version has changes
  bool get hasChanges =>
      unitsAdded > 0 || unitsModified > 0 || unitsDeleted > 0;

  /// Returns the total number of changes
  int get totalChanges => unitsAdded + unitsModified + unitsDeleted;

  /// Returns true if this version has additions
  bool get hasAdditions => unitsAdded > 0;

  /// Returns true if this version has modifications
  bool get hasModifications => unitsModified > 0;

  /// Returns true if this version has deletions
  bool get hasDeletions => unitsDeleted > 0;

  /// Returns true if this version is from Steam Workshop
  bool get isFromSteam => steamUpdateTimestamp != null;

  /// Returns true if this version has a release date
  bool get hasReleaseDate => releaseDate != null;

  /// Returns a summary of changes
  String get changesSummary {
    final parts = <String>[];
    if (unitsAdded > 0) parts.add('+$unitsAdded added');
    if (unitsModified > 0) parts.add('~$unitsModified modified');
    if (unitsDeleted > 0) parts.add('-$unitsDeleted deleted');
    return parts.isEmpty ? 'No changes' : parts.join(', ');
  }

  /// Returns a display name with version and current status
  String get displayName {
    final currentTag = isCurrent ? ' (Current)' : '';
    return '$versionString$currentTag';
  }

  /// Returns the release date as DateTime (if available)
  DateTime? get releaseDateAsDateTime {
    if (releaseDate == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(releaseDate! * 1000);
  }

  /// Returns the Steam update timestamp as DateTime (if available)
  DateTime? get steamUpdateAsDateTime {
    if (steamUpdateTimestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(steamUpdateTimestamp! * 1000);
  }

  ModVersion copyWith({
    String? id,
    String? projectId,
    String? versionString,
    int? releaseDate,
    int? steamUpdateTimestamp,
    int? unitsAdded,
    int? unitsModified,
    int? unitsDeleted,
    bool? isCurrent,
    int? detectedAt,
  }) {
    return ModVersion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      versionString: versionString ?? this.versionString,
      releaseDate: releaseDate ?? this.releaseDate,
      steamUpdateTimestamp: steamUpdateTimestamp ?? this.steamUpdateTimestamp,
      unitsAdded: unitsAdded ?? this.unitsAdded,
      unitsModified: unitsModified ?? this.unitsModified,
      unitsDeleted: unitsDeleted ?? this.unitsDeleted,
      isCurrent: isCurrent ?? this.isCurrent,
      detectedAt: detectedAt ?? this.detectedAt,
    );
  }

  factory ModVersion.fromJson(Map<String, dynamic> json) =>
      _$ModVersionFromJson(json);

  Map<String, dynamic> toJson() => _$ModVersionToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModVersion &&
        other.id == id &&
        other.projectId == projectId &&
        other.versionString == versionString &&
        other.releaseDate == releaseDate &&
        other.steamUpdateTimestamp == steamUpdateTimestamp &&
        other.unitsAdded == unitsAdded &&
        other.unitsModified == unitsModified &&
        other.unitsDeleted == unitsDeleted &&
        other.isCurrent == isCurrent &&
        other.detectedAt == detectedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      projectId.hashCode ^
      versionString.hashCode ^
      releaseDate.hashCode ^
      steamUpdateTimestamp.hashCode ^
      unitsAdded.hashCode ^
      unitsModified.hashCode ^
      unitsDeleted.hashCode ^
      isCurrent.hashCode ^
      detectedAt.hashCode;

  @override
  String toString() => 'ModVersion(id: $id, versionString: $versionString, isCurrent: $isCurrent, changes: $changesSummary)';
}
