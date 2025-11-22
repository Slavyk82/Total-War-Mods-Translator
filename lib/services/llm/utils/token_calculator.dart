import 'package:tiktoken/tiktoken.dart';
import 'package:twmt/services/llm/models/llm_request.dart';

/// Token calculator for LLM requests
///
/// Uses tiktoken with cl100k_base encoding (used by GPT-4, GPT-3.5, Claude)
/// Provides accurate token counting for token estimation and batch sizing.
class TokenCalculator {
  /// Tiktoken encoding instance (cl100k_base)
  late final dynamic _encoding;

  /// LRU cache for token counts (text -> token count)
  final Map<String, int> _cache = {};

  /// Maximum cache size (10,000 entries)
  static const int _maxCacheSize = 10000;

  /// Language-specific multipliers for output estimation
  static const Map<String, double> _languageMultipliers = {
    'zh': 1.5, // Chinese
    'ja': 1.5, // Japanese
    'ko': 1.5, // Korean
    'ru': 1.2, // Russian
    'de': 1.1, // German
    'ar': 1.3, // Arabic
    'th': 1.4, // Thai
    // Default: 1.0 for most languages
  };

  /// Singleton instance
  static final TokenCalculator _instance = TokenCalculator._internal();

  factory TokenCalculator() => _instance;

  TokenCalculator._internal() {
    // Initialize tiktoken with cl100k_base encoding
    _encoding = encodingForModel('gpt-4');
  }

  /// Calculate tokens for a single text
  ///
  /// Uses cache for performance.
  ///
  /// [text] - Text to calculate tokens for
  ///
  /// Returns token count
  int calculateTokens(String text) {
    if (text.isEmpty) return 0;

    // Check cache
    if (_cache.containsKey(text)) {
      return _cache[text]!;
    }

    // Calculate tokens using tiktoken
    final tokens = _encoding.encode(text).length;

    // Add to cache (with LRU eviction)
    _addToCache(text, tokens);

    return tokens;
  }

  /// Calculate tokens for multiple texts
  ///
  /// [texts] - List of texts to calculate tokens for
  ///
  /// Returns total token count
  int calculateTokensForTexts(List<String> texts) {
    return texts.fold(0, (sum, text) => sum + calculateTokens(text));
  }

  /// Calculate tokens for a map of texts (key-value pairs)
  ///
  /// [texts] - Map of texts to calculate tokens for
  ///
  /// Returns total token count (keys + values)
  int calculateTokensForMap(Map<String, String> texts) {
    int total = 0;
    for (final entry in texts.entries) {
      total += calculateTokens(entry.key);
      total += calculateTokens(entry.value);
    }
    return total;
  }

  /// Estimate tokens for a complete LLM request
  ///
  /// Includes:
  /// - System prompt
  /// - Game context (if provided)
  /// - Project context (if provided)
  /// - Few-shot examples (if provided)
  /// - Glossary terms (if provided)
  /// - Input texts (keys + values)
  /// - Estimated output (based on input and target language)
  ///
  /// [request] - LLM request to estimate
  ///
  /// Returns estimated total tokens (input + output)
  int estimateRequestTokens(LlmRequest request) {
    int inputTokens = 0;

    // System prompt
    inputTokens += calculateTokens(request.systemPrompt);

    // Game context
    if (request.gameContext != null) {
      inputTokens += calculateTokens(request.gameContext!);
    }

    // Project context
    if (request.projectContext != null) {
      inputTokens += calculateTokens(request.projectContext!);
    }

    // Few-shot examples
    if (request.fewShotExamples != null) {
      for (final example in request.fewShotExamples!) {
        inputTokens += calculateTokens(example.source);
        inputTokens += calculateTokens(example.target);
      }
    }

    // Glossary terms
    if (request.glossaryTerms != null) {
      inputTokens += calculateTokensForMap(request.glossaryTerms!);
    }

    // Input texts (keys + values)
    inputTokens += calculateTokensForMap(request.texts);

    // Add overhead for JSON structure (~5%)
    inputTokens = (inputTokens * 1.05).ceil();

    // Estimate output tokens
    final outputTokens = estimateOutputTokens(
      inputTokens: inputTokens,
      targetLanguage: request.targetLanguage,
      textCount: request.texts.length,
    );

    return inputTokens + outputTokens;
  }

  /// Estimate output tokens based on input and target language
  ///
  /// Uses language-specific multipliers for languages that tend to be
  /// longer (Chinese, Japanese, Russian, etc.)
  ///
  /// [inputTokens] - Input token count
  /// [targetLanguage] - Target language code (ISO 639-1)
  /// [textCount] - Number of texts being translated
  ///
  /// Returns estimated output tokens
  int estimateOutputTokens({
    required int inputTokens,
    required String targetLanguage,
    required int textCount,
  }) {
    // Base estimate: output is roughly equal to input for translation
    // (excluding system prompt, context, examples)
    // Assume 30% of input tokens are actual text to translate
    double baseOutputTokens = inputTokens * 0.3;

    // Apply language-specific multiplier
    final multiplier = _languageMultipliers[targetLanguage.toLowerCase()] ?? 1.0;
    baseOutputTokens *= multiplier;

    // Add overhead for JSON structure per text (~10 tokens per text)
    baseOutputTokens += textCount * 10;

    // Add safety buffer (20%)
    baseOutputTokens *= 1.2;

    return baseOutputTokens.ceil();
  }

  /// Add entry to cache with LRU eviction
  void _addToCache(String text, int tokens) {
    // If cache is full, remove oldest entry (first entry)
    if (_cache.length >= _maxCacheSize) {
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
    }

    _cache[text] = tokens;
  }

  /// Clear the cache
  void clearCache() {
    _cache.clear();
  }

  /// Get cache statistics
  CacheStatistics getCacheStatistics() {
    return CacheStatistics(
      size: _cache.length,
      maxSize: _maxCacheSize,
      hitRate: 0.0, // Would need hit/miss tracking for accurate rate
    );
  }

  /// Anthropic token estimation (adds 7.5% correction factor)
  ///
  /// Anthropic uses a similar tokenizer but with slight differences.
  /// Add 7.5% to tiktoken count for better accuracy.
  ///
  /// [text] - Text to estimate tokens for
  ///
  /// Returns estimated Anthropic token count
  int calculateAnthropicTokens(String text) {
    final baseTokens = calculateTokens(text);
    return (baseTokens * 1.075).ceil();
  }

  /// Estimate request tokens for Anthropic
  ///
  /// [request] - LLM request to estimate
  ///
  /// Returns estimated total tokens (input + output) for Anthropic
  int estimateAnthropicRequestTokens(LlmRequest request) {
    final baseTokens = estimateRequestTokens(request);
    return (baseTokens * 1.075).ceil();
  }

  /// Calculate character count for DeepL
  ///
  /// DeepL uses character-based billing, not tokens.
  ///
  /// [texts] - Map of texts to count characters for
  ///
  /// Returns total character count (source texts only)
  int calculateCharacterCount(Map<String, String> texts) {
    return texts.values.fold(0, (sum, text) => sum + text.length);
  }
}

/// Cache statistics
class CacheStatistics {
  /// Current cache size
  final int size;

  /// Maximum cache size
  final int maxSize;

  /// Cache hit rate (0.0-1.0)
  final double hitRate;

  const CacheStatistics({
    required this.size,
    required this.maxSize,
    required this.hitRate,
  });

  /// Utilization percentage
  double get utilization => size / maxSize;

  @override
  String toString() {
    return 'CacheStatistics(size: $size/$maxSize, '
        'utilization: ${(utilization * 100).toStringAsFixed(1)}%, '
        'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';
  }
}
