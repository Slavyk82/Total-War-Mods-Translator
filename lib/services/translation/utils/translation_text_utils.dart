/// Utility class for post-processing translated text
///
/// Applies normalization rules to ensure consistency between source
/// and translated text formatting.
class TranslationTextUtils {
  /// Private constructor - all methods are static
  TranslationTextUtils._();

  /// Normalize translated text by applying standard post-processing rules
  ///
  /// Converts actual newline characters to escaped format for .loc files.
  /// Total War .loc files use `\n` (backslash + n, 2 chars) to represent newlines.
  ///
  /// Handles multiple patterns from LLM responses:
  /// - `\<newline>` (backslash + actual newline) → `\n` (removes the actual newline)
  /// - Actual newlines alone → `\n`
  /// - Carriage returns with newlines → `\r\n`
  static String normalizeTranslation(String text) {
    // Step 1: Handle corrupted pattern where backslash precedes actual newline
    // Pattern: `\` followed by actual newline → should become just `\n` (2 chars)
    // This handles cases like byte sequence [92, 10] → [92, 110]
    var result = text.replaceAll('\\\r\n', r'\r\n');
    result = result.replaceAll('\\\n', r'\n');

    // Step 2: Handle remaining actual newlines (without preceding backslash)
    result = result.replaceAll('\r\n', r'\r\n');
    result = result.replaceAll('\n', r'\n');

    return result;
  }

  /// Batch normalize multiple translations
  ///
  /// Returns a new map with normalized values
  static Map<String, String> normalizeTranslations(Map<String, String> translations) {
    return translations.map(
      (key, value) => MapEntry(key, normalizeTranslation(value)),
    );
  }
}

