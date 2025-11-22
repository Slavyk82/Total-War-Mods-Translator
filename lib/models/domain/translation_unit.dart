import 'package:json_annotation/json_annotation.dart';
import 'language.dart' show BoolIntConverter;

part 'translation_unit.g.dart';

/// Represents a single text unit that needs to be translated.
///
/// Translation units are the atomic elements of translation work. Each unit
/// contains source text from the mod and can have multiple translations
/// (one per target language).
@JsonSerializable()
class TranslationUnit {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the parent project
  @JsonKey(name: 'project_id')
  final String projectId;

  /// Unique key/identifier for this text unit within the mod
  final String key;

  /// The source text to be translated
  @JsonKey(name: 'source_text')
  final String sourceText;

  /// Context information about where/how this text is used
  final String? context;

  /// Additional notes or instructions for translators
  final String? notes;

  /// Whether this unit is obsolete (removed from current mod version)
  @JsonKey(name: 'is_obsolete')
  @BoolIntConverter()
  final bool isObsolete;

  /// Unix timestamp when the unit was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the unit was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const TranslationUnit({
    required this.id,
    required this.projectId,
    required this.key,
    required this.sourceText,
    this.context,
    this.notes,
    this.isObsolete = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if the unit is currently active (not obsolete)
  bool get isActive => !isObsolete;

  /// Returns true if the unit has context information
  bool get hasContext => context != null && context!.isNotEmpty;

  /// Returns true if the unit has translator notes
  bool get hasNotes => notes != null && notes!.isNotEmpty;

  /// Returns true if the unit has additional information (context or notes)
  bool get hasAdditionalInfo => hasContext || hasNotes;

  /// Returns the source text truncated to a maximum length
  String getSourceTextPreview([int maxLength = 100]) {
    if (sourceText.length <= maxLength) {
      return sourceText;
    }
    return '${sourceText.substring(0, maxLength)}...';
  }

  /// Returns a combined string of context and notes
  String? get combinedInfo {
    final parts = <String>[];
    if (hasContext) parts.add('Context: $context');
    if (hasNotes) parts.add('Notes: $notes');
    return parts.isEmpty ? null : parts.join('\n');
  }

  TranslationUnit copyWith({
    String? id,
    String? projectId,
    String? key,
    String? sourceText,
    String? context,
    String? notes,
    bool? isObsolete,
    int? createdAt,
    int? updatedAt,
  }) {
    return TranslationUnit(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      key: key ?? this.key,
      sourceText: sourceText ?? this.sourceText,
      context: context ?? this.context,
      notes: notes ?? this.notes,
      isObsolete: isObsolete ?? this.isObsolete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TranslationUnit.fromJson(Map<String, dynamic> json) =>
      _$TranslationUnitFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationUnitToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationUnit &&
        other.id == id &&
        other.projectId == projectId &&
        other.key == key &&
        other.sourceText == sourceText &&
        other.context == context &&
        other.notes == notes &&
        other.isObsolete == isObsolete &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      projectId.hashCode ^
      key.hashCode ^
      sourceText.hashCode ^
      context.hashCode ^
      notes.hashCode ^
      isObsolete.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() => 'TranslationUnit(id: $id, key: $key, projectId: $projectId, isObsolete: $isObsolete)';
}
