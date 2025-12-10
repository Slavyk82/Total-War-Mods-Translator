import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/validation/translation_validation_service.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';

void main() {
  late TranslationValidationService service;

  setUp(() {
    service = TranslationValidationService();
  });

  group('TranslationValidationService - Empty Translation Check', () {
    test('should return error when translation is empty but source is not', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello World',
        translatedText: '',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      expect(issues.length, 1);
      expect(issues.first.type, ValidationIssueType.emptyTranslation);
      expect(issues.first.severity, ValidationSeverity.error);
    });

    test('should not return error when both source and translation are empty', () async {
      final result = await service.validateTranslation(
        sourceText: '',
        translatedText: '',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      expect(issues.isEmpty, true);
    });

    test('should not return error when both have content', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello',
        translatedText: 'Bonjour',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final emptyIssues = issues.where((i) => i.type == ValidationIssueType.emptyTranslation);
      expect(emptyIssues.isEmpty, true);
    });
  });

  group('TranslationValidationService - Length Check', () {
    test('should return warning when length difference exceeds 30%', () async {
      final result = await service.validateTranslation(
        sourceText: 'Short',
        translatedText: 'This is a much longer translation that exceeds threshold',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final lengthIssues = issues.where((i) => i.type == ValidationIssueType.lengthDifference);
      expect(lengthIssues.isNotEmpty, true);
      expect(lengthIssues.first.severity, ValidationSeverity.warning);
    });

    test('should not return warning when length difference is below 30%', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello World',
        translatedText: 'Bonjour Monde',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final lengthIssues = issues.where((i) => i.type == ValidationIssueType.lengthDifference);
      expect(lengthIssues.isEmpty, true);
    });

    test('should include metadata with length details', () async {
      final sourceText = 'Test';
      final translatedText = 'A very long translation text here';

      final result = await service.validateTranslation(
        sourceText: sourceText,
        translatedText: translatedText,
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final lengthIssue = issues.firstWhere(
        (i) => i.type == ValidationIssueType.lengthDifference,
      );

      expect(lengthIssue.metadata, isNotNull);
      expect(lengthIssue.metadata!['source_length'], sourceText.length);
      expect(lengthIssue.metadata!['translated_length'], translatedText.length);
    });
  });

  group('TranslationValidationService - Special Characters Check', () {
    test('should detect missing curly brace variables', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello {0}, welcome to {1}',
        translatedText: 'Bonjour, bienvenue',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssues = issues.where((i) => i.type == ValidationIssueType.missingVariables);
      expect(varIssues.isNotEmpty, true);
      expect(varIssues.first.severity, ValidationSeverity.error);
    });

    test('should detect missing printf-style variables', () async {
      final result = await service.validateTranslation(
        sourceText: 'Value: %d, Name: %s',
        translatedText: 'Valeur et Nom',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssues = issues.where((i) => i.type == ValidationIssueType.missingVariables);
      expect(varIssues.isNotEmpty, true);
    });

    test('should detect missing bracketed printf-style variables', () async {
      final result = await service.validateTranslation(
        sourceText: 'Are you sure you want to change profiles? There are pending changes on [%s] that will be lost if you continue.',
        translatedText: 'Êtes-vous sûr de vouloir changer de profil? Des modifications en attente seront perdues si vous continuez.',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssues = issues.where((i) => i.type == ValidationIssueType.missingVariables);
      expect(varIssues.isNotEmpty, true);
      
      // Verify the issue mentions [%s]
      final varIssue = varIssues.first;
      expect(varIssue.description, contains('[%s]'));
    });

    test('should not flag when bracketed printf-style variables are preserved', () async {
      final result = await service.validateTranslation(
        sourceText: 'Changes on [%s] will be lost.',
        translatedText: 'Les modifications sur [%s] seront perdues.',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssues = issues.where((i) => i.type == ValidationIssueType.missingVariables);
      expect(varIssues.isEmpty, true);
    });

    test('should not flag when all variables are present', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello {0} and {1}',
        translatedText: 'Bonjour {0} et {1}',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssues = issues.where((i) => i.type == ValidationIssueType.missingVariables);
      expect(varIssues.isEmpty, true);
    });

    test('should provide auto-fix for missing variables', () async {
      final result = await service.validateTranslation(
        sourceText: 'Test {0}',
        translatedText: 'Test',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssue = issues.firstWhere(
        (i) => i.type == ValidationIssueType.missingVariables,
      );

      expect(varIssue.autoFixable, true);
      expect(varIssue.autoFixValue, isNotNull);
      expect(varIssue.autoFixValue, contains('{0}'));
    });
  });

  group('TranslationValidationService - Whitespace Check', () {
    test('should detect leading whitespace mismatch', () async {
      final result = await service.validateTranslation(
        sourceText: '  Test',
        translatedText: 'Test',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final wsIssues = issues.where((i) => i.type == ValidationIssueType.whitespaceIssue);
      expect(wsIssues.isNotEmpty, true);
    });

    test('should detect trailing whitespace mismatch', () async {
      final result = await service.validateTranslation(
        sourceText: 'Test  ',
        translatedText: 'Test',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final wsIssues = issues.where((i) => i.type == ValidationIssueType.whitespaceIssue);
      expect(wsIssues.isNotEmpty, true);
    });

    test('should detect double spaces', () async {
      final result = await service.validateTranslation(
        sourceText: 'Test',
        translatedText: 'Test  double  space',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final wsIssues = issues.where((i) => i.type == ValidationIssueType.whitespaceIssue);
      expect(wsIssues.isNotEmpty, true);
    });

    test('should provide auto-fix for whitespace issues', () async {
      final result = await service.validateTranslation(
        sourceText: 'Test',
        translatedText: '  Test  ',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final wsIssue = issues.firstWhere(
        (i) => i.type == ValidationIssueType.whitespaceIssue,
      );

      expect(wsIssue.autoFixable, true);
      expect(wsIssue.autoFixValue, 'Test');
    });
  });

  group('TranslationValidationService - Punctuation Check', () {
    test('should detect ending punctuation mismatch', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello World!',
        translatedText: 'Bonjour Monde.',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final punctIssues = issues.where((i) => i.type == ValidationIssueType.punctuationMismatch);
      expect(punctIssues.isNotEmpty, true);
      expect(punctIssues.first.severity, ValidationSeverity.info);
    });

    test('should not flag when punctuation matches', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello World!',
        translatedText: 'Bonjour Monde!',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final punctIssues = issues.where((i) => i.type == ValidationIssueType.punctuationMismatch);
      expect(punctIssues.isEmpty, true);
    });
  });

  group('TranslationValidationService - Case Mismatch Check', () {
    test('should detect case mismatch at start', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello World',
        translatedText: 'bonjour monde',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final caseIssues = issues.where((i) => i.type == ValidationIssueType.caseMismatch);
      expect(caseIssues.isNotEmpty, true);
      expect(caseIssues.first.severity, ValidationSeverity.info);
    });

    test('should not flag when case matches', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello World',
        translatedText: 'Bonjour Monde',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final caseIssues = issues.where((i) => i.type == ValidationIssueType.caseMismatch);
      expect(caseIssues.isEmpty, true);
    });
  });

  group('TranslationValidationService - Numbers Check', () {
    test('should detect missing numbers', () async {
      final result = await service.validateTranslation(
        sourceText: 'Total: 42 items',
        translatedText: 'Total: items',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final numIssues = issues.where((i) => i.type == ValidationIssueType.missingNumbers);
      expect(numIssues.isNotEmpty, true);
      expect(numIssues.first.severity, ValidationSeverity.warning);
    });

    test('should not flag when all numbers are present', () async {
      final result = await service.validateTranslation(
        sourceText: 'Total: 42 items',
        translatedText: 'Total: 42 articles',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final numIssues = issues.where((i) => i.type == ValidationIssueType.missingNumbers);
      expect(numIssues.isEmpty, true);
    });
  });

  group('TranslationValidationService - Multiple Issues', () {
    test('should detect multiple issues in one translation', () async {
      final result = await service.validateTranslation(
        sourceText: 'Hello {0}! Count: 5',
        translatedText: 'bonjour',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      expect(issues.length, greaterThan(1));

      final hasVariableIssue = issues.any((i) => i.type == ValidationIssueType.missingVariables);
      final hasNumberIssue = issues.any((i) => i.type == ValidationIssueType.missingNumbers);
      final hasCaseIssue = issues.any((i) => i.type == ValidationIssueType.caseMismatch);

      expect(hasVariableIssue, true);
      expect(hasNumberIssue, true);
      expect(hasCaseIssue, true);
    });
  });

  group('TranslationValidationService - Auto-Fix', () {
    test('should apply single auto-fix correctly', () async {
      final issue = ValidationIssue(
        type: ValidationIssueType.whitespaceIssue,
        severity: ValidationSeverity.warning,
        description: 'Test',
        autoFixable: true,
        autoFixValue: 'Fixed Text',
      );

      final result = await service.applyAutoFix(
        translatedText: '  Original  ',
        issue: issue,
      );

      expect(result.isOk, true);
      expect(result.unwrap(), 'Fixed Text');
    });

    test('should fail when issue is not auto-fixable', () async {
      final issue = ValidationIssue(
        type: ValidationIssueType.lengthDifference,
        severity: ValidationSeverity.warning,
        description: 'Test',
        autoFixable: false,
      );

      final result = await service.applyAutoFix(
        translatedText: 'Test',
        issue: issue,
      );

      expect(result.isErr, true);
    });

    test('should apply all auto-fixes in correct order', () async {
      final issues = [
        ValidationIssue(
          type: ValidationIssueType.whitespaceIssue,
          severity: ValidationSeverity.warning,
          description: 'Whitespace',
          autoFixable: true,
          autoFixValue: 'Trimmed',
        ),
        ValidationIssue(
          type: ValidationIssueType.missingVariables,
          severity: ValidationSeverity.error,
          description: 'Variables',
          autoFixable: true,
          autoFixValue: 'Trimmed {0}',
        ),
      ];

      final result = await service.applyAllAutoFixes(
        sourceText: 'Source {0}',
        translatedText: '  Original  ',
        issues: issues,
      );

      expect(result.isOk, true);
      final fixed = result.unwrap();
      expect(fixed, contains('{0}'));
    });
  });

  group('TranslationValidationService - Edge Cases', () {
    test('should handle very long texts', () async {
      final longText = 'a' * 10000;

      final result = await service.validateTranslation(
        sourceText: longText,
        translatedText: longText,
      );

      expect(result.isOk, true);
    });

    test('should handle special unicode characters', () async {
      final result = await service.validateTranslation(
        sourceText: 'Test 中文 🎉',
        translatedText: 'Test 中文 🎉',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      expect(issues.isEmpty, true);
    });

    test('should handle mixed variable types', () async {
      final result = await service.validateTranslation(
        sourceText: 'Test {0} and %s and \${var}',
        translatedText: 'Test {0} and %s and \${var}',
      );

      expect(result.isOk, true);
      final issues = result.unwrap();
      final varIssues = issues.where((i) => i.type == ValidationIssueType.missingVariables);
      expect(varIssues.isEmpty, true);
    });
  });
}
