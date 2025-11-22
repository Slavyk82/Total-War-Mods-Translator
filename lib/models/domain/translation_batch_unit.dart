import 'package:json_annotation/json_annotation.dart';

part 'translation_batch_unit.g.dart';

/// Translation batch unit status enumeration
enum TranslationBatchUnitStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('processing')
  processing,
  @JsonValue('completed')
  completed,
  @JsonValue('failed')
  failed,
}

/// Represents a single translation unit within a translation batch.
///
/// Translation batch units link translation units to batches and track
/// the processing status of each unit within its batch.
@JsonSerializable()
class TranslationBatchUnit {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the parent batch
  @JsonKey(name: 'batch_id')
  final String batchId;

  /// ID of the translation unit being processed
  @JsonKey(name: 'unit_id')
  final String unitId;

  /// Order in which this unit should be processed within the batch
  @JsonKey(name: 'processing_order')
  final int processingOrder;

  /// Current status of this unit's processing
  final TranslationBatchUnitStatus status;

  /// Error message if processing failed
  @JsonKey(name: 'error_message')
  final String? errorMessage;

  /// Unix timestamp when processing started
  @JsonKey(name: 'started_at')
  final int? startedAt;

  /// Unix timestamp when processing completed
  @JsonKey(name: 'completed_at')
  final int? completedAt;

  const TranslationBatchUnit({
    required this.id,
    required this.batchId,
    required this.unitId,
    required this.processingOrder,
    this.status = TranslationBatchUnitStatus.pending,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  /// Returns true if the unit is pending processing
  bool get isPending => status == TranslationBatchUnitStatus.pending;

  /// Returns true if the unit is currently being processed
  bool get isProcessing => status == TranslationBatchUnitStatus.processing;

  /// Returns true if the unit has been completed
  bool get isCompleted => status == TranslationBatchUnitStatus.completed;

  /// Returns true if processing failed
  bool get isFailed => status == TranslationBatchUnitStatus.failed;

  /// Returns true if the unit is in a finished state
  bool get isFinished =>
      status == TranslationBatchUnitStatus.completed ||
      status == TranslationBatchUnitStatus.failed;

  /// Returns true if the unit is active (pending or processing)
  bool get isActive =>
      status == TranslationBatchUnitStatus.pending ||
      status == TranslationBatchUnitStatus.processing;

  /// Returns true if there's an error message
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  /// Returns true if processing has started
  bool get hasStarted => startedAt != null;

  /// Returns true if processing has completed (success or failure)
  bool get hasCompleted => completedAt != null;

  /// Returns the processing duration in seconds (if started and completed)
  int? get processingDuration {
    if (startedAt == null || completedAt == null) return null;
    return completedAt! - startedAt!;
  }

  /// Returns the processing duration in seconds (ongoing if not completed)
  int? get currentProcessingDuration {
    if (startedAt == null) return null;
    final endTime = completedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return endTime - startedAt!;
  }

  /// Returns a status display string
  String get statusDisplay {
    switch (status) {
      case TranslationBatchUnitStatus.pending:
        return 'Pending';
      case TranslationBatchUnitStatus.processing:
        return 'Processing';
      case TranslationBatchUnitStatus.completed:
        return 'Completed';
      case TranslationBatchUnitStatus.failed:
        return 'Failed';
    }
  }

  /// Returns a status indicator with emoji or symbol
  String get statusIndicator {
    switch (status) {
      case TranslationBatchUnitStatus.pending:
        return '⏳';
      case TranslationBatchUnitStatus.processing:
        return '⚙️';
      case TranslationBatchUnitStatus.completed:
        return '✓';
      case TranslationBatchUnitStatus.failed:
        return '✗';
    }
  }

  TranslationBatchUnit copyWith({
    String? id,
    String? batchId,
    String? unitId,
    int? processingOrder,
    TranslationBatchUnitStatus? status,
    String? errorMessage,
    int? startedAt,
    int? completedAt,
  }) {
    return TranslationBatchUnit(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      unitId: unitId ?? this.unitId,
      processingOrder: processingOrder ?? this.processingOrder,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  factory TranslationBatchUnit.fromJson(Map<String, dynamic> json) =>
      _$TranslationBatchUnitFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationBatchUnitToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationBatchUnit &&
        other.id == id &&
        other.batchId == batchId &&
        other.unitId == unitId &&
        other.processingOrder == processingOrder &&
        other.status == status &&
        other.errorMessage == errorMessage &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      batchId.hashCode ^
      unitId.hashCode ^
      processingOrder.hashCode ^
      status.hashCode ^
      errorMessage.hashCode ^
      startedAt.hashCode ^
      completedAt.hashCode;

  @override
  String toString() => 'TranslationBatchUnit(id: $id, batchId: $batchId, unitId: $unitId, status: $status, order: $processingOrder)';
}
