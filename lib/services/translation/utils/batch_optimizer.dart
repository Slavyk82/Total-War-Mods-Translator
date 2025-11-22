import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Utility for optimizing translation batch sizes
///
/// This class calculates optimal batch sizes based on:
/// - Token limits per LLM provider
/// - Average text length in the batch
/// - System and context prompt size
/// - Output estimate
/// - Safety margin for overhead
///
/// It can also split oversized batches and merge undersized ones.
class BatchOptimizer {
  final TokenCalculator _tokenCalculator;

  /// Safety margin as a percentage (default: 10%)
  /// This accounts for tokenization variance and overhead
  static const double _safetyMargin = 0.10;

  /// Minimum batch size (avoid tiny batches)
  static const int _minBatchSize = 5;

  /// Maximum batch size (avoid huge batches)
  static const int _maxBatchSize = 100;

  const BatchOptimizer(this._tokenCalculator);

  /// Calculate optimal batch size for given units and provider
  ///
  /// [units]: Translation units to batch
  /// [providerConfig]: LLM provider configuration with token limits
  /// [systemPromptTokens]: Estimated tokens for system prompt
  /// [contextTokens]: Estimated tokens for context (game + project + examples)
  /// [targetLanguage]: Target language code for output estimation
  ///
  /// Returns optimal number of units per batch
  Future<int> calculateOptimalBatchSize({
    required List<TranslationUnit> units,
    required LlmProviderConfig providerConfig,
    required int systemPromptTokens,
    required int contextTokens,
    required String targetLanguage,
  }) async {
    if (units.isEmpty) {
      throw const EmptyBatchException('Cannot calculate batch size for empty units list');
    }

    // Calculate average source text tokens
    final avgSourceTokens = await _calculateAverageSourceTokens(
      units: units,
      providerCode: providerConfig.providerCode,
    );

    // Estimate output tokens (usually ~1.0x input for most languages)
    final outputMultiplier = _getOutputMultiplier(targetLanguage);
    final avgOutputTokens = (avgSourceTokens * outputMultiplier).ceil();

    // Calculate overhead per unit (key, JSON formatting)
    final overheadPerUnit = await _calculateOverheadPerUnit(
      providerCode: providerConfig.providerCode,
    );

    // Total fixed tokens (system + context)
    final fixedTokens = systemPromptTokens + contextTokens;

    // Available tokens for translation units
    final availableTokens = (providerConfig.maxTokensPerRequest * (1 - _safetyMargin)).ceil() - fixedTokens;

    if (availableTokens <= 0) {
      throw BatchOptimizationException(
        'System and context prompts exceed token limit',
        'Fixed tokens: $fixedTokens, Max: ${providerConfig.maxTokensPerRequest}',
        0,
        providerConfig.maxTokensPerRequest,
      );
    }

    // Tokens per unit (input + output + overhead)
    final tokensPerUnit = avgSourceTokens + avgOutputTokens + overheadPerUnit;

    // Calculate batch size
    final calculatedBatchSize = (availableTokens / tokensPerUnit).floor();

    // Clamp to reasonable range
    final optimalBatchSize = calculatedBatchSize.clamp(_minBatchSize, _maxBatchSize);

    return optimalBatchSize;
  }

  /// Split units into optimally-sized batches
  ///
  /// [units]: All translation units to batch
  /// [optimalBatchSize]: Optimal size calculated by [calculateOptimalBatchSize]
  ///
  /// Returns list of batches, each with <= optimalBatchSize units
  List<List<TranslationUnit>> splitIntoBatches({
    required List<TranslationUnit> units,
    required int optimalBatchSize,
  }) {
    if (units.isEmpty) return [];
    if (optimalBatchSize <= 0) {
      throw BatchOptimizationException(
        'Invalid batch size',
        'Batch size must be positive',
        optimalBatchSize,
        _maxBatchSize,
      );
    }

    final batches = <List<TranslationUnit>>[];
    for (var i = 0; i < units.length; i += optimalBatchSize) {
      final end = (i + optimalBatchSize).clamp(0, units.length);
      batches.add(units.sublist(i, end));
    }

    return batches;
  }

  /// Validate that a batch fits within token limits
  ///
  /// [units]: Units in the batch
  /// [providerConfig]: Provider configuration
  /// [systemPromptTokens]: System prompt tokens
  /// [contextTokens]: Context tokens
  /// [targetLanguage]: Target language
  ///
  /// Returns true if batch fits, false otherwise
  Future<bool> validateBatchSize({
    required List<TranslationUnit> units,
    required LlmProviderConfig providerConfig,
    required int systemPromptTokens,
    required int contextTokens,
    required String targetLanguage,
  }) async {
    final totalTokens = await estimateBatchTokens(
      units: units,
      providerCode: providerConfig.providerCode,
      systemPromptTokens: systemPromptTokens,
      contextTokens: contextTokens,
      targetLanguage: targetLanguage,
    );

    return totalTokens <= providerConfig.maxTokensPerRequest;
  }

  /// Estimate total tokens for a batch
  ///
  /// Includes:
  /// - System prompt
  /// - Context (game + project + examples)
  /// - Input units
  /// - Estimated output
  /// - JSON formatting overhead
  ///
  /// [units]: Units in the batch
  /// [providerCode]: Provider code for tokenization
  /// [systemPromptTokens]: System prompt tokens
  /// [contextTokens]: Context tokens
  /// [targetLanguage]: Target language for output estimation
  ///
  /// Returns total estimated tokens
  Future<int> estimateBatchTokens({
    required List<TranslationUnit> units,
    required String providerCode,
    required int systemPromptTokens,
    required int contextTokens,
    required String targetLanguage,
  }) async {
    if (units.isEmpty) return systemPromptTokens + contextTokens;

    // Calculate input tokens
    int inputTokens = 0;
    for (final unit in units) {
      final tokens = _tokenCalculator.calculateTokens(unit.sourceText);
      inputTokens += tokens;
    }

    // Estimate output tokens
    final outputMultiplier = _getOutputMultiplier(targetLanguage);
    final outputTokens = (inputTokens * outputMultiplier).ceil();

    // Overhead
    final overheadPerUnit = await _calculateOverheadPerUnit(providerCode: providerCode);
    final totalOverhead = overheadPerUnit * units.length;

    return systemPromptTokens + contextTokens + inputTokens + outputTokens + totalOverhead;
  }

  /// Adjust batch size based on historical performance
  ///
  /// Uses actual token usage from previous batches to calibrate estimates.
  ///
  /// [currentBatchSize]: Current optimal batch size
  /// [estimatedTokens]: Estimated tokens for a batch
  /// [actualTokens]: Actual tokens used (from history)
  ///
  /// Returns adjusted batch size
  int adjustBasedOnHistory({
    required int currentBatchSize,
    required int estimatedTokens,
    required int actualTokens,
  }) {
    if (estimatedTokens == 0 || actualTokens == 0) return currentBatchSize;

    // Calculate accuracy ratio
    final accuracyRatio = actualTokens / estimatedTokens;

    // If we're underestimating (ratio > 1), reduce batch size
    // If we're overestimating (ratio < 1), we can increase batch size slightly
    final adjustmentFactor = 1 / accuracyRatio;

    final adjustedSize = (currentBatchSize * adjustmentFactor).round();

    // Clamp to reasonable range
    return adjustedSize.clamp(_minBatchSize, _maxBatchSize);
  }

  /// Calculate average source tokens across units
  Future<int> _calculateAverageSourceTokens({
    required List<TranslationUnit> units,
    required String providerCode,
  }) async {
    if (units.isEmpty) return 0;

    int totalTokens = 0;
    for (final unit in units) {
      final tokens = _tokenCalculator.calculateTokens(unit.sourceText);
      totalTokens += tokens;
    }

    return (totalTokens / units.length).ceil();
  }

  /// Calculate overhead tokens per unit (key + JSON formatting)
  Future<int> _calculateOverheadPerUnit({
    required String providerCode,
  }) async {
    // Typical JSON overhead per unit:
    // {"key": "some_key", "translation": "..."}\n
    const sampleOverhead = '{"key": "example_key_name", "translation": ""},\n';

    final tokens = _tokenCalculator.calculateTokens(sampleOverhead);

    return tokens;
  }

  /// Get output token multiplier for a language
  ///
  /// Some languages produce longer outputs than others:
  /// - German: typically 1.1x - 1.2x
  /// - French: typically 1.0x - 1.1x
  /// - Japanese: typically 0.8x - 0.9x (more compact)
  /// - Chinese: typically 0.6x - 0.7x (very compact)
  double _getOutputMultiplier(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'de': // German
        return 1.15;
      case 'fr': // French
        return 1.05;
      case 'es': // Spanish
        return 1.05;
      case 'it': // Italian
        return 1.05;
      case 'pt': // Portuguese
        return 1.05;
      case 'ru': // Russian
        return 1.1;
      case 'ja': // Japanese
        return 0.85;
      case 'zh': // Chinese
      case 'zh-cn':
      case 'zh-tw':
        return 0.65;
      case 'ko': // Korean
        return 0.9;
      default:
        return 1.0; // Default for other languages
    }
  }
}
