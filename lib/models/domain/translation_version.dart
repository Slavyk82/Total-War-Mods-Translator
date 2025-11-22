import 'package:json_annotation/json_annotation.dart';
import 'language.dart' show BoolIntConverter;

part 'translation_version.g.dart';

/// Translation version status enumeration
enum TranslationVersionStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('translating')
  translating,
  @JsonValue('translated')
  translated,
  @JsonValue('reviewed')
  reviewed,
  @JsonValue('approved')
  approved,
  @JsonValue('needs_review')
  needsReview,
}

/// Represents a translation of a unit in a specific language.
///
/// Each translation unit can have multiple versions (one per target language).
/// This model tracks the translated text, quality metrics, and review status.
@JsonSerializable()
class TranslationVersion {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the translation unit being translated
  @JsonKey(name: 'unit_id')
  final String unitId;

  /// ID of the project language this translation belongs to
  @JsonKey(name: 'project_language_id')
  final String projectLanguageId;

  /// The translated text (null if not yet translated)
  @JsonKey(name: 'translated_text')
  final String? translatedText;

  /// Whether the translation was manually edited by a user
  @JsonKey(name: 'is_manually_edited')
  @BoolIntConverter()
  final bool isManuallyEdited;

  /// Current status of the translation
  final TranslationVersionStatus status;

  /// Confidence score from the translation provider (0.0 to 1.0)
  @JsonKey(name: 'confidence_score')
  final double? confidenceScore;

  /// JSON string containing validation issues (if any)
  @JsonKey(name: 'validation_issues')
  final String? validationIssues;

  /// Unix timestamp when the version was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the version was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const TranslationVersion({
    required this.id,
    required this.unitId,
    required this.projectLanguageId,
    this.translatedText,
    this.isManuallyEdited = false,
    this.status = TranslationVersionStatus.pending,
    this.confidenceScore,
    this.validationIssues,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if translation is pending
  bool get isPending => status == TranslationVersionStatus.pending;

  /// Returns true if translation is in progress
  bool get isTranslating => status == TranslationVersionStatus.translating;

  /// Returns true if translation is completed
  bool get isTranslated => status == TranslationVersionStatus.translated;

  /// Returns true if translation has been reviewed
  bool get isReviewed => status == TranslationVersionStatus.reviewed;

  /// Returns true if translation has been approved
  bool get isApproved => status == TranslationVersionStatus.approved;

  /// Returns true if translation needs review
  bool get needsReview => status == TranslationVersionStatus.needsReview;

  /// Returns true if the translation has been completed (any finished state)
  bool get isComplete =>
      status == TranslationVersionStatus.translated ||
      status == TranslationVersionStatus.reviewed ||
      status == TranslationVersionStatus.approved;

  /// Returns true if the translation has validation issues
  bool get hasValidationIssues =>
      validationIssues != null && validationIssues!.isNotEmpty;

  /// Returns true if the translation has a confidence score
  bool get hasConfidenceScore => confidenceScore != null;

  /// Returns true if the confidence score is low (below 0.8)
  bool get hasLowConfidence =>
      confidenceScore != null && confidenceScore! < 0.8;

  /// Returns true if the translation quality seems questionable
  bool get hasQualityIssues => hasValidationIssues || hasLowConfidence;

  /// Returns true if the translation is ready for use
  bool get isReadyForUse =>
      isComplete && !hasQualityIssues && translatedText != null;

  /// Returns the confidence score as a percentage (0-100)
  int? get confidencePercentage =>
      confidenceScore != null ? (confidenceScore! * 100).round() : null;

  /// Returns the translated text or a placeholder
  String get displayText => translatedText ?? '(Not translated)';

  /// Returns a status display string
  String get statusDisplay {
    switch (status) {
      case TranslationVersionStatus.pending:
        return 'Pending';
      case TranslationVersionStatus.translating:
        return 'Translating';
      case TranslationVersionStatus.translated:
        return 'Translated';
      case TranslationVersionStatus.reviewed:
        return 'Reviewed';
      case TranslationVersionStatus.approved:
        return 'Approved';
      case TranslationVersionStatus.needsReview:
        return 'Needs Review';
    }
  }

  TranslationVersion copyWith({
    String? id,
    String? unitId,
    String? projectLanguageId,
    String? translatedText,
    bool? isManuallyEdited,
    TranslationVersionStatus? status,
    double? confidenceScore,
    String? validationIssues,
    int? createdAt,
    int? updatedAt,
  }) {
    return TranslationVersion(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      projectLanguageId: projectLanguageId ?? this.projectLanguageId,
      translatedText: translatedText ?? this.translatedText,
      isManuallyEdited: isManuallyEdited ?? this.isManuallyEdited,
      status: status ?? this.status,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      validationIssues: validationIssues ?? this.validationIssues,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TranslationVersion.fromJson(Map<String, dynamic> json) =>
      _$TranslationVersionFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationVersionToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationVersion &&
        other.id == id &&
        other.unitId == unitId &&
        other.projectLanguageId == projectLanguageId &&
        other.translatedText == translatedText &&
        other.isManuallyEdited == isManuallyEdited &&
        other.status == status &&
        other.confidenceScore == confidenceScore &&
        other.validationIssues == validationIssues &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      unitId.hashCode ^
      projectLanguageId.hashCode ^
      translatedText.hashCode ^
      isManuallyEdited.hashCode ^
      status.hashCode ^
      confidenceScore.hashCode ^
      validationIssues.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() => 'TranslationVersion(id: $id, unitId: $unitId, status: $status, isManuallyEdited: $isManuallyEdited)';
}
