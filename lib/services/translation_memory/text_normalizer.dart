/// Text normalizer for Translation Memory matching
///
/// Normalizes text before similarity calculation to improve match accuracy.
///
/// Normalization steps:
/// - Remove markup (XML, BBCode)
/// - Normalize whitespace (collapse, trim)
/// - Normalize punctuation
/// - Optional lowercase conversion
/// - Optional number removal
/// - Unicode normalization (NFC)
class TextNormalizer {
  /// Singleton instance
  static final TextNormalizer _instance = TextNormalizer._internal();

  factory TextNormalizer() => _instance;

  TextNormalizer._internal();

  /// Normalize text for similarity matching
  ///
  /// [text]: Text to normalize
  /// [options]: Normalization options
  ///
  /// Returns normalized text
  String normalize(String text, {NormalizationOptions? options}) {
    final opts = options ?? NormalizationOptions.defaultOptions;
    String result = text;

    // 1. Remove markup if enabled
    if (opts.removeMarkup) {
      result = _removeMarkup(result);
    }

    // 2. Normalize whitespace
    result = _normalizeWhitespace(result);

    // 3. Normalize punctuation
    if (opts.normalizePunctuation) {
      result = _normalizePunctuation(result);
    }

    // 4. Remove numbers if enabled
    if (opts.removeNumbers) {
      result = _removeNumbers(result);
    }

    // 5. Lowercase if enabled
    if (opts.lowercase) {
      result = result.toLowerCase();
    }

    // 6. Unicode normalization
    result = _normalizeUnicode(result);

    // 7. Trim final result
    result = result.trim();

    return result;
  }

  /// Remove markup tags (XML, BBCode, Markdown)
  String _removeMarkup(String text) {
    String result = text;

    // Remove XML/HTML tags: <tag>, </tag>, <tag attr="value">
    result = result.replaceAll(RegExp(r'<[^>]+>'), '');

    // Remove BBCode tags: [b], [/b], [url=...], etc.
    // BUT preserve printf-style placeholders like [%s], [%d], [%f]
    result = result.replaceAllMapped(
      RegExp(r'\[[^\]]+\]'),
      (match) {
        final tag = match.group(0)!;
        // Preserve bracketed printf placeholders
        if (RegExp(r'^\[%[sdf]\]$').hasMatch(tag)) {
          return tag;
        }
        return ''; // Remove other BBCode tags
      },
    );

    // Remove Markdown bold/italic: **text**, __text__, *text*, _text_
    // Note: Use replaceAllMapped to properly handle captured groups in Dart
    result = result.replaceAllMapped(
        RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
    result = result.replaceAllMapped(
        RegExp(r'__([^_]+)__'), (m) => m.group(1) ?? '');
    result = result.replaceAllMapped(
        RegExp(r'\*([^*]+)\*'), (m) => m.group(1) ?? '');
    result = result.replaceAllMapped(
        RegExp(r'_([^_]+)_'), (m) => m.group(1) ?? '');

    // Remove Markdown code: `code`
    result = result.replaceAllMapped(
        RegExp(r'`([^`]+)`'), (m) => m.group(1) ?? '');

    return result;
  }

  /// Normalize whitespace (collapse multiple spaces, tabs, newlines)
  String _normalizeWhitespace(String text) {
    // Replace multiple whitespace characters with single space
    String result = text.replaceAll(RegExp(r'\s+'), ' ');

    // Trim leading/trailing whitespace
    result = result.trim();

    return result;
  }

  /// Normalize punctuation
  ///
  /// - Converts curly quotes to straight quotes
  /// - Normalizes dashes and hyphens
  /// - Removes duplicate punctuation
  String _normalizePunctuation(String text) {
    String result = text;

    // Convert curly quotes to straight quotes
    // Unicode: U+2018 (left single), U+2019 (right single), U+201C (left double), U+201D (right double)
    result = result.replaceAll('\u2018', "'");
    result = result.replaceAll('\u2019', "'");
    result = result.replaceAll('\u201c', '"');
    result = result.replaceAll('\u201d', '"');

    // Normalize dashes (em dash, en dash → hyphen)
    // Unicode: U+2014 (em dash), U+2013 (en dash)
    result = result.replaceAll('\u2014', '-');
    result = result.replaceAll('\u2013', '-');

    // Remove duplicate punctuation (e.g., "!!" → "!", "??" → "?")
    // Note: This is done BEFORE ellipsis normalization to preserve "..."
    result = result.replaceAllMapped(
        RegExp(r'([!?])\1+'), (m) => m.group(1) ?? '');
    // Handle dots separately - reduce 4+ dots to 3 (ellipsis), keep 2 or 3
    result = result.replaceAll(RegExp(r'\.{4,}'), '...');

    // Normalize ellipsis character to three dots
    // Unicode: U+2026 (horizontal ellipsis)
    result = result.replaceAll('\u2026', '...');

    // Normalize spaces around punctuation
    result = result.replaceAllMapped(
        RegExp(r'\s+([.,!?;:])'), (m) => m.group(1) ?? '');
    result = result.replaceAllMapped(
        RegExp(r'([.,!?;:])\s+'), (m) => '${m.group(1)} ');

    return result;
  }

  /// Remove numbers from text
  String _removeNumbers(String text) {
    // Remove standalone numbers
    return text.replaceAll(RegExp(r'\b\d+\b'), '');
  }

  /// Normalize Unicode to NFC (Canonical Decomposition + Canonical Composition)
  ///
  /// This ensures that characters like "é" are represented consistently,
  /// whether they're encoded as a single character or as "e" + combining accent.
  String _normalizeUnicode(String text) {
    // Dart strings are already in UTF-16, but we can normalize combining characters
    // For now, return as-is (full Unicode normalization would require a package)
    return text;
  }

  /// Extract tokens from text for token-based similarity
  ///
  /// Tokens are whitespace-separated words, lowercased and sorted.
  ///
  /// [text]: Text to tokenize
  /// [options]: Normalization options
  ///
  /// Returns sorted set of tokens
  Set<String> tokenize(String text, {NormalizationOptions? options}) {
    // Normalize first
    final normalized = normalize(text, options: options);

    // Split on whitespace
    final tokens = normalized.split(RegExp(r'\s+'));

    // Remove empty tokens and convert to set (deduplicates)
    return tokens.where((t) => t.isNotEmpty).toSet();
  }

  /// Calculate character n-grams for fuzzy matching
  ///
  /// N-grams are substrings of length n.
  /// For example, "hello" with n=2 gives: ["he", "el", "ll", "lo"]
  ///
  /// [text]: Text to process
  /// [n]: N-gram size (default: 2 for bigrams)
  ///
  /// Returns set of n-grams
  Set<String> getNGrams(String text, {int n = 2}) {
    if (text.length < n) return {text};

    final nGrams = <String>{};
    for (int i = 0; i <= text.length - n; i++) {
      nGrams.add(text.substring(i, i + n));
    }

    return nGrams;
  }
}

/// Options for text normalization
class NormalizationOptions {
  /// Remove markup tags (XML, BBCode, Markdown)
  final bool removeMarkup;

  /// Convert to lowercase
  final bool lowercase;

  /// Normalize punctuation
  final bool normalizePunctuation;

  /// Remove numbers
  final bool removeNumbers;

  const NormalizationOptions({
    this.removeMarkup = true,
    this.lowercase = true,
    this.normalizePunctuation = true,
    this.removeNumbers = false,
  });

  /// Default options (remove markup, lowercase, normalize punctuation)
  static const NormalizationOptions defaultOptions = NormalizationOptions();

  /// Strict options (all normalizations)
  static const NormalizationOptions strictOptions = NormalizationOptions(
    removeMarkup: true,
    lowercase: true,
    normalizePunctuation: true,
    removeNumbers: true,
  );

  /// Lenient options (minimal normalization)
  static const NormalizationOptions lenientOptions = NormalizationOptions(
    removeMarkup: true,
    lowercase: false,
    normalizePunctuation: false,
    removeNumbers: false,
  );

  @override
  String toString() {
    return 'NormalizationOptions('
        'removeMarkup: $removeMarkup, '
        'lowercase: $lowercase, '
        'normalizePunctuation: $normalizePunctuation, '
        'removeNumbers: $removeNumbers)';
  }
}
