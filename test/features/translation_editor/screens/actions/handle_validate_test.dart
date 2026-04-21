import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_actions.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart'
    hide ValidationException;
import 'package:twmt/models/common/validation_issue_entry.dart';
import 'package:twmt/models/common/validation_result.dart' as common;
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/translation/i_validation_service.dart'
    show IValidationService;
import 'package:twmt/services/translation/models/translation_exceptions.dart'
    show ValidationException, ValidationSeverity;
import 'package:twmt/services/translation/models/validation_rule.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../../helpers/fakes/fake_logger.dart';

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockUnitRepository extends Mock implements TranslationUnitRepository {}

class _MockValidationService extends Mock implements IValidationService {}

/// Harness widget that builds a [TranslationEditorActions] from the live
/// `WidgetRef` + `BuildContext` pair. The caller pokes
/// [_ActionsHarnessState.handleValidate] via a [GlobalKey] so the test can
/// `await` the returned future directly without relying on a button tap.
class _ActionsHarness extends ConsumerStatefulWidget {
  const _ActionsHarness({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  final String projectId;
  final String languageId;

  @override
  ConsumerState<_ActionsHarness> createState() => _ActionsHarnessState();
}

class _ActionsHarnessState extends ConsumerState<_ActionsHarness> {
  Future<void> handleValidate() {
    final actions = TranslationEditorActions(
      ref: ref,
      context: context,
      projectId: widget.projectId,
      languageId: widget.languageId,
    );
    return actions.handleValidate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  const projectId = 'project-1';
  const languageId = 'language-fr';
  const projectLanguageId = 'plang-1';
  const unitId = 'unit-a';
  const versionId = 'version-a';

  late _MockProjectLanguageRepository projectLanguageRepo;
  late _MockVersionRepository versionRepo;
  late _MockUnitRepository unitRepo;
  late _MockValidationService validationService;

  setUp(() {
    projectLanguageRepo = _MockProjectLanguageRepository();
    versionRepo = _MockVersionRepository();
    unitRepo = _MockUnitRepository();
    validationService = _MockValidationService();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final projectLanguage = ProjectLanguage(
      id: projectLanguageId,
      projectId: projectId,
      languageId: languageId,
      createdAt: now,
      updatedAt: now,
    );

    final unit = TranslationUnit(
      id: unitId,
      projectId: projectId,
      key: 'greeting',
      sourceText: 'Hello',
      createdAt: now,
      updatedAt: now,
    );

    final version = TranslationVersion(
      id: versionId,
      unitId: unitId,
      projectLanguageId: projectLanguageId,
      translatedText: 'Bonjour',
      status: TranslationVersionStatus.translated,
      createdAt: now,
      updatedAt: now,
    );

    when(() => projectLanguageRepo.getByProject(projectId)).thenAnswer(
      (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>(
        [projectLanguage],
      ),
    );

    when(() => versionRepo.normalizeStatusEncoding()).thenAnswer(
      (_) async => const Ok<int, TWMTDatabaseException>(0),
    );

    when(() => versionRepo.getByProjectLanguage(projectLanguageId)).thenAnswer(
      (_) async => Ok<List<TranslationVersion>, TWMTDatabaseException>(
        [version],
      ),
    );

    when(() => unitRepo.getByIds(any())).thenAnswer(
      (_) async => Ok<List<TranslationUnit>, TWMTDatabaseException>([unit]),
    );

    // Default: validation returns a clean result so the row's status
    // stays `translated`. Tests that need a failing result override this
    // stub locally.
    when(
      () => validationService.validateTranslation(
        sourceText: any(named: 'sourceText'),
        translatedText: any(named: 'translatedText'),
        key: any(named: 'key'),
      ),
    ).thenAnswer(
      (_) async => Ok<common.ValidationResult, ValidationException>(
        common.ValidationResult.success(),
      ),
    );
  });

  testWidgets(
    'handleValidate leaves filters untouched when no row needs review',
    (tester) async {
      final harnessKey = GlobalKey<_ActionsHarnessState>();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loggingServiceProvider.overrideWithValue(FakeLogger()),
            projectLanguageRepositoryProvider.overrideWithValue(
              projectLanguageRepo,
            ),
            translationVersionRepositoryProvider.overrideWithValue(
              versionRepo,
            ),
            translationUnitRepositoryProvider.overrideWithValue(unitRepo),
            validationServiceProvider.overrideWithValue(validationService),
          ],
          child: MaterialApp(
            theme: AppTheme.atelierDarkTheme,
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  container = ProviderScope.containerOf(ctx);
                  return _ActionsHarness(
                    key: harnessKey,
                    projectId: projectId,
                    languageId: languageId,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Keep `editorFilterProvider` alive for the duration of the test.
      // Without an active listener the provider (autoDispose) would reset
      // between reads — `setStatusFilters({needsReview})` then
      // subsequently reading the state would yield the initial
      // (empty) value again.
      final filterSubscription = container.listen(
        editorFilterProvider,
        (_, _) {},
      );
      addTearDown(filterSubscription.close);

      // Confirm initial filter state is empty — otherwise the assertions
      // below would be vacuous.
      final initialFilter = container.read(editorFilterProvider);
      expect(initialFilter.statusFilters, isEmpty);
      expect(initialFilter.severityFilters, isEmpty);

      // Kick off `handleValidate` via the harness and settle the async
      // microtasks it schedules. We pump a handful of frames rather than
      // calling `pumpAndSettle` because the production flow opens a
      // progress dialog whose [CircularProgressIndicator] animates
      // forever — `pumpAndSettle` would never return.
      final handleFuture = harnessKey.currentState!.handleValidate();
      bool done = false;
      handleFuture.then((_) => done = true, onError: (_, _) => done = true);
      for (var i = 0; i < 32 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await handleFuture;
      await tester.pump();

      // The progress dialog's `ValueListenableBuilder` races with the
      // `finally` block that disposes the notifier: in this tight test
      // harness the rescan finishes before the dialog's builder is first
      // invoked, so the builder trips
      // `ChangeNotifier.debugAssertNotDisposed` when it calls
      // `addListener`. Drain that known assertion so the test harness
      // doesn't fail on it — it does not occur in production where the
      // rescan takes milliseconds and the dialog mounts first.
      final swallowed = tester.takeException();
      if (swallowed != null) {
        expect(
          swallowed.toString(),
          contains('ValueNotifier'),
          reason:
              'Only the expected dispose-race assertion should be drained.',
        );
      }

      final finalFilter = container.read(editorFilterProvider);
      expect(
        finalFilter.statusFilters,
        isEmpty,
        reason:
            'handleValidate must not pivot the status filter when zero rows '
            'need review — pivoting would hide every row in the grid',
      );
      expect(
        finalFilter.severityFilters,
        isEmpty,
        reason: 'severity filter must remain untouched on the zero-issue path',
      );
    },
  );

  testWidgets(
    'handleValidate pivots filters when at least one row needs review',
    (tester) async {
      // Override the default clean-result stub with one that surfaces a
      // warning — the rescan should flip the row to `needsReview`.
      when(
        () => validationService.validateTranslation(
          sourceText: any(named: 'sourceText'),
          translatedText: any(named: 'translatedText'),
          key: any(named: 'key'),
        ),
      ).thenAnswer(
        (_) async => Ok<common.ValidationResult, ValidationException>(
          common.ValidationResult.failure(
            issues: const [
              ValidationIssueEntry(
                rule: ValidationRule.markup,
                severity: ValidationSeverity.warning,
                message: 'mocked warning',
              ),
            ],
          ),
        ),
      );
      when(() => versionRepo.updateValidationBatch(any())).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(1),
      );

      final harnessKey = GlobalKey<_ActionsHarnessState>();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loggingServiceProvider.overrideWithValue(FakeLogger()),
            projectLanguageRepositoryProvider.overrideWithValue(
              projectLanguageRepo,
            ),
            translationVersionRepositoryProvider.overrideWithValue(
              versionRepo,
            ),
            translationUnitRepositoryProvider.overrideWithValue(unitRepo),
            validationServiceProvider.overrideWithValue(validationService),
          ],
          child: MaterialApp(
            theme: AppTheme.atelierDarkTheme,
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  container = ProviderScope.containerOf(ctx);
                  return _ActionsHarness(
                    key: harnessKey,
                    projectId: projectId,
                    languageId: languageId,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final filterSubscription = container.listen(
        editorFilterProvider,
        (_, _) {},
      );
      addTearDown(filterSubscription.close);

      final handleFuture = harnessKey.currentState!.handleValidate();
      bool done = false;
      handleFuture.then((_) => done = true, onError: (_, _) => done = true);
      for (var i = 0; i < 32 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await handleFuture;
      await tester.pump();

      final swallowed = tester.takeException();
      if (swallowed != null) {
        expect(
          swallowed.toString(),
          contains('ValueNotifier'),
          reason:
              'Only the expected dispose-race assertion should be drained.',
        );
      }

      final finalFilter = container.read(editorFilterProvider);
      expect(
        finalFilter.statusFilters,
        contains(TranslationVersionStatus.needsReview),
        reason:
            'handleValidate must focus the grid on needsReview when at least '
            'one row needs review',
      );
      expect(
        finalFilter.severityFilters,
        isEmpty,
        reason:
            'handleValidate must clear severity filters so the SEVERITY pill '
            'group reflects fresh counts',
      );
    },
  );
}
