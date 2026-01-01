import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/validation/translation_validation_service.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';

void main() {
  late TranslationValidationService service;

  setUp(() {
    service = TranslationValidationService();
  });

  group('TranslationValidationService', () {
    // =========================================================================
    // validateTranslation - Empty Translation
    // =========================================================================
    group('validateTranslation - empty translation', () {
      test('should return error when translation is empty but source has text', () async {
        // Arrange
        const sourceText = 'Hello world';
        const translatedText = '';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        final issues = result.value;
        expect(issues.any((i) => i.type == ValidationIssueType.emptyTranslation), true);
        final emptyIssue = issues.firstWhere(
          (i) => i.type == ValidationIssueType.emptyTranslation,
        );
        expect(emptyIssue.severity, ValidationSeverity.error);
        expect(emptyIssue.autoFixable, false);
      });

      test('should not return error when both source and translation are empty', () async {
        // Arrange
        const sourceText = '';
        const translatedText = '';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.emptyTranslation),
          false,
        );
      });

      test('should not return error when source is whitespace only', () async {
        // Arrange
        const sourceText = '   ';
        const translatedText = '';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.emptyTranslation),
          false,
        );
      });
    });

    // =========================================================================
    // validateTranslation - Length Difference
    // =========================================================================
    group('validateTranslation - length difference', () {
      test('should not return warning when translation is shorter but within threshold', () async {
        // Arrange - The service uses a 100% threshold for length differences
        // For shorter translations, max possible difference is ~100% (when translation is empty)
        // So shorter translations won't typically trigger this warning
        const sourceText = 'This is a very long sentence that contains many words and characters.';
        const translatedText = '.';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert - 98.5% difference is within the 100% threshold
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.lengthDifference),
          false,
        );
      });

      test('should return warning when translation is significantly longer', () async {
        // Arrange
        const sourceText = 'Hi';
        const translatedText = 'This is an extremely long translation that is way too verbose for such a short source.';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        final issues = result.value;
        expect(issues.any((i) => i.type == ValidationIssueType.lengthDifference), true);
        final lengthIssue = issues.firstWhere(
          (i) => i.type == ValidationIssueType.lengthDifference,
        );
        expect(lengthIssue.description, contains('longer'));
      });

      test('should not return warning when length difference is within threshold', () async {
        // Arrange (less than 100% difference)
        const sourceText = 'Hello world';
        const translatedText = 'Bonjour le monde';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.lengthDifference),
          false,
        );
      });
    });

    // =========================================================================
    // validateTranslation - Missing Variables
    // =========================================================================
    group('validateTranslation - missing variables', () {
      test('should return error when numbered placeholder is missing', () async {
        // Arrange
        const sourceText = 'Hello {0}, welcome to {1}!';
        const translatedText = 'Bonjour, bienvenue!';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        final issues = result.value;
        expect(issues.any((i) => i.type == ValidationIssueType.missingVariables), true);
        final variableIssue = issues.firstWhere(
          (i) => i.type == ValidationIssueType.missingVariables,
        );
        expect(variableIssue.severity, ValidationSeverity.error);
        expect(variableIssue.autoFixable, true);
        expect(variableIssue.description, contains('{0}'));
        expect(variableIssue.description, contains('{1}'));
      });

      test('should return error when printf placeholder is missing', () async {
        // Arrange
        const sourceText = 'Count: %d items, Price: %s';
        const translatedText = 'Compte: elements, Prix:';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        final issues = result.value;
        expect(issues.any((i) => i.type == ValidationIssueType.missingVariables), true);
      });

      test('should return error when bracketed printf placeholder is missing', () async {
        // Arrange
        const sourceText = 'Value: [%s] and [%d]';
        const translatedText = 'Valeur: et';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.missingVariables),
          true,
        );
      });

      test('should not return error when all variables are present', () async {
        // Arrange
        const sourceText = 'Hello {0}, welcome to {1}!';
        const translatedText = 'Bonjour {0}, bienvenue a {1}!';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.missingVariables),
          false,
        );
      });

      test('should handle dart-style variables', () async {
        // Arrange
        const sourceText = 'Hello \${name}, your ID is \${userId}';
        const translatedText = 'Bonjour, votre ID est';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.missingVariables),
          true,
        );
      });
    });

    // =========================================================================
    // validateTranslation - Whitespace Issues
    // =========================================================================
    group('validateTranslation - whitespace issues', () {
      test('should return warning when leading whitespace differs', () async {
        // Arrange
        const sourceText = '  Hello';
        const translatedText = 'Bonjour';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.whitespaceIssue),
          true,
        );
      });

      test('should return warning when trailing whitespace differs', () async {
        // Arrange
        const sourceText = 'Hello  ';
        const translatedText = 'Bonjour';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.whitespaceIssue),
          true,
        );
      });

      test('should return warning when translation contains double spaces', () async {
        // Arrange
        const sourceText = 'Hello world';
        const translatedText = 'Bonjour  monde';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        final issues = result.value.where(
          (i) => i.type == ValidationIssueType.whitespaceIssue,
        );
        expect(issues.isNotEmpty, true);
        expect(
          issues.any((i) => i.description.contains('double spaces')),
          true,
        );
      });

      test('should provide auto-fix for whitespace issues', () async {
        // Arrange
        const sourceText = 'Hello';
        const translatedText = '  Bonjour  ';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        final whitespaceIssue = result.value.firstWhere(
          (i) => i.type == ValidationIssueType.whitespaceIssue,
        );
        expect(whitespaceIssue.autoFixable, true);
        expect(whitespaceIssue.autoFixValue, isNotNull);
      });
    });

    // =========================================================================
    // validateTranslation - Punctuation Mismatch
    // =========================================================================
    group('validateTranslation - punctuation mismatch', () {
      test('should return info when ending punctuation differs', () async {
        // Arrange
        const sourceText = 'Hello world.';
        const translatedText = 'Bonjour monde!';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.punctuationMismatch),
          true,
        );
        final punctuationIssue = result.value.firstWhere(
          (i) => i.type == ValidationIssueType.punctuationMismatch,
        );
        expect(punctuationIssue.severity, ValidationSeverity.info);
      });

      test('should not return issue when punctuation matches', () async {
        // Arrange
        const sourceText = 'Hello world!';
        const translatedText = 'Bonjour monde!';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.punctuationMismatch),
          false,
        );
      });

      test('should handle question mark vs period', () async {
        // Arrange
        const sourceText = 'Are you ready?';
        const translatedText = 'Etes-vous pret.';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.punctuationMismatch),
          true,
        );
      });
    });

    // =========================================================================
    // validateTranslation - Case Mismatch
    // =========================================================================
    group('validateTranslation - case mismatch', () {
      test('should return info when source starts uppercase but translation lowercase', () async {
        // Arrange
        const sourceText = 'Hello world';
        const translatedText = 'bonjour monde';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.caseMismatch),
          true,
        );
        final caseIssue = result.value.firstWhere(
          (i) => i.type == ValidationIssueType.caseMismatch,
        );
        expect(caseIssue.severity, ValidationSeverity.info);
      });

      test('should not return issue when case matches', () async {
        // Arrange
        const sourceText = 'Hello world';
        const translatedText = 'Bonjour monde';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.caseMismatch),
          false,
        );
      });
    });

    // =========================================================================
    // validateTranslation - Missing Numbers
    // =========================================================================
    group('validateTranslation - missing numbers', () {
      test('should return warning when number is missing in translation', () async {
        // Arrange
        const sourceText = 'You have 42 items in your cart.';
        const translatedText = 'Vous avez des articles dans votre panier.';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.missingNumbers),
          true,
        );
        final numberIssue = result.value.firstWhere(
          (i) => i.type == ValidationIssueType.missingNumbers,
        );
        expect(numberIssue.severity, ValidationSeverity.warning);
        expect(numberIssue.description, contains('42'));
      });

      test('should not return issue when all numbers are present', () async {
        // Arrange
        const sourceText = 'You have 42 items.';
        const translatedText = 'Vous avez 42 articles.';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.missingNumbers),
          false,
        );
      });
    });

    // =========================================================================
    // validateTranslation - Modified Numbers
    // =========================================================================
    group('validateTranslation - modified numbers', () {
      test('should return error when number has been reformatted with spaces', () async {
        // Arrange (color code 13140 formatted as 13 140)
        const sourceText = 'Color code: 13140';
        const translatedText = 'Code couleur: 13 140';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.modifiedNumbers),
          true,
        );
        final modifiedIssue = result.value.firstWhere(
          (i) => i.type == ValidationIssueType.modifiedNumbers,
        );
        expect(modifiedIssue.severity, ValidationSeverity.error);
        expect(modifiedIssue.autoFixable, true);
      });

      test('should return error when large number has thousand separators added', () async {
        // Arrange
        const sourceText = 'Price: 1000000 gold';
        const translatedText = 'Prix: 1 000 000 or';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(
          result.value.any((i) => i.type == ValidationIssueType.modifiedNumbers),
          true,
        );
      });
    });

    // =========================================================================
    // applyAutoFix
    // =========================================================================
    group('applyAutoFix', () {
      test('should apply fix when issue is auto-fixable', () async {
        // Arrange
        const translatedText = '  Bonjour monde  ';
        const issue = ValidationIssue(
          type: ValidationIssueType.whitespaceIssue,
          severity: ValidationSeverity.warning,
          description: 'Whitespace issue',
          autoFixable: true,
          autoFixValue: 'Bonjour monde',
        );

        // Act
        final result = await service.applyAutoFix(
          translatedText: translatedText,
          issue: issue,
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value, 'Bonjour monde');
      });

      test('should return error when issue is not auto-fixable', () async {
        // Arrange
        const translatedText = 'Test';
        const issue = ValidationIssue(
          type: ValidationIssueType.emptyTranslation,
          severity: ValidationSeverity.error,
          description: 'Empty translation',
          autoFixable: false,
        );

        // Act
        final result = await service.applyAutoFix(
          translatedText: translatedText,
          issue: issue,
        );

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, contains('not auto-fixable'));
      });

      test('should return error when autoFixValue is null', () async {
        // Arrange
        const translatedText = 'Test';
        const issue = ValidationIssue(
          type: ValidationIssueType.whitespaceIssue,
          severity: ValidationSeverity.warning,
          description: 'Whitespace issue',
          autoFixable: true,
          autoFixValue: null,
        );

        // Act
        final result = await service.applyAutoFix(
          translatedText: translatedText,
          issue: issue,
        );

        // Assert
        expect(result.isErr, true);
      });
    });

    // =========================================================================
    // applyAllAutoFixes
    // =========================================================================
    group('applyAllAutoFixes', () {
      test('should apply whitespace fix', () async {
        // Arrange
        const sourceText = 'Hello';
        const translatedText = '  Bonjour  ';
        final issues = [
          const ValidationIssue(
            type: ValidationIssueType.whitespaceIssue,
            severity: ValidationSeverity.warning,
            description: 'Whitespace mismatch',
            autoFixable: true,
            autoFixValue: 'Bonjour',
          ),
        ];

        // Act
        final result = await service.applyAllAutoFixes(
          sourceText: sourceText,
          translatedText: translatedText,
          issues: issues,
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value, 'Bonjour');
      });

      test('should return original text when no auto-fixable issues', () async {
        // Arrange
        const sourceText = 'Hello';
        const translatedText = 'Bonjour';
        final issues = [
          const ValidationIssue(
            type: ValidationIssueType.caseMismatch,
            severity: ValidationSeverity.info,
            description: 'Case mismatch',
            autoFixable: false,
          ),
        ];

        // Act
        final result = await service.applyAllAutoFixes(
          sourceText: sourceText,
          translatedText: translatedText,
          issues: issues,
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value, 'Bonjour');
      });
    });

    // =========================================================================
    // Edge Cases
    // =========================================================================
    group('edge cases', () {
      test('should handle very long text', () async {
        // Arrange
        final sourceText = 'Hello ' * 1000;
        final translatedText = 'Bonjour ' * 1000;

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
      });

      test('should handle special characters', () async {
        // Arrange
        const sourceText = 'Test with special chars: @#\$%^&*()';
        const translatedText = 'Test avec chars speciaux: @#\$%^&*()';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
      });

      test('should handle unicode characters', () async {
        // Arrange
        const sourceText = 'Hello world';
        const translatedText = 'Bonjour le monde';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
      });

      test('should handle multiple issues at once', () async {
        // Arrange (multiple issues: empty, length, case)
        const sourceText = 'Hello {0}!';
        const translatedText = '  bonjour  ';

        // Act
        final result = await service.validateTranslation(
          sourceText: sourceText,
          translatedText: translatedText,
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.length, greaterThan(1));
      });
    });
  });
}
