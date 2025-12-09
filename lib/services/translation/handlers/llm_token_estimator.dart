import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/translation/models/translation_context.dart';

/// Handles token estimation and batch size calculation for LLM translation.
///
/// Responsibilities:
/// - Estimate max tokens for output based on source text content
/// - Calculate optimal batch sizes to avoid token limits
/// - Estimate total tokens for batches of translation units
class LlmTokenEstimator {
  final TokenCalculator _tokenCalculator = TokenCalculator();

  /// Estimate maxTokens based on source text content, not just unit count.
  ///
  /// For long texts, 120 tokens/unit is insufficient. Uses character count
  /// as a more accurate proxy (roughly 4 chars per token for most languages).
  int estimateMaxTokens(Map<String, String> textsMap) {
    // Calculate based on actual text length
    int totalChars = 0;
    for (final text in textsMap.values) {
      totalChars += text.length;
    }

    // Estimate: ~4 chars per token, translation may be 1.2x longer than source
    // Add buffer for JSON structure overhead
    final textBasedEstimate = ((totalChars / 4) * 1.3).ceil() + 500;

    // Also consider unit count for JSON key overhead
    final unitBasedEstimate = (textsMap.length * 150) + 500;

    // Use the larger of the two estimates
    final estimate = textBasedEstimate > unitBasedEstimate
        ? textBasedEstimate
        : unitBasedEstimate;

    // Clamp to reasonable bounds: minimum 1000, maximum 80000
    return estimate.clamp(1000, 80000);
  }

  /// Calculate optimal batch size based on token estimation.
  ///
  /// Estimates:
  /// - Fixed tokens (system prompt, context, glossary)
  /// - Average tokens per unit (input + output + JSON overhead)
  /// - Maximum units that fit within Anthropic's 200k token limit with safety margin
  int calculateOptimalBatchSize({
    required LlmRequest llmRequest,
    required List<TranslationUnit> units,
    required TranslationContext context,
  }) {
    // Provider max tokens (Anthropic: 200k for input+output combined)
    const int maxTokens = 200000;
    // Safety margin: use only 40% to account for estimation errors and response overhead
    // The output can be larger than input due to JSON structure
    const double safetyMargin = 0.4;
    final int safeMaxTokens = (maxTokens * safetyMargin).floor();

    // Calculate fixed context tokens (system prompt + context)
    int fixedTokens = 0;

    // System prompt
    fixedTokens += _tokenCalculator.calculateAnthropicTokens(llmRequest.systemPrompt);

    // Game context
    if (llmRequest.gameContext != null) {
      fixedTokens += _tokenCalculator.calculateAnthropicTokens(llmRequest.gameContext!);
    }

    // Project context
    if (llmRequest.projectContext != null) {
      fixedTokens += _tokenCalculator.calculateAnthropicTokens(llmRequest.projectContext!);
    }

    // Few-shot examples
    if (llmRequest.fewShotExamples != null) {
      for (final example in llmRequest.fewShotExamples!) {
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(example.source);
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(example.target);
      }
    }

    // Glossary terms
    if (llmRequest.glossaryTerms != null) {
      for (final entry in llmRequest.glossaryTerms!.entries) {
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(entry.key);
        fixedTokens += _tokenCalculator.calculateAnthropicTokens(entry.value);
      }
    }

    // If fixed tokens already exceed safe limit, return minimum
    if (fixedTokens >= safeMaxTokens) {
      return 1;
    }

    // Calculate average tokens per unit from sample
    final sampleSize = units.length.clamp(1, 10);
    int totalUnitTokens = 0;

    for (var i = 0; i < sampleSize; i++) {
      final unit = units[i];

      // Input tokens (key + source text)
      totalUnitTokens += _tokenCalculator.calculateAnthropicTokens(unit.id);
      totalUnitTokens += _tokenCalculator.calculateAnthropicTokens(unit.sourceText);

      // Estimated output tokens (roughly equal to input for translations)
      totalUnitTokens += _tokenCalculator.calculateAnthropicTokens(unit.sourceText);

      // JSON overhead per unit: {"key": "uuid-36-chars", "translation": "..."},
      // Includes: JSON structure (~10 tokens) + UUID (~10 tokens) + punctuation (~15 tokens)
      totalUnitTokens += 35;
    }

    final avgTokensPerUnit = (totalUnitTokens / sampleSize).ceil();

    // Available tokens for units
    final availableTokens = safeMaxTokens - fixedTokens;

    // Calculate optimal batch size
    final calculatedSize = (availableTokens / avgTokensPerUnit).floor();

    // Handle auto mode (unitsPerBatch = 0) vs manual limit
    final int optimalSize;
    if (context.unitsPerBatch == 0) {
      // Auto mode: use calculated size with reasonable max (1000)
      optimalSize = calculatedSize.clamp(1, 1000);
    } else {
      // Manual mode: clamp to user-defined max batch size
      optimalSize = calculatedSize.clamp(1, context.unitsPerBatch);
    }

    return optimalSize;
  }

  /// Estimate total tokens for a batch of units.
  ///
  /// Quick estimation without building full request.
  int estimateTokensForUnits({
    required LlmRequest llmRequest,
    required List<TranslationUnit> units,
  }) {
    // Create a mock request with these units for estimation
    final textsMap = {for (var unit in units) unit.id: unit.sourceText};
    final mockRequest = llmRequest.copyWith(texts: textsMap);

    return _tokenCalculator.estimateAnthropicRequestTokens(mockRequest);
  }
}
