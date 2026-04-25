import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/models/common/validation_result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/headless_validation_rescan_service.dart';
import 'package:twmt/services/translation/i_validation_service.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';
import 'package:twmt/services/validation/validation_schema.dart';

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockValidationService extends Mock implements IValidationService {}

void main() {
  late _MockVersionRepo repo;

  setUp(() {
    repo = _MockVersionRepo();
  });

  test('returns zero-valued result when no translated units', () async {
    // getByProjectLanguage returns an empty list (no versions at all).
    when(() => repo.getByProjectLanguage(any()))
        .thenAnswer((_) async => const Ok([]));

    // normalizeStatusEncoding is also called before the main fetch.
    when(() => repo.normalizeStatusEncoding())
        .thenAnswer((_) async => const Ok(0));

    // Wrap the call in a FutureProvider so it receives a Ref — the
    // idiomatic way to test a Ref-taking function from a ProviderContainer.
    final resultProvider = FutureProvider<RescanResult>((ref) {
      return runHeadlessValidationRescan(
        ref: ref,
        projectLanguageId: 'pl-1',
      );
    });

    final container = ProviderContainer(overrides: [
      translationVersionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(resultProvider.future);

    expect(result.scanned, 0);
    expect(result.needsReviewTotal, 0);
  });

  // Regression: when validation flips a row to needs-review, the rescan
  // must stamp `kCurrentValidationSchemaVersion` on the row — not the
  // hardcoded `1` that previously slipped through. Hardcoded `1` made
  // the row look legacy on next boot and re-triggered the
  // "Resuming validation update" dialog every time a user reviewed
  // units in a project.
  test(
    'stamps current schema version on rescan-modified rows',
    () async {
      final unitRepo = _MockUnitRepo();
      final validation = _MockValidationService();

      const projectLanguageId = 'pl-1';
      final unit = TranslationUnit(
        id: 'unit-1',
        projectId: 'proj-1',
        key: 'k1',
        sourceText: 'Hello',
        createdAt: 0,
        updatedAt: 0,
      );
      // Stored at the current schema version with status=translated; the
      // validator below will flip it to needs-review, forcing a write.
      final storedVersion = TranslationVersion(
        id: 'v-1',
        unitId: unit.id,
        projectLanguageId: projectLanguageId,
        translatedText: 'Bonjour',
        status: TranslationVersionStatus.translated,
        validationSchemaVersion: kCurrentValidationSchemaVersion,
        createdAt: 0,
        updatedAt: 0,
      );

      when(() => repo.normalizeStatusEncoding())
          .thenAnswer((_) async => const Ok(0));
      when(() => repo.getByProjectLanguage(projectLanguageId))
          .thenAnswer((_) async => Ok([storedVersion]));
      when(() => unitRepo.getByIds(any()))
          .thenAnswer((_) async => Ok([unit]));
      when(() => validation.validateTranslation(
            sourceText: any(named: 'sourceText'),
            translatedText: any(named: 'translatedText'),
            key: any(named: 'key'),
          )).thenAnswer((_) async => Ok(ValidationResult.failure(
                issues: const [
                  ValidationIssueEntry(
                    rule: ValidationRule.completeness,
                    severity: ValidationSeverity.error,
                    message: 'forced flip to needs-review',
                  ),
                ],
              )));
      when(() => repo.updateValidationBatch(any()))
          .thenAnswer((_) async => const Ok(1));

      final resultProvider = FutureProvider<RescanResult>((ref) {
        return runHeadlessValidationRescan(
          ref: ref,
          projectLanguageId: projectLanguageId,
        );
      });

      final container = ProviderContainer(overrides: [
        translationVersionRepositoryProvider.overrideWithValue(repo),
        translationUnitRepositoryProvider.overrideWithValue(unitRepo),
        validationServiceProvider.overrideWithValue(validation),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(resultProvider.future);
      expect(result.newIssues, 1);

      // Capture the updates the rescan wrote and verify the stamped
      // schema version is the current constant — not 1.
      final captured =
          verify(() => repo.updateValidationBatch(captureAny())).captured;
      expect(captured, hasLength(1));
      final updates = captured.first as List;
      expect(updates, hasLength(1));
      final update = updates.first as ({
        String versionId,
        String status,
        String? validationIssues,
        int schemaVersion,
      });
      expect(update.schemaVersion, kCurrentValidationSchemaVersion);
    },
  );
}
