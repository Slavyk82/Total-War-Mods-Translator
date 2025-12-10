import 'domain_event.dart';

/// Event emitted when a new translation is added
class TranslationAddedEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final String projectLanguageId;
  final String translatedText;
  final String? providerId;

  TranslationAddedEvent({
    required this.versionId,
    required this.unitId,
    required this.projectLanguageId,
    required this.translatedText,
    this.providerId,
  }) : super.now();

  bool get isProviderGenerated => providerId != null;
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationAddedEvent(versionId: $versionId, provider: $providerId)';
}

/// Event emitted when a translation is manually edited
class TranslationEditedEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final String oldTranslation;
  final String newTranslation;
  final String editedBy;
  final String? reason;

  TranslationEditedEvent({
    required this.versionId,
    required this.unitId,
    required this.oldTranslation,
    required this.newTranslation,
    required this.editedBy,
    this.reason,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationEditedEvent(versionId: $versionId, by: $editedBy, '
      'reason: ${reason ?? "N/A"})';
}

/// Event emitted when a translation is validated/approved
class TranslationValidatedEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final String status; // 'translated' or 'needs_review'
  final String validatedBy;
  final List<String>? validationIssues;

  TranslationValidatedEvent({
    required this.versionId,
    required this.unitId,
    required this.status,
    required this.validatedBy,
    this.validationIssues,
  }) : super.now();

  bool get isTranslated => status == 'translated';
  bool get hasIssues => validationIssues != null && validationIssues!.isNotEmpty;
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationValidatedEvent(versionId: $versionId, status: $status, '
      'by: $validatedBy, issues: ${validationIssues?.length ?? 0})';
}

/// Event emitted when a translation is deleted
class TranslationDeletedEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final String projectLanguageId;
  final String deletedBy;
  final String reason;

  TranslationDeletedEvent({
    required this.versionId,
    required this.unitId,
    required this.projectLanguageId,
    required this.deletedBy,
    required this.reason,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationDeletedEvent(versionId: $versionId, by: $deletedBy, '
      'reason: $reason)';
}

/// Event emitted when translation status changes
class TranslationStatusChangedEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final String oldStatus;
  final String newStatus;
  final String? changedBy;

  TranslationStatusChangedEvent({
    required this.versionId,
    required this.unitId,
    required this.oldStatus,
    required this.newStatus,
    this.changedBy,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationStatusChangedEvent(versionId: $versionId, '
      '$oldStatus -> $newStatus, by: ${changedBy ?? "system"})';
}

/// Event emitted when translation quality issues are detected
class TranslationQualityIssueDetectedEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final List<String> issues;
  final bool requiresReview;

  TranslationQualityIssueDetectedEvent({
    required this.versionId,
    required this.unitId,
    required this.issues,
    required this.requiresReview,
  }) : super.now();

  int get issueCount => issues.length;
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationQualityIssueDetectedEvent(versionId: $versionId, '
      'issues: $issueCount, requiresReview: $requiresReview)';
}
