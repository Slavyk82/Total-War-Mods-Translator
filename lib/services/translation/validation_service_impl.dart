import 'dart:convert';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/validation_result.dart' as common;
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Implementation of translation validation service
///
/// Performs comprehensive validation checks on translations:
/// - Completeness, length, variables, markup
/// - Encoding, glossary, security, truncation
/// - Common mistakes detection
class ValidationServiceImpl implements IValidationService {
  ValidationRulesConfig _config = ValidationRulesConfig.defaultConfig;

  @override
  Future<Result<common.ValidationResult, ValidationException>>
      validateTranslation({
    required String sourceText,
    required String translatedText,
    required String key,
    Map<String, String>? glossaryTerms,
    int? maxLength,
  }) async {
    try {
      final errors = <String>[];
      final warnings = <String>[];

      // Run all enabled validation checks
      if (_config.checkCompleteness) {
        final result = await checkCompleteness(
          translatedText: translatedText,
          key: key,
        );
        if (result != null) {
          _addError(errors, warnings, result, _config.strictMode);
        }
      }

      if (_config.checkLength) {
        final result = await checkLength(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
          maxLength: maxLength,
        );
        if (result != null) {
          _addError(errors, warnings, result, _config.strictMode);
        }
      }

      if (_config.checkVariables) {
        final result = await checkVariablePreservation(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
        );
        if (result != null) {
          _addError(errors, warnings, result, false); // Always error
        }
      }

      if (_config.checkMarkup) {
        final result = await checkMarkupPreservation(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
        );
        if (result != null) {
          _addError(errors, warnings, result, false); // Always error
        }
      }

      if (_config.checkEncoding) {
        final result = await checkEncoding(
          translatedText: translatedText,
          key: key,
        );
        if (result != null) {
          _addError(errors, warnings, result, false); // Always error
        }
      }

      if (_config.checkGlossary && glossaryTerms != null) {
        final result = await checkGlossaryConsistency(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
          glossaryTerms: glossaryTerms,
        );
        if (result != null) {
          _addError(errors, warnings, result, _config.strictMode);
        }
      }

      if (_config.checkSecurity) {
        final result = await checkSecurity(
          translatedText: translatedText,
          key: key,
        );
        if (result != null) {
          _addError(errors, warnings, result, false); // Always error
        }
      }

      if (_config.checkTruncation) {
        final result = await checkTruncation(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
        );
        if (result != null) {
          _addError(errors, warnings, result, _config.strictMode);
        }
      }

      if (_config.checkCommonMistakes) {
        final mistakes = await checkCommonMistakes(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
        );
        for (final mistake in mistakes) {
          _addError(errors, warnings, mistake, _config.strictMode);
        }
      }

      final validationResult = common.ValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
      );

      return Ok(validationResult);
    } catch (e, stackTrace) {
      return Err(
        ValidationException(
          'Validation failed for key $key: ${e.toString()}',
          [],
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<Map<String, common.ValidationResult>, ValidationException>>
      validateBatch({
    required Map<String, String> translations,
    required Map<String, String> sourcesMap,
    Map<String, String>? glossaryTerms,
    int? maxLength,
  }) async {
    try {
      final results = <String, common.ValidationResult>{};

      // Validate each translation
      for (final entry in translations.entries) {
        final key = entry.key;
        final translatedText = entry.value;
        final sourceText = sourcesMap[key];

        if (sourceText == null) {
          results[key] = common.ValidationResult(
            isValid: false,
            errors: ['Source text not found for key: $key'],
            warnings: [],
          );
          continue;
        }

        final result = await validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
          key: key,
          glossaryTerms: glossaryTerms,
          maxLength: maxLength,
        );

        if (result.isOk) {
          results[key] = result.value;
        } else {
          results[key] = common.ValidationResult(
            isValid: false,
            errors: [result.error.message],
            warnings: [],
          );
        }
      }

      return Ok(results);
    } catch (e, stackTrace) {
      return Err(
        ValidationException(
          'Batch validation failed: ${e.toString()}',
          [],
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<ValidationError?> checkCompleteness({
    required String translatedText,
    required String key,
  }) async {
    if (translatedText.trim().isEmpty) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Translation is empty',
        field: key,
      );
    }
    return null;
  }

  @override
  Future<ValidationError?> checkLength({
    required String sourceText,
    required String translatedText,
    required String key,
    int? maxLength,
  }) async {
    // Check hard limit if provided
    if (maxLength != null && translatedText.length > maxLength) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Translation exceeds maximum length '
            '(${translatedText.length} > $maxLength)',
        field: key,
      );
    }

    // Check relative length difference
    final sourceLength = sourceText.length;
    final translatedLength = translatedText.length;

    if (sourceLength == 0) return null;

    final ratio = translatedLength / sourceLength;
    final maxRatio = _config.maxLengthDifferenceRatio;

    if (ratio > maxRatio || ratio < (1 / maxRatio)) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Translation length differs significantly from source '
            '(source: $sourceLength, translation: $translatedLength, '
            'ratio: ${ratio.toStringAsFixed(2)})',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<ValidationError?> checkVariablePreservation({
    required String sourceText,
    required String translatedText,
    required String key,
  }) async {
    // Extract variables from source
    final sourceVars = _extractVariables(sourceText);
    final translatedVars = _extractVariables(translatedText);

    // Debug logging for variable extraction
    if (sourceVars.any((v) => v.startsWith('{{'))) {
      print('[DEBUG] Variable extraction for key: $key');
      print('[DEBUG] Source double-brace vars: ${sourceVars.where((v) => v.startsWith('{{')).toList()}');
      print('[DEBUG] Translated double-brace vars: ${translatedVars.where((v) => v.startsWith('{{')).toList()}');
    }

    // Check if all source variables are in translation
    final missingVars = sourceVars.where((v) => !translatedVars.contains(v)).toList();
    if (missingVars.isNotEmpty) {
      // Separate double-brace templates from simple variables
      final missingSimpleVars = missingVars.where((v) => !v.startsWith('{{')).toList();
      final missingTemplates = missingVars.where((v) => v.startsWith('{{')).toList();

      // Simple variables missing = error (e.g., {0}, %s must be preserved exactly)
      if (missingSimpleVars.isNotEmpty) {
        return ValidationError(
          severity: ValidationSeverity.error,
          message: 'Missing variables in translation: ${missingSimpleVars.join(', ')}',
          field: key,
        );
      }

      // Double-brace templates modified = warning only
      // These may contain display strings that should be translated
      if (missingTemplates.isNotEmpty) {
        return ValidationError(
          severity: ValidationSeverity.warning,
          message: 'Template expressions modified (may be intentional for display strings): ${missingTemplates.length} template(s)',
          field: key,
        );
      }
    }

    // Check if translation has extra variables
    final extraVars = translatedVars.where((v) => !sourceVars.contains(v));
    if (extraVars.isNotEmpty) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Extra variables in translation: ${extraVars.join(', ')}',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<ValidationError?> checkMarkupPreservation({
    required String sourceText,
    required String translatedText,
    required String key,
  }) async {
    // Extract markup tags from source
    final sourceTags = _extractMarkupTags(sourceText);
    final translatedTags = _extractMarkupTags(translatedText);

    // Check source tag balance first (data quality check)
    if (!_areTagsBalanced(sourceTags)) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Source text has unbalanced markup tags - may cause translation issues',
        field: key,
      );
    }

    // Check if tags match
    if (sourceTags.length != translatedTags.length) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Markup tag count mismatch '
            '(source: ${sourceTags.length}, translation: ${translatedTags.length})',
        field: key,
      );
    }

    // Check tag balance in translation
    if (!_areTagsBalanced(translatedTags)) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Unbalanced markup tags in translation',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<ValidationError?> checkEncoding({
    required String translatedText,
    required String key,
  }) async {
    // Check for invalid UTF-8 characters
    if (translatedText.contains('�')) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Invalid encoding: contains replacement character (�)',
        field: key,
      );
    }

    // Check for control characters (except common ones like \n, \t)
    final controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');
    if (controlChars.hasMatch(translatedText)) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Contains invalid control characters',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<ValidationError?> checkGlossaryConsistency({
    required String sourceText,
    required String translatedText,
    required String key,
    required Map<String, String> glossaryTerms,
  }) async {
    final violations = <String>[];

    for (final entry in glossaryTerms.entries) {
      final sourceTerm = entry.key;
      final expectedTranslation = entry.value;

      // Check if source contains this term
      if (sourceText.contains(sourceTerm)) {
        // Translation should contain the glossary translation
        if (!translatedText.contains(expectedTranslation)) {
          violations.add('$sourceTerm → $expectedTranslation');
        }
      }
    }

    if (violations.isNotEmpty) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Glossary terms not used: ${violations.join(', ')}',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<ValidationError?> checkSecurity({
    required String translatedText,
    required String key,
  }) async {
    // Check for SQL injection patterns
    if (RegExp(r"('|--|\bOR\b|\bAND\b)", caseSensitive: false)
        .hasMatch(translatedText)) {
      if (RegExp(r"'\s*(OR|AND)\s*'", caseSensitive: false)
          .hasMatch(translatedText)) {
        return ValidationError(
          severity: ValidationSeverity.error,
          message: 'Potential SQL injection pattern detected',
          field: key,
        );
      }
    }

    // Check for script injection
    if (translatedText.contains('<script') ||
        translatedText.contains('javascript:')) {
      return ValidationError(
        severity: ValidationSeverity.error,
        message: 'Potential script injection detected',
        field: key,
      );
    }

    // Check for path traversal
    if (translatedText.contains('../') || translatedText.contains('..\\')) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Potential path traversal pattern detected',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<ValidationError?> checkTruncation({
    required String sourceText,
    required String translatedText,
    required String key,
  }) async {
    // Check for ellipsis at end
    if (translatedText.trimRight().endsWith('...') &&
        !sourceText.trimRight().endsWith('...')) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Translation may be truncated (ends with ...)',
        field: key,
      );
    }

    // Check if significantly shorter than source
    if (translatedText.length < sourceText.length * 0.3) {
      return ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Translation is significantly shorter than source '
            '(may be truncated)',
        field: key,
      );
    }

    return null;
  }

  @override
  Future<List<ValidationError>> checkCommonMistakes({
    required String sourceText,
    required String translatedText,
    required String key,
  }) async {
    final mistakes = <ValidationError>[];

    // Check for repeated words
    final repeatedWords = RegExp(r'\b(\w+)\s+\1\b', caseSensitive: false);
    if (repeatedWords.hasMatch(translatedText)) {
      mistakes.add(ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Repeated word detected',
        field: key,
      ));
    }

    // Check for missing ending punctuation
    final endPunctuationPattern = RegExp(r'[.!?]$');
    if (endPunctuationPattern.hasMatch(sourceText.trimRight()) &&
        !endPunctuationPattern.hasMatch(translatedText.trimRight())) {
      mistakes.add(ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Missing ending punctuation',
        field: key,
      ));
    }

    // Check for number mismatches
    final sourceNumbers = _extractNumbers(sourceText);
    final translatedNumbers = _extractNumbers(translatedText);
    if (sourceNumbers.isNotEmpty && sourceNumbers != translatedNumbers) {
      mistakes.add(ValidationError(
        severity: ValidationSeverity.warning,
        message: 'Numbers don\'t match source',
        field: key,
      ));
    }

    return mistakes;
  }

  @override
  Future<Result<Map<String, String>, ValidationException>> validateLlmResponse({
    required String jsonResponse,
    required List<String> expectedKeys,
  }) async {
    try {
      // Parse JSON
      final Map<String, dynamic> parsed;
      try {
        parsed = json.decode(jsonResponse) as Map<String, dynamic>;
      } catch (e) {
        return Err(
          ValidationException(
            'Invalid JSON response from LLM: ${e.toString()}',
            [],
            error: e,
          ),
        );
      }

      // Check for translations array
      if (!parsed.containsKey('translations')) {
        return Err(
          ValidationException(
            'LLM response missing "translations" field',
            [],
          ),
        );
      }

      final translations = parsed['translations'];
      if (translations is! List) {
        return Err(
          ValidationException(
            'LLM response "translations" is not a list',
            [],
          ),
        );
      }

      // Extract translations into map
      final result = <String, String>{};
      for (final item in translations) {
        if (item is! Map<String, dynamic>) continue;

        final key = item['key'] as String?;
        final translation = item['translation'] as String?;

        if (key != null && translation != null) {
          result[key] = translation;
        }
      }

      // Check if all expected keys are present
      final missingKeys =
          expectedKeys.where((key) => !result.containsKey(key)).toList();
      if (missingKeys.isNotEmpty) {
        return Err(
          ValidationException(
            'LLM response missing translations for keys: ${missingKeys.join(', ')}',
            [],
          ),
        );
      }

      return Ok(result);
    } catch (e, stackTrace) {
      return Err(
        ValidationException(
          'Failed to validate LLM response: ${e.toString()}',
          [],
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<ValidationRulesConfig> getValidationRules() async {
    return _config;
  }

  @override
  Future<void> updateValidationRules({
    required ValidationRulesConfig config,
  }) async {
    _config = config;
  }

  /// Add error or warning based on severity and strict mode
  void _addError(
    List<String> errors,
    List<String> warnings,
    ValidationError error,
    bool treatWarningsAsErrors,
  ) {
    if (error.severity == ValidationSeverity.error ||
        (treatWarningsAsErrors &&
            error.severity == ValidationSeverity.warning)) {
      errors.add(error.message);
    } else {
      warnings.add(error.message);
    }
  }

  /// Extract variables from text
  ///
  /// Supports:
  /// - {{expression}} (Total War double-brace templates)
  /// - {0}, {1}, {2} (positional)
  /// - {name}, {count} (named)
  /// - %s, %d, %f (printf-style)
  /// - [%s], [%d], [%f] (bracketed printf-style)
  /// - $var, ${var} (template-style)
  List<String> _extractVariables(String text) {
    final variables = <String>[];

    // Total War double-brace templates: {{CcoCampaignEventDilemma:GetIfElse(...)}}
    // These can contain nested braces, so match {{ until }}
    // Pattern: {{ followed by any char except }} until }}
    final doubleBracePattern = RegExp(r'\{\{(?:[^}]|\}(?!\}))*\}\}');
    final doubleBraceMatches = doubleBracePattern.allMatches(text).toList();
    variables.addAll(
      doubleBraceMatches.map((m) => m.group(0)!),
    );

    // Build a set of ranges covered by double-brace matches to avoid double-counting
    final doubleBraceRanges = doubleBraceMatches
        .map((m) => (start: m.start, end: m.end))
        .toList();

    // Positional and named placeholders: {0}, {name}
    // Skip matches that fall within double-brace ranges
    final bracePattern = RegExp(r'\{([^}]+)\}');
    for (final match in bracePattern.allMatches(text)) {
      final isInsideDoubleBrace = doubleBraceRanges.any(
        (r) => match.start >= r.start && match.end <= r.end,
      );
      if (!isInsideDoubleBrace) {
        variables.add(match.group(0)!);
      }
    }

    // Bracketed printf-style: [%s], [%d], [%f], etc.
    // Must be checked BEFORE single printf and BBCode patterns to avoid conflicts
    final bracketedPrintfPattern = RegExp(r'\[%[sdf]\]');
    variables.addAll(
      bracketedPrintfPattern.allMatches(text).map((m) => m.group(0)!),
    );

    // Printf-style: %s, %d, %f, etc.
    final printfPattern = RegExp(r'%[sdf]');
    variables.addAll(
      printfPattern.allMatches(text).map((m) => m.group(0)!),
    );

    // Template-style: $var, ${var}
    final templatePattern = RegExp(r'\$\{?(\w+)\}?');
    variables.addAll(
      templatePattern.allMatches(text).map((m) => m.group(0)!),
    );

    return variables;
  }

  /// Extract markup tags from text
  ///
  /// Supports:
  /// - XML: &lt;tag&gt;, &lt;/tag&gt;
  /// - BBCode: [tag], [/tag]
  /// - Double-bracket: [[tag]], [[/tag]]
  ///
  /// Excludes printf-style placeholders like [%s] which are variables, not tags
  List<String> _extractMarkupTags(String text) {
    final tags = <String>[];

    // XML tags: <tag>, </tag>, <tag attr="value">
    final xmlPattern = RegExp(r'<[^>]+>');
    tags.addAll(
      xmlPattern.allMatches(text).map((m) => m.group(0)!),
    );

    // Double-bracket tags: [[tag:value]], [[/tag]]
    // Must be checked BEFORE single-bracket pattern to avoid partial matches
    final doubleBracketPattern = RegExp(r'\[\[[^\]]+\]\]');
    tags.addAll(
      doubleBracketPattern.allMatches(text).map((m) => m.group(0)!),
    );

    // Single BBCode tags: [tag], [/tag], [tag=value]
    // Use negative lookbehind/lookahead to avoid matching double brackets
    // Match [ but not [[, and ] but not ]]
    // Exclude [%s], [%d], [%f] which are printf-style placeholders, not tags
    final bbcodePattern = RegExp(r'(?<!\[)\[[^\[\]]+\](?!\])');
    final matches = bbcodePattern.allMatches(text);
    
    for (final match in matches) {
      final tag = match.group(0)!;
      // Skip if this is a bracketed printf placeholder
      if (!RegExp(r'^\[%[sdf]\]$').hasMatch(tag)) {
        tags.add(tag);
      }
    }

    return tags;
  }

  /// Check if markup tags are balanced
  bool _areTagsBalanced(List<String> tags) {
    final stack = <String>[];

    for (final tag in tags) {
      // Self-closing tags (e.g., <br/>, <img/>)
      if (tag.endsWith('/>')) {
        continue; // Self-closing, no need to track
      }

      // Closing tags (including double-bracket [[/tag]])
      if (tag.startsWith('</') || tag.startsWith('[/') || tag.startsWith('[[/')) {
        final tagName = _extractTagName(tag);
        if (stack.isEmpty) return false;

        final expectedOpening = stack.removeLast();
        final expectedName = _extractTagName(expectedOpening);

        // Check if closing tag matches opening tag
        if (tagName != expectedName) {
          return false;
        }
      } else {
        // Opening tag (including tags with attributes like [tag=value])
        stack.add(tag);
      }
    }

    return stack.isEmpty;
  }

  /// Extract tag name from a markup tag
  ///
  /// Examples:
  /// - <b> -> b
  /// - </b> -> b
  /// - <div class="foo"> -> div
  /// - <color=#FF0000> -> color
  /// - [color=red] -> color
  /// - [/color] -> color
  /// - [[col:red]] -> [col (opening bracket)
  /// - [[/col]] -> [/col (closing bracket)
  String _extractTagName(String tag) {
    // XML/HTML tags
    if (tag.startsWith('<')) {
      // Remove < and > and / if present
      var name = tag.substring(1);
      if (name.startsWith('/')) {
        name = name.substring(1);
      }
      if (name.endsWith('>')) {
        name = name.substring(0, name.length - 1);
      }
      // Remove self-closing marker
      if (name.endsWith('/')) {
        name = name.substring(0, name.length - 1);
      }
      // Remove attributes (everything after first space or =)
      var cutIndex = name.indexOf(' ');
      final equalsIndex = name.indexOf('=');
      if (equalsIndex != -1 && (cutIndex == -1 || equalsIndex < cutIndex)) {
        cutIndex = equalsIndex;
      }
      if (cutIndex != -1) {
        name = name.substring(0, cutIndex);
      }
      return name.trim();
    }

    // BBCode tags (including double-bracket style [[tag]])
    if (tag.startsWith('[')) {
      // Remove outer brackets
      var name = tag.substring(1);
      if (name.endsWith(']')) {
        name = name.substring(0, name.length - 1);
      }

      // For double-bracket tags: [[col:red]] -> [col:red], [[/col]] -> [/col]
      // We'll keep the inner bracket as part of the tag name

      // First, handle the slash for closing tags
      // [[/col]] -> [col] (after outer bracket removal we have [/col])
      if (name.startsWith('[/')) {
        name = name.substring(2); // Remove [/
        // Also remove trailing ] for double-bracket tags
        if (name.endsWith(']')) {
          name = name.substring(0, name.length - 1);
        }
      } else if (name.startsWith('/')) {
        name = name.substring(1); // Remove /
      } else if (name.startsWith('[')) {
        name = name.substring(1); // Remove [ for double-bracket opening
        // Also remove trailing ] for double-bracket tags
        if (name.endsWith(']')) {
          name = name.substring(0, name.length - 1);
        }
      }

      // Remove attributes (everything after = or :)
      var cutIndex = name.indexOf('=');
      final colonIndex = name.indexOf(':');
      if (colonIndex != -1 && (cutIndex == -1 || colonIndex < cutIndex)) {
        cutIndex = colonIndex;
      }
      if (cutIndex != -1) {
        name = name.substring(0, cutIndex);
      }

      return name.trim();
    }

    return tag;
  }

  /// Extract numbers from text
  List<String> _extractNumbers(String text) {
    final numberPattern = RegExp(r'\b\d+\b');
    return numberPattern.allMatches(text).map((m) => m.group(0)!).toList();
  }
}
