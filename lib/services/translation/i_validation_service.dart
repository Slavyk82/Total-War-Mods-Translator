import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/validation_result.dart' as common;
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Service for validating translations against quality rules
///
/// This service performs various validation checks on translations:
/// - Completeness (all keys translated)
/// - Length constraints (max characters)
/// - Variable preservation ({0}, {1}, etc.)
/// - Markup preservation (XML tags, BBCode)
/// - Encoding validation (valid UTF-8)
/// - Glossary term consistency
/// - Security checks (code injection detection)
/// - Truncation detection
abstract class IValidationService {
  /// Validate a single translation
  ///
  /// Performs all validation checks on a translation and returns
  /// a comprehensive result with errors and warnings.
  ///
  /// [sourceText]: Original text in source language
  /// [translatedText]: Translated text in target language
  /// [key]: Unique identifier for the translation unit
  /// [glossaryTerms]: Optional glossary terms to check
  /// [maxLength]: Optional maximum length constraint
  ///
  /// Returns:
  /// - [ValidationResult] with errors and warnings
  ///
  /// Throws:
  /// - [ValidationException] if validation process fails
  Future<Result<common.ValidationResult, ValidationException>>
      validateTranslation({
    required String sourceText,
    required String translatedText,
    required String key,
    Map<String, String>? glossaryTerms,
    int? maxLength,
  });

  /// Validate a batch of translations
  ///
  /// Validates multiple translations in parallel for efficiency.
  ///
  /// [translations]: Map of key -> translated text
  /// [sourcesMap]: Map of key -> source text
  /// [glossaryTerms]: Optional glossary terms to check
  /// [maxLength]: Optional maximum length constraint
  ///
  /// Returns:
  /// - Map of key -> ValidationResult for each translation
  Future<Result<Map<String, common.ValidationResult>, ValidationException>>
      validateBatch({
    required Map<String, String> translations,
    required Map<String, String> sourcesMap,
    Map<String, String>? glossaryTerms,
    int? maxLength,
  });

  /// Check if translation is complete (not empty)
  ///
  /// Returns error if translation is null, empty, or only whitespace.
  Future<ValidationError?> checkCompleteness({
    required String translatedText,
    required String key,
  });

  /// Check if translation respects length constraints
  ///
  /// Returns error if translation exceeds maxLength.
  /// Returns warning if translation is significantly shorter or longer than source.
  Future<ValidationError?> checkLength({
    required String sourceText,
    required String translatedText,
    required String key,
    int? maxLength,
  });

  /// Check if all variables are preserved
  ///
  /// Variables formats:
  /// - {0}, {1}, {2}, ... (positional)
  /// - {name}, {count}, ... (named)
  /// - %s, %d, %f, ... (printf-style)
  /// - $var, ${var} (template-style)
  ///
  /// Returns error if variables are missing or added incorrectly.
  Future<ValidationError?> checkVariablePreservation({
    required String sourceText,
    required String translatedText,
    required String key,
  });

  /// Check if markup tags are preserved
  ///
  /// Supported markup:
  /// - XML: &lt;tag&gt;, &lt;/tag&gt;, &lt;tag attr="value"&gt;
  /// - BBCode: [b], [/b], [i], [url], etc.
  /// - Markdown: **, __, `, etc.
  ///
  /// Returns error if tags are missing, malformed, or unbalanced.
  Future<ValidationError?> checkMarkupPreservation({
    required String sourceText,
    required String translatedText,
    required String key,
  });

  /// Check if text is valid UTF-8
  ///
  /// Returns error if encoding is invalid or contains control characters.
  Future<ValidationError?> checkEncoding({
    required String translatedText,
    required String key,
  });

  /// Check if glossary terms are used consistently
  ///
  /// Verifies that:
  /// - Glossary terms in source are translated correctly
  /// - Translations match the glossary
  /// - Case sensitivity is respected
  ///
  /// Returns warning if terms don't match glossary.
  Future<ValidationError?> checkGlossaryConsistency({
    required String sourceText,
    required String translatedText,
    required String key,
    required Map<String, String> glossaryTerms,
  });

  /// Check for potential code injection or security issues
  ///
  /// Detects suspicious patterns:
  /// - SQL injection attempts
  /// - Script injection (<script>, javascript:)
  /// - Command injection (shell commands)
  /// - Path traversal (../, ..\)
  ///
  /// Returns error if suspicious patterns are detected.
  Future<ValidationError?> checkSecurity({
    required String translatedText,
    required String key,
  });

  /// Check if translation appears truncated
  ///
  /// Detects truncation indicators:
  /// - Ends with ellipsis (...)
  /// - Incomplete sentence (no ending punctuation)
  /// - Significantly shorter than source without reason
  /// - Ends mid-word
  ///
  /// Returns warning if truncation is suspected.
  Future<ValidationError?> checkTruncation({
    required String sourceText,
    required String translatedText,
    required String key,
  });

  /// Check for common translation mistakes
  ///
  /// Detects:
  /// - Repeated words (the the, of of)
  /// - Missing punctuation
  /// - Inconsistent capitalization
  /// - Numbers don't match source
  ///
  /// Returns warning for potential mistakes.
  Future<List<ValidationError>> checkCommonMistakes({
    required String sourceText,
    required String translatedText,
    required String key,
  });

  /// Validate JSON structure from LLM response
  ///
  /// Checks that the LLM returned valid JSON with the expected structure:
  /// ```json
  /// {
  ///   "translations": [
  ///     {"key": "key1", "translation": "..."},
  ///     {"key": "key2", "translation": "..."}
  ///   ]
  /// }
  /// ```
  ///
  /// [jsonResponse]: Raw JSON response from LLM
  /// [expectedKeys]: List of keys that should be present
  ///
  /// Returns:
  /// - Map of key -> translated text if valid
  /// - ValidationException if JSON is invalid or incomplete
  Future<Result<Map<String, String>, ValidationException>>
      validateLlmResponse({
    required String jsonResponse,
    required List<String> expectedKeys,
  });

  /// Get validation rules configuration
  ///
  /// Returns the current validation rules and their severity levels.
  /// Can be used to display validation settings in UI.
  Future<ValidationRulesConfig> getValidationRules();

  /// Update validation rules configuration
  ///
  /// Allows customizing which rules are enabled and their severity.
  Future<void> updateValidationRules({
    required ValidationRulesConfig config,
  });
}

/// Configuration for validation rules
class ValidationRulesConfig {
  /// Check completeness (enabled by default)
  final bool checkCompleteness;

  /// Check length constraints (enabled by default)
  final bool checkLength;

  /// Check variable preservation (enabled by default)
  final bool checkVariables;

  /// Check markup preservation (enabled by default)
  final bool checkMarkup;

  /// Check encoding (enabled by default)
  final bool checkEncoding;

  /// Check glossary consistency (enabled if glossary exists)
  final bool checkGlossary;

  /// Check security (enabled by default)
  final bool checkSecurity;

  /// Check truncation (enabled by default)
  final bool checkTruncation;

  /// Check common mistakes (enabled by default)
  final bool checkCommonMistakes;

  /// Maximum allowed length difference ratio (source vs translation)
  /// Default: 2.0 (translation can be up to 2x longer or 0.5x shorter)
  final double maxLengthDifferenceRatio;

  /// Whether to treat warnings as errors
  final bool strictMode;

  const ValidationRulesConfig({
    this.checkCompleteness = true,
    this.checkLength = true,
    this.checkVariables = true,
    this.checkMarkup = true,
    this.checkEncoding = true,
    this.checkGlossary = true,
    this.checkSecurity = true,
    this.checkTruncation = true,
    this.checkCommonMistakes = true,
    this.maxLengthDifferenceRatio = 2.0,
    this.strictMode = false,
  });

  /// Default configuration with all checks enabled
  static const ValidationRulesConfig defaultConfig = ValidationRulesConfig();

  /// Lenient configuration with only critical checks
  static const ValidationRulesConfig lenientConfig = ValidationRulesConfig(
    checkCommonMistakes: false,
    checkTruncation: false,
    maxLengthDifferenceRatio: 3.0,
    strictMode: false,
  );

  /// Strict configuration with all checks as errors
  static const ValidationRulesConfig strictConfig = ValidationRulesConfig(
    strictMode: true,
    maxLengthDifferenceRatio: 1.5,
  );

  @override
  String toString() {
    final enabledChecks = [
      if (checkCompleteness) 'completeness',
      if (checkLength) 'length',
      if (checkVariables) 'variables',
      if (checkMarkup) 'markup',
      if (checkEncoding) 'encoding',
      if (checkGlossary) 'glossary',
      if (checkSecurity) 'security',
      if (checkTruncation) 'truncation',
      if (checkCommonMistakes) 'common mistakes',
    ];
    return 'ValidationRulesConfig(checks: ${enabledChecks.join(", ")}, '
        'strict: $strictMode)';
  }
}
