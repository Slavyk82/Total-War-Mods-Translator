import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'glossary_entry.g.dart';

/// Represents a glossary entry for consistent terminology translation.
///
/// Glossary entries define how specific terms should be translated.
/// This ensures consistency across translations, especially for game-specific
/// terminology like character names, place names, and technical terms.
@JsonSerializable()
class GlossaryEntry {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the parent glossary
  @JsonKey(name: 'glossary_id')
  final String glossaryId;

  /// Target language code (e.g., 'en', 'fr')
  @JsonKey(name: 'target_language_code')
  final String targetLanguageCode;

  /// The source term in the original language
  @JsonKey(name: 'source_term')
  final String sourceTerm;

  /// The target term in the translation language
  @JsonKey(name: 'target_term')
  final String targetTerm;

  /// Whether matching should be case-sensitive
  @JsonKey(name: 'case_sensitive')
  @BoolIntConverter()
  final bool caseSensitive;

  /// Optional notes providing context for the LLM during translation.
  /// Example: "Bretonnian is not gendered in English but should be 
  /// Bretonnien (m) or Bretonnienne (f) in French depending on context"
  final String? notes;

  /// Unix timestamp when the entry was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the entry was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const GlossaryEntry({
    required this.id,
    required this.glossaryId,
    required this.targetLanguageCode,
    required this.sourceTerm,
    required this.targetTerm,
    this.caseSensitive = false,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns a display string for the glossary entry
  String get displayText => '$sourceTerm → $targetTerm';

  /// Whether this entry has notes
  bool get hasNotes => notes != null && notes!.isNotEmpty;

  GlossaryEntry copyWith({
    String? id,
    String? glossaryId,
    String? targetLanguageCode,
    String? sourceTerm,
    String? targetTerm,
    bool? caseSensitive,
    String? notes,
    int? createdAt,
    int? updatedAt,
  }) {
    return GlossaryEntry(
      id: id ?? this.id,
      glossaryId: glossaryId ?? this.glossaryId,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
      sourceTerm: sourceTerm ?? this.sourceTerm,
      targetTerm: targetTerm ?? this.targetTerm,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory GlossaryEntry.fromJson(Map<String, dynamic> json) =>
      _$GlossaryEntryFromJson(json);

  Map<String, dynamic> toJson() => _$GlossaryEntryToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GlossaryEntry &&
        other.id == id &&
        other.glossaryId == glossaryId &&
        other.targetLanguageCode == targetLanguageCode &&
        other.sourceTerm == sourceTerm &&
        other.targetTerm == targetTerm &&
        other.caseSensitive == caseSensitive &&
        other.notes == notes &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        glossaryId,
        targetLanguageCode,
        sourceTerm,
        targetTerm,
        caseSensitive,
        notes,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'GlossaryEntry(id: $id, displayText: $displayText, targetLanguage: $targetLanguageCode)';
}
