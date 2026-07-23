import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/validation/translation_validation_service.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';

/// H1 (occurrence count) + H2 (printf grammar) regressions for the editor's
/// inline validation service.
void main() {
  late TranslationValidationService service;

  setUp(() {
    service = TranslationValidationService();
  });

  bool hasMissingVars(List<ValidationIssue> issues) =>
      issues.any((i) => i.type == ValidationIssueType.missingVariables);

  group('missing variables - printf grammar (H2)', () {
    test('detects dropped %u', () async {
      final result = await service.validateTranslation(
        sourceText: 'Gain %u renown',
        translatedText: 'Gagnez du prestige',
      );
      expect(hasMissingVars(result.value), true);
    });

    test('detects dropped %x (hex)', () async {
      final result = await service.validateTranslation(
        sourceText: 'ref %x',
        translatedText: 'ref',
      );
      expect(hasMissingVars(result.value), true);
    });

    test('detects dropped length-modified %ld', () async {
      final result = await service.validateTranslation(
        sourceText: 'count=%ld',
        translatedText: 'compte=',
      );
      expect(hasMissingVars(result.value), true);
    });
  });

  group('missing variables - occurrence count (H1)', () {
    test('detects dropping one of two identical %s', () async {
      final result = await service.validateTranslation(
        sourceText: 'Move %s to %s',
        translatedText: 'Deplacer %s',
      );
      expect(hasMissingVars(result.value), true);
    });

    test('equal count preserved -> no missing-variable issue (guard)', () async {
      final result = await service.validateTranslation(
        sourceText: 'Move %s to %s',
        translatedText: 'Deplacer %s vers %s',
      );
      expect(hasMissingVars(result.value), false);
    });
  });
}
