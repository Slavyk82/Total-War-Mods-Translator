import 'dart:convert';

import 'package:tiktoken/tiktoken.dart';
// ignore: implementation_imports
import 'package:tiktoken/src/common/byte_array.dart';
import 'package:twmt/services/llm/models/llm_request.dart';

import 'cl100k_base_ranks.dart';

/// Token calculator for LLM requests
///
/// Uses tiktoken with cl100k_base encoding (used by GPT-4, GPT-3.5, Claude)
/// Provides accurate token counting for token estimation and batch sizing.
///
/// The encoding is assembled here rather than via tiktoken's `getEncoding`:
/// that path initialises `package:tiktoken`'s ~100k-entry `cl100kBase` map
/// literal, which the Dart VM intermittently fails to build inside a large
/// program, throwing a bogus `is not a subtype of type 'String'` out of
/// `Map._fromLiteral` (the reported type varies run to run). It made roughly
/// half of all full-suite `flutter test` runs red and could equally break
/// translation in the shipped app, since every LLM provider constructs this
/// singleton and there is no fallback. Parsing the identical ranks from one
/// const string ([cl100kBaseRanksData]) avoids the pathological literal.
class TokenCalculator {
  /// Tiktoken encoding instance (cl100k_base)
  late final Tiktoken _encoding;

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
    _encoding = _buildCl100kBase();
  }

  /// Splitting pattern for cl100k_base.
  ///
  /// Copied verbatim from `CoreBPEConstructor.cl100kBase()` in tiktoken 1.0.3.
  /// It must stay byte-for-byte identical to that source, or tokenization
  /// silently diverges from the encoding OpenAI and Anthropic actually bill.
  static const String _cl100kPatStr =
      r"(\?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+";

  /// Special tokens for cl100k_base, also verbatim from tiktoken 1.0.3.
  static const Map<String, int> _cl100kSpecialTokens = {
    '<|endoftext|>': 100257,
    '<|fim_prefix|>': 100258,
    '<|fim_middle|>': 100259,
    '<|fim_suffix|>': 100260,
    '<|endofprompt|>': 100276,
  };

  /// Build the cl100k_base encoding from the vendored ranks table.
  ///
  /// Produces exactly the same encoding as `getEncoding('cl100k_base')` —
  /// same ranks, same pattern, same special tokens — without touching the
  /// map literal described in the class doc.
  static Tiktoken _buildCl100kBase() {
    final mergeableRanks = <ByteArray, int>{};
    for (final line in const LineSplitter().convert(cl100kBaseRanksData)) {
      if (line.isEmpty) continue;
      final separator = line.indexOf(' ');
      mergeableRanks[ByteArray.fromList(
        base64Decode(line.substring(0, separator)),
      )] = int.parse(line.substring(separator + 1));
    }

    return Tiktoken(
      name: 'cl100k_base',
      patStr: _cl100kPatStr,
      mergeableRanks: mergeableRanks,
      specialTokens: _cl100kSpecialTokens,
    );
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

    // Check cache. On a hit, move the entry to the most-recently-used
    // position (remove + re-insert) so eviction is true LRU, not FIFO.
    // Dart's Map is a LinkedHashMap, so insertion order == recency order and
    // `keys.first` (evicted in _addToCache) is the least-recently-used entry.
    // Safe because TokenCalculator is a singleton accessed from a single
    // isolate; there is no concurrent mutation during this read-modify-write.
    final cached = _cache.remove(text);
    if (cached != null) {
      _cache[text] = cached;
      return cached;
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
    // If cache is full, evict the least-recently-used entry. Because hits in
    // [calculateTokens] re-insert the accessed key (moving it to the end),
    // `keys.first` is the LRU entry, making this a true LRU policy.
    if (_cache.length >= _maxCacheSize) {
      final lruKey = _cache.keys.first;
      _cache.remove(lruKey);
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
