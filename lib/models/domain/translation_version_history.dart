import 'package:json_annotation/json_annotation.dart';
import 'translation_version.dart';

part 'translation_version_history.g.dart';

/// Represents a historical record of changes to a translation version.
///
/// Translation version history tracks all changes made to a translation over time,
/// including who made the change, what was changed, and why. This provides an
/// audit trail and allows reverting to previous translations if needed.
@JsonSerializable()
class TranslationVersionHistory {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the translation version this history entry belongs to
  @JsonKey(name: 'version_id')
  final String versionId;

  /// The translated text at this point in history
  @JsonKey(name: 'translated_text')
  final String translatedText;

  /// The status at this point in history
  final TranslationVersionStatus status;

  /// The confidence score at this point in history
  @JsonKey(name: 'confidence_score')
  final double? confidenceScore;

  /// Who made this change (user ID, provider code, or 'system')
  @JsonKey(name: 'changed_by')
  final String changedBy;

  /// Reason for the change (e.g., 'manual_edit', 'quality_improvement', 'correction')
  @JsonKey(name: 'change_reason')
  final String? changeReason;

  /// Unix timestamp when this change was made
  @JsonKey(name: 'created_at')
  final int createdAt;

  const TranslationVersionHistory({
    required this.id,
    required this.versionId,
    required this.translatedText,
    required this.status,
    this.confidenceScore,
    required this.changedBy,
    this.changeReason,
    required this.createdAt,
  });

  /// Returns true if the change was made by a user
  bool get isUserChange =>
      !changedBy.startsWith('provider_') && changedBy != 'system';

  /// Returns true if the change was made by a translation provider
  bool get isProviderChange => changedBy.startsWith('provider_');

  /// Returns true if the change was made by the system
  bool get isSystemChange => changedBy == 'system';

  /// Returns true if a change reason was provided
  bool get hasChangeReason =>
      changeReason != null && changeReason!.isNotEmpty;

  /// Returns true if there's a confidence score
  bool get hasConfidenceScore => confidenceScore != null;

  /// Returns the confidence score as a percentage (0-100)
  int? get confidencePercentage =>
      confidenceScore != null ? (confidenceScore! * 100).round() : null;

  /// Returns a display string for who made the change
  String get changedByDisplay {
    if (isSystemChange) return 'System';
    if (isProviderChange) {
      // Remove 'provider_' prefix and format nicely
      final providerName = changedBy.replaceFirst('provider_', '');
      return providerName
          .split('_')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');
    }
    return 'User';
  }

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

  /// Returns a preview of the translated text
  String getTranslatedTextPreview([int maxLength = 50]) {
    if (translatedText.length <= maxLength) {
      return translatedText;
    }
    return '${translatedText.substring(0, maxLength)}...';
  }

  /// Returns the created date as DateTime
  DateTime get createdAtAsDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);

  TranslationVersionHistory copyWith({
    String? id,
    String? versionId,
    String? translatedText,
    TranslationVersionStatus? status,
    double? confidenceScore,
    String? changedBy,
    String? changeReason,
    int? createdAt,
  }) {
    return TranslationVersionHistory(
      id: id ?? this.id,
      versionId: versionId ?? this.versionId,
      translatedText: translatedText ?? this.translatedText,
      status: status ?? this.status,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      changedBy: changedBy ?? this.changedBy,
      changeReason: changeReason ?? this.changeReason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory TranslationVersionHistory.fromJson(Map<String, dynamic> json) =>
      _$TranslationVersionHistoryFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationVersionHistoryToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationVersionHistory &&
        other.id == id &&
        other.versionId == versionId &&
        other.translatedText == translatedText &&
        other.status == status &&
        other.confidenceScore == confidenceScore &&
        other.changedBy == changedBy &&
        other.changeReason == changeReason &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      versionId.hashCode ^
      translatedText.hashCode ^
      status.hashCode ^
      confidenceScore.hashCode ^
      changedBy.hashCode ^
      changeReason.hashCode ^
      createdAt.hashCode;

  @override
  String toString() => 'TranslationVersionHistory(id: $id, versionId: $versionId, status: $status, changedBy: $changedByDisplay)';
}
