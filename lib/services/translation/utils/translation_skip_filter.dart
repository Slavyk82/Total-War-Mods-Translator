import '../ignored_source_text_service.dart';

/// Utility class for filtering translation units that should be skipped.
///
/// Provides centralized logic for determining which source texts should not
/// be sent to Translation Memory or LLM translation.
///
/// The class supports two modes:
/// - **Database-backed mode**: Uses [IgnoredSourceTextService] for user-configurable
///   skip texts. Call [initialize] to enable this mode.
/// - **Fallback mode**: Uses hardcoded defaults when service is not available.
class TranslationSkipFilter {
  TranslationSkipFilter._();

  /// Reference to the database-backed service for configurable skip texts.
  static IgnoredSourceTextService? _service;

  /// Default source texts for fallback when service is not available.
  ///
  /// These match the default values seeded in the database.
  /// Note: Texts fully enclosed in brackets like [placeholder] are handled
  /// by isFullyBracketedText() and don't need to be listed here.
  static const _defaultSkipSourceTexts = <String>{
    'placeholder',
    'dummy',
  };

  /// Initialize with the database-backed service.
  ///
  /// Call this during app startup to enable user-configurable skip texts.
  /// If not called, the filter will use hardcoded defaults.
  static void initialize(IgnoredSourceTextService service) {
    _service = service;
  }

  /// Check if the service has been initialized.
  static bool get isInitialized => _service != null;

  /// Get the SQL condition for excluding skip texts in statistics queries.
  ///
  /// Returns a SQL snippet suitable for use in WHERE clauses.
  /// If service is not initialized, builds condition from defaults.
  static String getSqlCondition() {
    if (_service != null) {
      return _service!.getSqlCondition();
    }
    // Fallback: build from defaults
    final escaped = _defaultSkipSourceTexts
        .map((t) => "'${t.replaceAll("'", "''")}'")
        .join(', ');
    return 'LOWER(TRIM(tu.source_text)) IN ($escaped)';
  }

  /// Checks if the source text is entirely a simple bracketed placeholder.
  ///
  /// These texts are typically placeholders or non-translatable markers
  /// and should be copied as-is without translation.
  /// Example: "[PLACEHOLDER]", "[unit_name]"
  ///
  /// Does NOT match BBCode/Total War double-bracket tags like:
  /// "[[col:yellow]]text[[/col]]" - these should be translated
  ///
  /// Note: This is structural detection and is NOT configurable by users.
  static bool isFullyBracketedText(String text) {
    final trimmed = text.trim();

    // Must start with [ and end with ]
    if (!trimmed.startsWith('[') ||
        !trimmed.endsWith(']') ||
        trimmed.length <= 2) {
      return false;
    }

    // If it starts with [[ it's BBCode, not a placeholder - should translate
    if (trimmed.startsWith('[[')) {
      return false;
    }

    // Check if it's a simple single-bracketed expression: [something]
    // Should have exactly one [ at start and one ] at end
    final innerContent = trimmed.substring(1, trimmed.length - 1);

    // If inner content contains more brackets, it's not a simple placeholder
    if (innerContent.contains('[') || innerContent.contains(']')) {
      return false;
    }

    // Simple placeholder like [PLACEHOLDER] or [unit_name]
    return true;
  }

  /// Checks if the source text should be skipped from translation.
  ///
  /// Returns true if the text matches any of the skip patterns:
  /// - Fully bracketed text like [PLACEHOLDER] (structural, not configurable)
  /// - User-configurable skip texts from the database
  /// - Default skip texts as fallback
  static bool shouldSkip(String text) {
    final trimmed = text.trim();

    // Check for fully bracketed text (structural rule, not configurable)
    if (isFullyBracketedText(trimmed)) {
      return true;
    }

    // Check against database-backed list if service is available
    if (_service != null) {
      return _service!.shouldSkip(trimmed);
    }

    // Fallback to hardcoded defaults
    return _defaultSkipSourceTexts.contains(trimmed.toLowerCase());
  }
}
