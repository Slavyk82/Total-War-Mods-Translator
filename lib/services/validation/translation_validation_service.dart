import 'package:twmt/services/validation/i_translation_validation_service.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';

/// Implementation of translation validation service
///
/// Performs various quality checks on translations to identify issues
class TranslationValidationService implements ITranslationValidationService {
  /// Regular expression to find variables in text
  /// Supports: {0}, %s, [%s], ${var}
  static final _variablePattern = RegExp(r'\{(\d+)\}|\[%[sdifgc]\]|%[sdifgc]|\$\{[\w]+\}');

  /// Regular expression to find numbers in text
  static final _numberPattern = RegExp(r'\d+');

  /// Threshold for length difference warning (100%)
  /// Translations from English to Romance languages (French, Spanish, Italian)
  /// are typically 15-30% longer, and can be 50-100% longer for short UI text
  static const _lengthDifferenceThreshold = 1.0;

  @override
  Future<Result<List<ValidationIssue>, ServiceException>>
      validateTranslation({
    required String sourceText,
    required String translatedText,
    String? context,
  }) async {
    try {
      final issues = <ValidationIssue>[];

      // Run all validation checks
      issues.addAll(_checkEmpty(sourceText, translatedText));
      issues.addAll(_checkLength(sourceText, translatedText));
      issues.addAll(_checkSpecialCharacters(sourceText, translatedText));
      issues.addAll(_checkWhitespace(sourceText, translatedText));
      issues.addAll(_checkPunctuation(sourceText, translatedText));
      issues.addAll(_checkCaseMismatch(sourceText, translatedText));
      issues.addAll(_checkNumbers(sourceText, translatedText));

      return Ok(issues);
    } catch (e, stackTrace) {
      return Err(
        ServiceException(
          'Validation failed',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String, ServiceException>> applyAutoFix({
    required String translatedText,
    required ValidationIssue issue,
  }) async {
    try {
      if (!issue.autoFixable || issue.autoFixValue == null) {
        return Err(
          ServiceException('Issue is not auto-fixable: ${issue.type}'),
        );
      }

      return Ok(issue.autoFixValue!);
    } catch (e, stackTrace) {
      return Err(
        ServiceException(
          'Failed to apply auto-fix',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String, ServiceException>> applyAllAutoFixes({
    required String sourceText,
    required String translatedText,
    required List<ValidationIssue> issues,
  }) async {
    try {
      String fixedText = translatedText;

      // Apply fixes in order of priority
      // 1. Trim whitespace
      final whitespaceIssue = issues.firstWhere(
        (issue) =>
            issue.type == ValidationIssueType.whitespaceIssue &&
            issue.autoFixable,
        orElse: () => const ValidationIssue(
          type: ValidationIssueType.whitespaceIssue,
          severity: ValidationSeverity.info,
          description: '',
        ),
      );

      if (whitespaceIssue.autoFixable && whitespaceIssue.autoFixValue != null) {
        fixedText = whitespaceIssue.autoFixValue!;
      }

      // 2. Add missing variables
      final variableIssue = issues.firstWhere(
        (issue) =>
            issue.type == ValidationIssueType.missingVariables &&
            issue.autoFixable,
        orElse: () => const ValidationIssue(
          type: ValidationIssueType.missingVariables,
          severity: ValidationSeverity.error,
          description: '',
        ),
      );

      if (variableIssue.autoFixable && variableIssue.autoFixValue != null) {
        fixedText = variableIssue.autoFixValue!;
      }

      return Ok(fixedText);
    } catch (e, stackTrace) {
      return Err(
        ServiceException(
          'Failed to apply all auto-fixes',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Check if translation is empty when source has text
  List<ValidationIssue> _checkEmpty(String sourceText, String translatedText) {
    if (sourceText.trim().isNotEmpty && translatedText.trim().isEmpty) {
      return [
        const ValidationIssue(
          type: ValidationIssueType.emptyTranslation,
          severity: ValidationSeverity.error,
          description: 'Translation is empty but source text is not',
          suggestion: 'Provide a translation for this text',
          autoFixable: false,
        ),
      ];
    }
    return [];
  }

  /// Check length difference between source and translation
  List<ValidationIssue> _checkLength(String sourceText, String translatedText) {
    if (sourceText.trim().isEmpty || translatedText.trim().isEmpty) {
      return [];
    }

    final sourceLength = sourceText.length;
    final translatedLength = translatedText.length;
    final difference = (sourceLength - translatedLength).abs();
    final percentDifference = difference / sourceLength;

    // Only flag if translation is significantly different
    // 100% threshold allows for natural language expansion (English->French typically 15-30%, can be 50-100% for short text)
    if (percentDifference > _lengthDifferenceThreshold) {
      final percent = (percentDifference * 100).round();
      
      // Determine if translation is shorter or longer
      final lengthStatus = translatedLength < sourceLength ? 'shorter' : 'longer';
      
      return [
        ValidationIssue(
          type: ValidationIssueType.lengthDifference,
          severity: ValidationSeverity.warning,
          description: 'Length difference: $percent% ($lengthStatus)',
          suggestion:
              'Source: $sourceLength characters, Translation: $translatedLength characters. '
              'Translation is $lengthStatus than expected. '
              'Review for accuracy - text might be incomplete${translatedLength < sourceLength ? '' : ' or too verbose'}.',
          autoFixable: false,
          metadata: {
            'source_length': sourceLength,
            'translated_length': translatedLength,
            'difference_percent': percent,
          },
        ),
      ];
    }
    return [];
  }

  /// Check for missing variables and special characters
  List<ValidationIssue> _checkSpecialCharacters(
    String sourceText,
    String translatedText,
  ) {
    final sourceVariables = _variablePattern
        .allMatches(sourceText)
        .map((m) => m.group(0)!)
        .toSet();

    final translatedVariables = _variablePattern
        .allMatches(translatedText)
        .map((m) => m.group(0)!)
        .toSet();

    final missingVariables =
        sourceVariables.difference(translatedVariables).toList();

    if (missingVariables.isNotEmpty) {
      final missingVarsStr = missingVariables.join(', ');

      return [
        ValidationIssue(
          type: ValidationIssueType.missingVariables,
          severity: ValidationSeverity.error,
          description: 'Missing variables: $missingVarsStr',
          suggestion:
              'Ensure all variables from the source text are present in the translation. '
              'Variables: $missingVarsStr',
          autoFixable: true,
          autoFixValue: '$translatedText ${missingVariables.join(' ')}',
          metadata: {
            'missing_variables': missingVariables,
          },
        ),
      ];
    }

    return [];
  }

  /// Check for whitespace issues
  List<ValidationIssue> _checkWhitespace(
    String sourceText,
    String translatedText,
  ) {
    final issues = <ValidationIssue>[];

    // Check leading whitespace
    final sourceLeading = sourceText.length - sourceText.trimLeft().length;
    final translatedLeading =
        translatedText.length - translatedText.trimLeft().length;

    // Check trailing whitespace
    final sourceTrailing = sourceText.length - sourceText.trimRight().length;
    final translatedTrailing =
        translatedText.length - translatedText.trimRight().length;

    if (sourceLeading != translatedLeading ||
        sourceTrailing != translatedTrailing) {
      issues.add(
        ValidationIssue(
          type: ValidationIssueType.whitespaceIssue,
          severity: ValidationSeverity.warning,
          description: 'Leading or trailing whitespace mismatch',
          suggestion: 'Adjust whitespace to match source text',
          autoFixable: true,
          autoFixValue: translatedText.trim(),
          metadata: {
            'source_leading': sourceLeading,
            'translated_leading': translatedLeading,
            'source_trailing': sourceTrailing,
            'translated_trailing': translatedTrailing,
          },
        ),
      );
    }

    // Check for double spaces
    if (translatedText.contains('  ')) {
      issues.add(
        ValidationIssue(
          type: ValidationIssueType.whitespaceIssue,
          severity: ValidationSeverity.warning,
          description: 'Contains double spaces',
          suggestion: 'Replace double spaces with single spaces',
          autoFixable: true,
          autoFixValue: translatedText.replaceAll(RegExp(r'\s+'), ' '),
        ),
      );
    }

    return issues;
  }

  /// Check for punctuation mismatch
  List<ValidationIssue> _checkPunctuation(
    String sourceText,
    String translatedText,
  ) {
    if (sourceText.trim().isEmpty || translatedText.trim().isEmpty) {
      return [];
    }

    final sourcePunctuation = _getEndingPunctuation(sourceText);
    final translatedPunctuation = _getEndingPunctuation(translatedText);

    if (sourcePunctuation != null &&
        translatedPunctuation != null &&
        sourcePunctuation != translatedPunctuation) {
      return [
        ValidationIssue(
          type: ValidationIssueType.punctuationMismatch,
          severity: ValidationSeverity.info,
          description: 'Ending punctuation mismatch',
          suggestion:
              'Source ends with "$sourcePunctuation" but translation ends with "$translatedPunctuation"',
          autoFixable: false,
          metadata: {
            'source_punctuation': sourcePunctuation,
            'translated_punctuation': translatedPunctuation,
          },
        ),
      ];
    }

    return [];
  }

  /// Get ending punctuation of a text
  String? _getEndingPunctuation(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final lastChar = trimmed[trimmed.length - 1];
    if (['.', '!', '?', ',', ';', ':'].contains(lastChar)) {
      return lastChar;
    }

    return null;
  }

  /// Check for case mismatch
  List<ValidationIssue> _checkCaseMismatch(
    String sourceText,
    String translatedText,
  ) {
    if (sourceText.trim().isEmpty || translatedText.trim().isEmpty) {
      return [];
    }

    final sourceFirstChar = sourceText.trim()[0];
    final translatedFirstChar = translatedText.trim()[0];

    final sourceIsUpper = sourceFirstChar == sourceFirstChar.toUpperCase();
    final translatedIsUpper =
        translatedFirstChar == translatedFirstChar.toUpperCase();

    if (sourceIsUpper && !translatedIsUpper) {
      return [
        const ValidationIssue(
          type: ValidationIssueType.caseMismatch,
          severity: ValidationSeverity.info,
          description: 'Source starts with uppercase, translation with lowercase',
          suggestion: 'Consider capitalizing the first letter of the translation',
          autoFixable: false,
        ),
      ];
    }

    return [];
  }

  /// Check for missing or modified numbers
  ///
  /// Detects:
  /// - Numbers that are completely missing from translation
  /// - Numbers that have been reformatted (e.g., "13140" → "13 140")
  List<ValidationIssue> _checkNumbers(String sourceText, String translatedText) {
    final issues = <ValidationIssue>[];

    final sourceNumbers =
        _numberPattern.allMatches(sourceText).map((m) => m.group(0)!).toList();

    final translatedNumbers = _numberPattern
        .allMatches(translatedText)
        .map((m) => m.group(0)!)
        .toList();

    // Check for exact number preservation (important for color codes, IDs, etc.)
    final sourceNumbersSet = sourceNumbers.toSet();
    final translatedNumbersSet = translatedNumbers.toSet();

    final missingNumbers = sourceNumbersSet.difference(translatedNumbersSet).toList();

    // Check if missing numbers might have been reformatted with separators
    // e.g., "13140" → "13 140" or "1000000" → "1 000 000"
    final modifiedNumbers = <String, String>{};

    for (final sourceNum in missingNumbers.toList()) {
      // Check if the number might have been split by spaces/separators
      // Remove all spaces, non-breaking spaces, and common separators from translated text
      final normalizedTranslated = translatedText
          .replaceAll(' ', '')
          .replaceAll('\u00A0', '') // non-breaking space
          .replaceAll('\u202F', '') // narrow non-breaking space
          .replaceAll(',', '')
          .replaceAll('.', '');

      if (normalizedTranslated.contains(sourceNum)) {
        // The number exists when separators are removed - it was reformatted
        // Try to find the original formatted version in the translation
        final formattedVersion = _findFormattedNumber(translatedText, sourceNum);
        if (formattedVersion != null && formattedVersion != sourceNum) {
          modifiedNumbers[sourceNum] = formattedVersion;
          missingNumbers.remove(sourceNum);
        }
      }
    }

    // Report modified numbers as errors (important for color codes, IDs)
    if (modifiedNumbers.isNotEmpty) {
      final modifiedStr = modifiedNumbers.entries
          .map((e) => '"${e.key}" → "${e.value}"')
          .join(', ');

      issues.add(
        ValidationIssue(
          type: ValidationIssueType.modifiedNumbers,
          severity: ValidationSeverity.error,
          description: 'Numbers reformatted: $modifiedStr',
          suggestion:
              'Numbers must be preserved exactly as in source text. '
              'Do not add thousand separators or spaces. '
              'These may be color codes, IDs, or other technical values.',
          autoFixable: true,
          autoFixValue: _fixModifiedNumbers(translatedText, modifiedNumbers),
          metadata: {
            'modified_numbers': modifiedNumbers,
          },
        ),
      );
    }

    // Report truly missing numbers
    if (missingNumbers.isNotEmpty) {
      final missingNumStr = missingNumbers.join(', ');
      issues.add(
        ValidationIssue(
          type: ValidationIssueType.missingNumbers,
          severity: ValidationSeverity.warning,
          description: 'Missing numbers: $missingNumStr',
          suggestion:
              'Ensure all numbers from the source text are present in the translation',
          autoFixable: false,
          metadata: {
            'missing_numbers': missingNumbers,
          },
        ),
      );
    }

    return issues;
  }

  /// Find the formatted version of a number in text
  /// e.g., find "13 140" when looking for "13140"
  String? _findFormattedNumber(String text, String number) {
    // Build a regex pattern that matches the number with optional separators
    // For "13140", match "1[sep]?3[sep]?1[sep]?4[sep]?0"
    final separatorPattern = r'[\s\u00A0\u202F,.]?';
    final patternStr = number.split('').join(separatorPattern);
    final pattern = RegExp(patternStr);

    final match = pattern.firstMatch(text);
    if (match != null) {
      final found = match.group(0)!;
      // Only return if it actually contains separators (is different from source)
      if (found != number && found.replaceAll(RegExp(r'[\s\u00A0\u202F,.]'), '') == number) {
        return found;
      }
    }
    return null;
  }

  /// Fix modified numbers by replacing formatted versions with original
  String _fixModifiedNumbers(String text, Map<String, String> modifiedNumbers) {
    String result = text;
    for (final entry in modifiedNumbers.entries) {
      final original = entry.key;
      final formatted = entry.value;
      result = result.replaceAll(formatted, original);
    }
    return result;
  }
}
