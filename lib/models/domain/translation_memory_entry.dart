import 'package:json_annotation/json_annotation.dart';

part 'translation_memory_entry.g.dart';

/// Represents an entry in the translation memory system.
///
/// Translation memory stores previously translated text for reuse across
/// projects and languages. This improves consistency and performance by
/// reusing high-quality translations.
@JsonSerializable()
class TranslationMemoryEntry {
  /// Unique identifier (UUID)
  final String id;

  /// The source text that was translated
  @JsonKey(name: 'source_text')
  final String sourceText;

  /// Hash of the source text for fast lookup
  @JsonKey(name: 'source_hash')
  final String sourceHash;

  /// ID of the target language
  @JsonKey(name: 'target_language_id')
  final String targetLanguageId;

  /// The translated text
  @JsonKey(name: 'translated_text')
  final String translatedText;

  /// Game/mod context where this translation was used
  @JsonKey(name: 'game_context')
  final String? gameContext;

  /// ID of the translation provider that created this translation
  @JsonKey(name: 'translation_provider_id')
  final String? translationProviderId;

  /// Quality score of the translation (0.0 to 1.0)
  @JsonKey(name: 'quality_score')
  final double? qualityScore;

  /// Number of times this translation has been used
  @JsonKey(name: 'usage_count')
  final int usageCount;

  /// Unix timestamp when the entry was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the entry was last used
  @JsonKey(name: 'last_used_at')
  final int lastUsedAt;

  /// Unix timestamp when the entry was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const TranslationMemoryEntry({
    required this.id,
    required this.sourceText,
    required this.sourceHash,
    required this.targetLanguageId,
    required this.translatedText,
    this.gameContext,
    this.translationProviderId,
    this.qualityScore,
    this.usageCount = 1,
    required this.createdAt,
    required this.lastUsedAt,
    required this.updatedAt,
  });

  /// Returns true if the entry has a quality score
  bool get hasQualityScore => qualityScore != null;

  /// Returns true if the quality score is high (>= 0.8)
  bool get hasHighQuality =>
      qualityScore != null && qualityScore! >= 0.8;

  /// Returns true if the entry has been used multiple times
  bool get isFrequentlyUsed => usageCount > 5;

  /// Returns true if the entry is from a specific game context
  bool get hasGameContext => gameContext != null && gameContext!.isNotEmpty;

  /// Returns true if the entry has a translation provider
  bool get hasProvider =>
      translationProviderId != null && translationProviderId!.isNotEmpty;

  /// Returns the quality score as a percentage (0-100)
  int? get qualityPercentage =>
      qualityScore != null ? (qualityScore! * 100).round() : null;

  /// Returns the days since last use
  int get daysSinceLastUse {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (now - lastUsedAt) ~/ 86400;
  }

  /// Returns true if the entry was used recently (within 30 days)
  bool get isRecentlyUsed => daysSinceLastUse <= 30;

  /// Returns true if the entry is stale (not used in 180 days)
  bool get isStale => daysSinceLastUse > 180;

  /// Returns a preview of the source text
  String getSourceTextPreview([int maxLength = 50]) {
    if (sourceText.length <= maxLength) {
      return sourceText;
    }
    return '${sourceText.substring(0, maxLength)}...';
  }

  /// Returns a preview of the translated text
  String getTranslatedTextPreview([int maxLength = 50]) {
    if (translatedText.length <= maxLength) {
      return translatedText;
    }
    return '${translatedText.substring(0, maxLength)}...';
  }

  /// Returns a display string for usage statistics
  String get usageDisplay {
    if (usageCount == 1) {
      return 'Used once';
    }
    return 'Used $usageCount times';
  }

  TranslationMemoryEntry copyWith({
    String? id,
    String? sourceText,
    String? sourceHash,
    String? targetLanguageId,
    String? translatedText,
    String? gameContext,
    String? translationProviderId,
    double? qualityScore,
    int? usageCount,
    int? createdAt,
    int? lastUsedAt,
    int? updatedAt,
  }) {
    return TranslationMemoryEntry(
      id: id ?? this.id,
      sourceText: sourceText ?? this.sourceText,
      sourceHash: sourceHash ?? this.sourceHash,
      targetLanguageId: targetLanguageId ?? this.targetLanguageId,
      translatedText: translatedText ?? this.translatedText,
      gameContext: gameContext ?? this.gameContext,
      translationProviderId: translationProviderId ?? this.translationProviderId,
      qualityScore: qualityScore ?? this.qualityScore,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TranslationMemoryEntry.fromJson(Map<String, dynamic> json) =>
      _$TranslationMemoryEntryFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationMemoryEntryToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationMemoryEntry &&
        other.id == id &&
        other.sourceText == sourceText &&
        other.sourceHash == sourceHash &&
        other.targetLanguageId == targetLanguageId &&
        other.translatedText == translatedText &&
        other.gameContext == gameContext &&
        other.translationProviderId == translationProviderId &&
        other.qualityScore == qualityScore &&
        other.usageCount == usageCount &&
        other.createdAt == createdAt &&
        other.lastUsedAt == lastUsedAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      sourceText.hashCode ^
      sourceHash.hashCode ^
      targetLanguageId.hashCode ^
      translatedText.hashCode ^
      gameContext.hashCode ^
      translationProviderId.hashCode ^
      qualityScore.hashCode ^
      usageCount.hashCode ^
      createdAt.hashCode ^
      lastUsedAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() => 'TranslationMemoryEntry(id: $id, sourceHash: $sourceHash, usageCount: $usageCount)';
}
