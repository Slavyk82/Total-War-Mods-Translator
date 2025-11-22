import 'package:json_annotation/json_annotation.dart';

part 'mod_version_change.g.dart';

/// Mod version change type enumeration
enum ModVersionChangeType {
  @JsonValue('added')
  added,
  @JsonValue('modified')
  modified,
  @JsonValue('deleted')
  deleted,
}

/// Represents a detailed change to a translation unit between mod versions.
///
/// Mod version changes track what specifically changed when a mod is updated.
/// This allows the system to identify which translations need to be updated
/// and helps maintain translation accuracy across mod versions.
@JsonSerializable()
class ModVersionChange {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the mod version this change belongs to
  @JsonKey(name: 'version_id')
  final String versionId;

  /// The key of the translation unit that changed
  @JsonKey(name: 'unit_key')
  final String unitKey;

  /// Type of change (added, modified, deleted)
  @JsonKey(name: 'change_type')
  final ModVersionChangeType changeType;

  /// The old source text (null if added)
  @JsonKey(name: 'old_source_text')
  final String? oldSourceText;

  /// The new source text (null if deleted)
  @JsonKey(name: 'new_source_text')
  final String? newSourceText;

  /// Unix timestamp when the change was detected
  @JsonKey(name: 'detected_at')
  final int detectedAt;

  const ModVersionChange({
    required this.id,
    required this.versionId,
    required this.unitKey,
    required this.changeType,
    this.oldSourceText,
    this.newSourceText,
    required this.detectedAt,
  });

  /// Returns true if this is an addition
  bool get isAddition => changeType == ModVersionChangeType.added;

  /// Returns true if this is a modification
  bool get isModification => changeType == ModVersionChangeType.modified;

  /// Returns true if this is a deletion
  bool get isDeletion => changeType == ModVersionChangeType.deleted;

  /// Returns true if the source text was provided (not deleted)
  bool get hasNewText => newSourceText != null && newSourceText!.isNotEmpty;

  /// Returns true if old text was provided (not added)
  bool get hasOldText => oldSourceText != null && oldSourceText!.isNotEmpty;

  /// Returns a change type display string
  String get changeTypeDisplay {
    switch (changeType) {
      case ModVersionChangeType.added:
        return 'Added';
      case ModVersionChangeType.modified:
        return 'Modified';
      case ModVersionChangeType.deleted:
        return 'Deleted';
    }
  }

  /// Returns a change type symbol
  String get changeTypeSymbol {
    switch (changeType) {
      case ModVersionChangeType.added:
        return '+';
      case ModVersionChangeType.modified:
        return '~';
      case ModVersionChangeType.deleted:
        return '-';
    }
  }

  /// Returns a summary of the change
  String get changeSummary {
    switch (changeType) {
      case ModVersionChangeType.added:
        return 'Added: $unitKey';
      case ModVersionChangeType.modified:
        return 'Modified: $unitKey';
      case ModVersionChangeType.deleted:
        return 'Deleted: $unitKey';
    }
  }

  /// Returns the relevant text (new for added/modified, old for deleted)
  String? get relevantText {
    if (isDeletion) return oldSourceText;
    return newSourceText;
  }

  /// Returns a preview of the old text
  String? getOldTextPreview([int maxLength = 50]) {
    if (oldSourceText == null || oldSourceText!.isEmpty) return null;
    if (oldSourceText!.length <= maxLength) return oldSourceText;
    return '${oldSourceText!.substring(0, maxLength)}...';
  }

  /// Returns a preview of the new text
  String? getNewTextPreview([int maxLength = 50]) {
    if (newSourceText == null || newSourceText!.isEmpty) return null;
    if (newSourceText!.length <= maxLength) return newSourceText;
    return '${newSourceText!.substring(0, maxLength)}...';
  }

  /// Returns a detailed change description
  String get detailedDescription {
    switch (changeType) {
      case ModVersionChangeType.added:
        return 'Added new translation unit: "$unitKey"';
      case ModVersionChangeType.modified:
        return 'Modified translation unit: "$unitKey"\nOld: ${getOldTextPreview()}\nNew: ${getNewTextPreview()}';
      case ModVersionChangeType.deleted:
        return 'Deleted translation unit: "$unitKey"';
    }
  }

  /// Returns the detected date as DateTime
  DateTime get detectedAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(detectedAt * 1000);

  ModVersionChange copyWith({
    String? id,
    String? versionId,
    String? unitKey,
    ModVersionChangeType? changeType,
    String? oldSourceText,
    String? newSourceText,
    int? detectedAt,
  }) {
    return ModVersionChange(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      unitKey: unitKey ?? this.unitKey,
      changeType: changeType ?? this.changeType,
      oldSourceText: oldSourceText ?? this.oldSourceText,
      newSourceText: newSourceText ?? this.newSourceText,
      detectedAt: detectedAt ?? this.detectedAt,
    );
  }

  factory ModVersionChange.fromJson(Map<String, dynamic> json) =>
      _$ModVersionChangeFromJson(json);

  Map<String, dynamic> toJson() => _$ModVersionChangeToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModVersionChange &&
        other.id == id &&
        other.versionId == versionId &&
        other.unitKey == unitKey &&
        other.changeType == changeType &&
        other.oldSourceText == oldSourceText &&
        other.newSourceText == newSourceText &&
        other.detectedAt == detectedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      versionId.hashCode ^
      unitKey.hashCode ^
      changeType.hashCode ^
      oldSourceText.hashCode ^
      newSourceText.hashCode ^
      detectedAt.hashCode;

  @override
  String toString() => 'ModVersionChange(id: $id, unitKey: $unitKey, changeType: $changeTypeDisplay)';
}
