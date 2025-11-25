import 'package:json_annotation/json_annotation.dart';

part 'llm_exchange_log.g.dart';

/// Log of LLM request/response exchanges
///
/// Captures details of communication with LLM providers for debugging
/// and monitoring purposes during mass translation.
@JsonSerializable()
class LlmExchangeLog {
  /// Timestamp of the exchange
  final DateTime timestamp;

  /// Provider code (anthropic, openai, deepl)
  final String providerCode;

  /// Model name used
  final String modelName;

  /// Request ID for correlation
  final String requestId;

  /// Number of units translated in this request
  final int unitsCount;

  /// Input tokens used
  final int inputTokens;

  /// Output tokens generated
  final int outputTokens;

  /// Total tokens
  final int totalTokens;

  /// Processing time in milliseconds
  final int processingTimeMs;

  /// Was the request successful
  final bool success;

  /// Error message if failed
  final String? errorMessage;

  /// Sample of first translated text (for preview)
  final String? sampleTranslation;

  const LlmExchangeLog({
    required this.timestamp,
    required this.providerCode,
    required this.modelName,
    required this.requestId,
    required this.unitsCount,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.processingTimeMs,
    required this.success,
    this.errorMessage,
    this.sampleTranslation,
  });

  factory LlmExchangeLog.fromJson(Map<String, dynamic> json) =>
      _$LlmExchangeLogFromJson(json);

  Map<String, dynamic> toJson() => _$LlmExchangeLogToJson(this);

  /// Create log from successful LLM response
  factory LlmExchangeLog.fromResponse({
    required String requestId,
    required String providerCode,
    required String modelName,
    required int unitsCount,
    required int inputTokens,
    required int outputTokens,
    required int processingTimeMs,
    String? sampleTranslation,
  }) {
    return LlmExchangeLog(
      timestamp: DateTime.now(),
      providerCode: providerCode,
      modelName: modelName,
      requestId: requestId,
      unitsCount: unitsCount,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: inputTokens + outputTokens,
      processingTimeMs: processingTimeMs,
      success: true,
      sampleTranslation: sampleTranslation,
    );
  }

  /// Create log from failed LLM request
  factory LlmExchangeLog.fromError({
    required String requestId,
    required String providerCode,
    required String modelName,
    required int unitsCount,
    required String errorMessage,
  }) {
    return LlmExchangeLog(
      timestamp: DateTime.now(),
      providerCode: providerCode,
      modelName: modelName,
      requestId: requestId,
      unitsCount: unitsCount,
      inputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
      processingTimeMs: 0,
      success: false,
      errorMessage: errorMessage,
    );
  }

  /// Get display-friendly summary
  String get summary {
    if (!success) {
      return 'ERROR: $errorMessage';
    }
    return '$providerCode/$modelName: $unitsCount units, ${totalTokens}t, ${processingTimeMs}ms';
  }

  /// Get compact display text for UI
  String get compactDisplay {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    if (!success) {
      return '[$time] ❌ $errorMessage';
    }
    return '[$time] ✓ $unitsCount units → ${totalTokens}t (${processingTimeMs}ms)';
  }
}

