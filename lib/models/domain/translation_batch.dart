import 'package:json_annotation/json_annotation.dart';

part 'translation_batch.g.dart';

/// Translation batch status enumeration
enum TranslationBatchStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('processing')
  processing,
  @JsonValue('completed')
  completed,
  @JsonValue('failed')
  failed,
  @JsonValue('cancelled')
  cancelled,
}

/// Represents a batch of translation units being processed together.
///
/// Translation batches group multiple units for efficient processing by
/// a translation provider. This model tracks the progress and status of
/// batch translation operations.
@JsonSerializable()
class TranslationBatch {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the project language this batch belongs to
  @JsonKey(name: 'project_language_id')
  final String projectLanguageId;

  /// Current status of the batch
  final TranslationBatchStatus status;

  /// ID of the translation provider processing this batch
  @JsonKey(name: 'provider_id')
  final String providerId;

  /// Sequential batch number within the project language
  @JsonKey(name: 'batch_number')
  final int batchNumber;

  /// Total number of units in this batch
  @JsonKey(name: 'units_count')
  final int unitsCount;

  /// Number of units completed in this batch
  @JsonKey(name: 'units_completed')
  final int unitsCompleted;

  /// Unix timestamp when the batch started processing
  @JsonKey(name: 'started_at')
  final int? startedAt;

  /// Unix timestamp when the batch completed
  @JsonKey(name: 'completed_at')
  final int? completedAt;

  /// Error message if the batch failed
  @JsonKey(name: 'error_message')
  final String? errorMessage;

  /// Number of times this batch has been retried
  @JsonKey(name: 'retry_count')
  final int retryCount;

  const TranslationBatch({
    required this.id,
    required this.projectLanguageId,
    this.status = TranslationBatchStatus.pending,
    required this.providerId,
    required this.batchNumber,
    this.unitsCount = 0,
    this.unitsCompleted = 0,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.retryCount = 0,
  });

  /// Returns true if the batch is pending
  bool get isPending => status == TranslationBatchStatus.pending;

  /// Returns true if the batch is currently processing
  bool get isProcessing => status == TranslationBatchStatus.processing;

  /// Returns true if the batch is completed
  bool get isCompleted => status == TranslationBatchStatus.completed;

  /// Returns true if the batch failed
  bool get isFailed => status == TranslationBatchStatus.failed;

  /// Returns true if the batch was cancelled
  bool get isCancelled => status == TranslationBatchStatus.cancelled;

  /// Returns true if the batch is in a finished state
  bool get isFinished =>
      status == TranslationBatchStatus.completed ||
      status == TranslationBatchStatus.failed ||
      status == TranslationBatchStatus.cancelled;

  /// Returns true if the batch is active (pending or processing)
  bool get isActive =>
      status == TranslationBatchStatus.pending ||
      status == TranslationBatchStatus.processing;

  /// Returns true if the batch has an error message
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  /// Returns true if the batch has been retried
  bool get hasBeenRetried => retryCount > 0;

  /// Returns true if the batch has started processing
  bool get hasStarted => startedAt != null;

  /// Returns the progress percentage (0-100)
  double get progressPercent {
    if (unitsCount == 0) return 0.0;
    return (unitsCompleted / unitsCount) * 100.0;
  }

  /// Returns the progress as an integer percentage
  int get progressPercentInt => progressPercent.round();

  /// Returns the number of remaining units
  int get remainingUnits => unitsCount - unitsCompleted;

  /// Returns true if all units are completed
  bool get allUnitsCompleted => unitsCompleted >= unitsCount && unitsCount > 0;

  /// Returns the processing duration in seconds (if started)
  int? get processingDuration {
    if (startedAt == null) return null;
    final endTime = completedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return endTime - startedAt!;
  }

  /// Returns a status display string
  String get statusDisplay {
    switch (status) {
      case TranslationBatchStatus.pending:
        return 'Pending';
      case TranslationBatchStatus.processing:
        return 'Processing';
      case TranslationBatchStatus.completed:
        return 'Completed';
      case TranslationBatchStatus.failed:
        return 'Failed';
      case TranslationBatchStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// Returns a formatted progress string (e.g., "15/30 (50%)")
  String get progressDisplay =>
      '$unitsCompleted/$unitsCount ($progressPercentInt%)';

  TranslationBatch copyWith({
    String? id,
    String? projectLanguageId,
    TranslationBatchStatus? status,
    String? providerId,
    int? batchNumber,
    int? unitsCount,
    int? unitsCompleted,
    int? startedAt,
    int? completedAt,
    String? errorMessage,
    int? retryCount,
  }) {
    return TranslationBatch(
      id: id ?? this.id,
      projectLanguageId: projectLanguageId ?? this.projectLanguageId,
      status: status ?? this.status,
      providerId: providerId ?? this.providerId,
      batchNumber: batchNumber ?? this.batchNumber,
      unitsCount: unitsCount ?? this.unitsCount,
      unitsCompleted: unitsCompleted ?? this.unitsCompleted,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  factory TranslationBatch.fromJson(Map<String, dynamic> json) =>
      _$TranslationBatchFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationBatchToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationBatch &&
        other.id == id &&
        other.projectLanguageId == projectLanguageId &&
        other.status == status &&
        other.providerId == providerId &&
        other.batchNumber == batchNumber &&
        other.unitsCount == unitsCount &&
        other.unitsCompleted == unitsCompleted &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt &&
        other.errorMessage == errorMessage &&
        other.retryCount == retryCount;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      projectLanguageId.hashCode ^
      status.hashCode ^
      providerId.hashCode ^
      batchNumber.hashCode ^
      unitsCount.hashCode ^
      unitsCompleted.hashCode ^
      startedAt.hashCode ^
      completedAt.hashCode ^
      errorMessage.hashCode ^
      retryCount.hashCode;

  @override
  String toString() => 'TranslationBatch(id: $id, batchNumber: $batchNumber, status: $status, progress: $progressDisplay)';
}
