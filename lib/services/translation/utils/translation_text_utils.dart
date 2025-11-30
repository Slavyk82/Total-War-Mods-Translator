/// Utility class for post-processing translated text
///
/// Applies normalization rules to ensure consistency between source
/// and translated text formatting.
class TranslationTextUtils {
  /// Private constructor - all methods are static
  TranslationTextUtils._();

  /// Normalize translated text by applying standard post-processing rules
  ///
  /// Keeps actual newline characters as-is for storage in the database.
  /// The source text (English) is stored with actual newlines, so translated
  /// text must also use actual newlines for consistency.
  ///
  /// Escaping to `\n` sequences is done only at export time by the
  /// LocFileService._escapeTsvText() method.
  ///
  /// Handles edge cases from LLM responses:
  /// - `\<newline>` (backslash + actual newline) → actual newline (removes spurious backslash)
  /// - `\n` (escaped sequence from LLM) → actual newline
  /// - Normalizes Windows CRLF to Unix LF
  static String normalizeTranslation(String text) {
    // Step 1: Handle double-backslash escape sequences from LLM
    // Pattern: `\\n` (3 chars: backslash, backslash, n) → actual newline
    // Must be done BEFORE single backslash handling to avoid leaving stray backslashes
    var result = text.replaceAll(r'\\r\\n', '\n');
    result = result.replaceAll(r'\\n', '\n');
    result = result.replaceAll(r'\\r', '');

    // Step 2: Handle single-backslash escape sequences from LLM
    // Pattern: `\n` (2 chars: backslash, n) → actual newline
    result = result.replaceAll(r'\r\n', '\n');
    result = result.replaceAll(r'\n', '\n');

    // Step 3: Handle corrupted pattern where backslash precedes actual newline
    // Pattern: `\` + actual newline → just newline
    // This handles cases like byte sequence [92, 10] → [10]
    result = result.replaceAll('\\\r\n', '\n');
    result = result.replaceAll('\\\n', '\n');

    // Step 4: Normalize Windows CRLF to Unix LF for consistency
    result = result.replaceAll('\r\n', '\n');
    result = result.replaceAll('\r', '');

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

