import 'package:json_annotation/json_annotation.dart';

part 'batch_estimate.g.dart';

/// Performance estimation for a translation batch
@JsonSerializable()
class BatchEstimate {
  /// Batch ID being estimated
  final String batchId;

  /// Total number of units in batch
  final int totalUnits;

  /// Estimated input tokens
  final int estimatedInputTokens;

  /// Estimated output tokens
  final int estimatedOutputTokens;

  /// Total estimated tokens (input + output)
  final int totalEstimatedTokens;

  /// Provider being used for this estimate
  final String providerCode;

  /// Model being used
  final String modelName;

  /// Number of units that will use TM (exact or fuzzy matches)
  final int unitsFromTm;

  /// Number of units that will use LLM
  final int unitsRequiringLlm;

  /// TM reuse rate (0.0 - 1.0)
  final double tmReuseRate;

  /// Estimated time to complete (in seconds)
  final int estimatedDurationSeconds;

  /// Timestamp when estimate was created
  final DateTime createdAt;

  const BatchEstimate({
    required this.batchId,
    required this.totalUnits,
    required this.estimatedInputTokens,
    required this.estimatedOutputTokens,
    required this.totalEstimatedTokens,
    required this.providerCode,
    required this.modelName,
    required this.unitsFromTm,
    required this.unitsRequiringLlm,
    required this.tmReuseRate,
    required this.estimatedDurationSeconds,
    required this.createdAt,
  });

  /// Tokens per unit (average)
  double get tokensPerUnit =>
      totalUnits > 0 ? totalEstimatedTokens / totalUnits : 0.0;

  /// Estimated duration in minutes
  double get estimatedDurationMinutes => estimatedDurationSeconds / 60.0;

  // JSON serialization
  factory BatchEstimate.fromJson(Map<String, dynamic> json) =>
      _$BatchEstimateFromJson(json);

  Map<String, dynamic> toJson() => _$BatchEstimateToJson(this);

  // CopyWith method
  BatchEstimate copyWith({
    String? batchId,
    int? totalUnits,
    int? estimatedInputTokens,
    int? estimatedOutputTokens,
    int? totalEstimatedTokens,
    String? providerCode,
    String? modelName,
    int? unitsFromTm,
    int? unitsRequiringLlm,
    double? tmReuseRate,
    int? estimatedDurationSeconds,
    DateTime? createdAt,
  }) {
    return BatchEstimate(
      batchId: batchId ?? this.batchId,
      totalUnits: totalUnits ?? this.totalUnits,
      estimatedInputTokens: estimatedInputTokens ?? this.estimatedInputTokens,
      estimatedOutputTokens:
          estimatedOutputTokens ?? this.estimatedOutputTokens,
      totalEstimatedTokens: totalEstimatedTokens ?? this.totalEstimatedTokens,
      providerCode: providerCode ?? this.providerCode,
      modelName: modelName ?? this.modelName,
      unitsFromTm: unitsFromTm ?? this.unitsFromTm,
      unitsRequiringLlm: unitsRequiringLlm ?? this.unitsRequiringLlm,
      tmReuseRate: tmReuseRate ?? this.tmReuseRate,
      estimatedDurationSeconds:
          estimatedDurationSeconds ?? this.estimatedDurationSeconds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchEstimate &&
          runtimeType == other.runtimeType &&
          batchId == other.batchId &&
          totalEstimatedTokens == other.totalEstimatedTokens;

  @override
  int get hashCode =>
      batchId.hashCode ^
      totalEstimatedTokens.hashCode;

  @override
  String toString() {
    return 'BatchEstimate(batchId: $batchId, units: $totalUnits, '
        'tokens: $totalEstimatedTokens, '
        'TM reuse: ${(tmReuseRate * 100).toStringAsFixed(1)}%, '
        'duration: ${estimatedDurationMinutes.toStringAsFixed(1)} min)';
  }
}
