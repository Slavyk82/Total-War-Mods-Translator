import 'package:json_annotation/json_annotation.dart';

part 'translation_progress.g.dart';

/// Progress information for translation batch execution
/// Emitted as stream events during translation
@JsonSerializable()
class TranslationProgress {
  /// Batch ID being processed
  final String batchId;

  /// Current status
  final TranslationProgressStatus status;

  /// Total number of units in batch
  final int totalUnits;

  /// Number of units processed so far
  final int processedUnits;

  /// Number of units successfully translated
  final int successfulUnits;

  /// Number of units that failed
  final int failedUnits;

  /// Number of units skipped (already translated, TM matches, etc.)
  final int skippedUnits;

  /// Current phase of translation
  final TranslationPhase currentPhase;

  /// Estimated time remaining in seconds
  final int? estimatedSecondsRemaining;

  /// Tokens used so far
  final int tokensUsed;

  /// Translation Memory reuse rate (0.0 - 1.0)
  final double tmReuseRate;

  /// Error message if status is error
  final String? errorMessage;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  /// Timestamp of this progress update
  final DateTime timestamp;

  const TranslationProgress({
    required this.batchId,
    required this.status,
    required this.totalUnits,
    required this.processedUnits,
    required this.successfulUnits,
    required this.failedUnits,
    required this.skippedUnits,
    required this.currentPhase,
    this.estimatedSecondsRemaining,
    required this.tokensUsed,
    required this.tmReuseRate,
    this.errorMessage,
    this.metadata,
    required this.timestamp,
  });

  /// Progress percentage (0.0 - 1.0)
  double get progressPercentage =>
      totalUnits > 0 ? processedUnits / totalUnits : 0.0;

  /// Is translation completed (successfully or with errors)
  bool get isCompleted =>
      status == TranslationProgressStatus.completed ||
      status == TranslationProgressStatus.failed;

  /// Is translation in progress
  bool get isInProgress =>
      status == TranslationProgressStatus.inProgress ||
      status == TranslationProgressStatus.paused;

  // JSON serialization
  factory TranslationProgress.fromJson(Map<String, dynamic> json) =>
      _$TranslationProgressFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationProgressToJson(this);

  // CopyWith method
  TranslationProgress copyWith({
    String? batchId,
    TranslationProgressStatus? status,
    int? totalUnits,
    int? processedUnits,
    int? successfulUnits,
    int? failedUnits,
    int? skippedUnits,
    TranslationPhase? currentPhase,
    int? estimatedSecondsRemaining,
    int? tokensUsed,
    double? tmReuseRate,
    String? errorMessage,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) {
    return TranslationProgress(
      batchId: batchId ?? this.batchId,
      status: status ?? this.status,
      totalUnits: totalUnits ?? this.totalUnits,
      processedUnits: processedUnits ?? this.processedUnits,
      successfulUnits: successfulUnits ?? this.successfulUnits,
      failedUnits: failedUnits ?? this.failedUnits,
      skippedUnits: skippedUnits ?? this.skippedUnits,
      currentPhase: currentPhase ?? this.currentPhase,
      estimatedSecondsRemaining:
          estimatedSecondsRemaining ?? this.estimatedSecondsRemaining,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      tmReuseRate: tmReuseRate ?? this.tmReuseRate,
      errorMessage: errorMessage ?? this.errorMessage,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationProgress &&
          runtimeType == other.runtimeType &&
          batchId == other.batchId &&
          status == other.status &&
          processedUnits == other.processedUnits;

  @override
  int get hashCode =>
      batchId.hashCode ^ status.hashCode ^ processedUnits.hashCode;

  @override
  String toString() {
    return 'TranslationProgress(batchId: $batchId, status: $status, '
        'progress: ${(progressPercentage * 100).toStringAsFixed(1)}%, '
        'phase: $currentPhase, tokens: $tokensUsed)';
  }
}

/// Status of translation batch
enum TranslationProgressStatus {
  /// Batch is queued and waiting to start
  @JsonValue('queued')
  queued,

  /// Batch is currently being processed
  @JsonValue('in_progress')
  inProgress,

  /// Batch is paused by user
  @JsonValue('paused')
  paused,

  /// Batch completed successfully
  @JsonValue('completed')
  completed,

  /// Batch failed with error
  @JsonValue('failed')
  failed,

  /// Batch was cancelled by user
  @JsonValue('cancelled')
  cancelled,
}

/// Current phase of translation workflow
enum TranslationPhase {
  /// Initializing batch
  @JsonValue('initializing')
  initializing,

  /// Checking Translation Memory for exact matches
  @JsonValue('tm_exact_lookup')
  tmExactLookup,

  /// Checking Translation Memory for fuzzy matches
  @JsonValue('tm_fuzzy_lookup')
  tmFuzzyLookup,

  /// Building prompt with context
  @JsonValue('building_prompt')
  buildingPrompt,

  /// Calling LLM service
  @JsonValue('llm_translation')
  llmTranslation,

  /// Validating LLM response
  @JsonValue('validating')
  validating,

  /// Saving translations to database
  @JsonValue('saving')
  saving,

  /// Updating Translation Memory
  @JsonValue('updating_tm')
  updatingTm,

  /// Finalizing batch
  @JsonValue('finalizing')
  finalizing,

  /// Completed
  @JsonValue('completed')
  completed,
}
