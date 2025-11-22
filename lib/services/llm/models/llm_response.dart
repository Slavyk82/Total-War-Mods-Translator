import 'package:json_annotation/json_annotation.dart';

part 'llm_response.g.dart';

/// Response from LLM translation
@JsonSerializable()
class LlmResponse {
  /// Request ID that this response corresponds to
  final String requestId;

  /// Translated texts (key-value pairs)
  final Map<String, String> translations;

  /// Provider that generated this response
  final String providerCode;

  /// Model used for translation
  final String modelName;

  /// Input tokens used
  final int inputTokens;

  /// Output tokens generated
  final int outputTokens;

  /// Total tokens (input + output)
  final int totalTokens;

  /// Processing time in milliseconds
  final int processingTimeMs;

  /// Response timestamp
  final DateTime timestamp;

  /// Finish reason (completed, length, error, etc.)
  final String? finishReason;

  /// Any warnings from the provider
  final List<String>? warnings;

  const LlmResponse({
    required this.requestId,
    required this.translations,
    required this.providerCode,
    required this.modelName,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.processingTimeMs,
    required this.timestamp,
    this.finishReason,
    this.warnings,
  });

  factory LlmResponse.fromJson(Map<String, dynamic> json) =>
      _$LlmResponseFromJson(json);

  Map<String, dynamic> toJson() => _$LlmResponseToJson(this);

  LlmResponse copyWith({
    String? requestId,
    Map<String, String>? translations,
    String? providerCode,
    String? modelName,
    int? inputTokens,
    int? outputTokens,
    int? totalTokens,
    int? processingTimeMs,
    DateTime? timestamp,
    String? finishReason,
    List<String>? warnings,
  }) {
    return LlmResponse(
      requestId: requestId ?? this.requestId,
      translations: translations ?? this.translations,
      providerCode: providerCode ?? this.providerCode,
      modelName: modelName ?? this.modelName,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      timestamp: timestamp ?? this.timestamp,
      finishReason: finishReason ?? this.finishReason,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmResponse &&
          runtimeType == other.runtimeType &&
          requestId == other.requestId &&
          translations == other.translations &&
          providerCode == other.providerCode &&
          modelName == other.modelName &&
          inputTokens == other.inputTokens &&
          outputTokens == other.outputTokens &&
          totalTokens == other.totalTokens &&
          processingTimeMs == other.processingTimeMs &&
          timestamp == other.timestamp &&
          finishReason == other.finishReason &&
          warnings == other.warnings;

  @override
  int get hashCode =>
      requestId.hashCode ^
      translations.hashCode ^
      providerCode.hashCode ^
      modelName.hashCode ^
      inputTokens.hashCode ^
      outputTokens.hashCode ^
      totalTokens.hashCode ^
      processingTimeMs.hashCode ^
      timestamp.hashCode ^
      (finishReason?.hashCode ?? 0) ^
      (warnings?.hashCode ?? 0);

  @override
  String toString() {
    return 'LlmResponse(requestId: $requestId, provider: $providerCode, '
        'model: $modelName, translations: ${translations.length} items, '
        'tokens: $totalTokens, time: ${processingTimeMs}ms)';
  }
}

/// Result from batch translation
@JsonSerializable()
class BatchTranslationResult {
  /// Batch identifier
  final String batchId;

  /// Total units in batch
  final int totalUnits;

  /// Successfully translated units
  final int successfulUnits;

  /// Failed units
  final int failedUnits;

  /// LLM responses for each successful translation
  final List<LlmResponse> responses;

  /// Errors for failed translations
  final Map<String, String> errors;

  /// Total tokens used across all requests
  final int totalTokens;

  /// Total processing time in milliseconds
  final int totalProcessingTimeMs;

  /// Batch start time
  final DateTime startTime;

  /// Batch end time
  final DateTime endTime;

  const BatchTranslationResult({
    required this.batchId,
    required this.totalUnits,
    required this.successfulUnits,
    required this.failedUnits,
    required this.responses,
    required this.errors,
    required this.totalTokens,
    required this.totalProcessingTimeMs,
    required this.startTime,
    required this.endTime,
  });

  factory BatchTranslationResult.fromJson(Map<String, dynamic> json) =>
      _$BatchTranslationResultFromJson(json);

  Map<String, dynamic> toJson() => _$BatchTranslationResultToJson(this);

  /// Calculate success rate (0.0-1.0)
  double get successRate =>
      totalUnits > 0 ? successfulUnits / totalUnits : 0.0;

  /// Duration of batch processing
  Duration get duration => endTime.difference(startTime);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchTranslationResult &&
          runtimeType == other.runtimeType &&
          batchId == other.batchId &&
          totalUnits == other.totalUnits &&
          successfulUnits == other.successfulUnits &&
          failedUnits == other.failedUnits &&
          responses == other.responses &&
          errors == other.errors &&
          totalTokens == other.totalTokens &&
          totalProcessingTimeMs == other.totalProcessingTimeMs &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode =>
      batchId.hashCode ^
      totalUnits.hashCode ^
      successfulUnits.hashCode ^
      failedUnits.hashCode ^
      responses.hashCode ^
      errors.hashCode ^
      totalTokens.hashCode ^
      totalProcessingTimeMs.hashCode ^
      startTime.hashCode ^
      endTime.hashCode;

  @override
  String toString() {
    return 'BatchTranslationResult(batchId: $batchId, '
        'total: $totalUnits, successful: $successfulUnits, failed: $failedUnits, '
        'successRate: ${(successRate * 100).toStringAsFixed(1)}%, '
        'tokens: $totalTokens, duration: ${duration.inSeconds}s)';
  }
}
