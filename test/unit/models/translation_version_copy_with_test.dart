import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_version.dart';

void main() {
  const issuesJson =
      '[{"rule":"markup","severity":"warning","message":"tag mismatch"}]';

  TranslationVersion version({String? validationIssues = issuesJson}) =>
      TranslationVersion(
        id: 'v1',
        unitId: 'u1',
        projectLanguageId: 'pl1',
        translatedText: 'Bonjour',
        status: TranslationVersionStatus.needsReview,
        validationIssues: validationIssues,
        createdAt: 0,
        updatedAt: 0,
      );

  group('TranslationVersion.copyWith validationIssues semantics', () {
    test('clearValidationIssues: true clears the field', () {
      final cleared = version().copyWith(clearValidationIssues: true);
      expect(cleared.validationIssues, isNull);
      expect(cleared.hasValidationIssues, isFalse);
    });

    test(
        'passing validationIssues: null is a KEEP, not a clear — '
        'callers must use clearValidationIssues instead', () {
      // Pins the copyWith contract: an explicit null is indistinguishable
      // from omitting the parameter, so the old value is retained. Any
      // call site that intends to clear must pass clearValidationIssues.
      final kept = version().copyWith(validationIssues: null);
      expect(kept.validationIssues, issuesJson);
      expect(kept.hasValidationIssues, isTrue);
    });

    test('passing a new value replaces the old one', () {
      const newIssues = '[{"rule":"variables"}]';
      final replaced = version().copyWith(validationIssues: newIssues);
      expect(replaced.validationIssues, newIssues);
    });

    test('clearing issues on a translated row makes it ready for use', () {
      final accepted = version().copyWith(
        status: TranslationVersionStatus.translated,
        clearValidationIssues: true,
      );
      expect(accepted.isReadyForUse, isTrue);
    });
  });
}
