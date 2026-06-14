// Line-coverage tests for [BulkReviewDialog]. Complements the focused
// `bulk_review_dialog_retranslate_test.dart` (which locks the per-row
// retranslate provider-resolution contract) by exercising the remaining
// branches: per-row validate (success + error), validate-all (success +
// error), retranslate-all (progress dialog + notifier), the selected-editor
// -model resolution path, and the empty / error / loading render states plus
// the refresh action.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/bulk_review_rows_provider.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';
import 'package:twmt/features/projects/widgets/bulk_review_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/llm_model_providers.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/providers/translation_runner_providers.dart';
import 'package:twmt/repositories/llm_provider_model_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

// ---------------------------------------------------------------------------
// Mocks / Fakes
// ---------------------------------------------------------------------------

class _MockRunner extends Mock implements HeadlessBatchTranslationRunner {}

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockModelRepo extends Mock implements LlmProviderModelRepository {}

class _FakeModel extends Fake implements LlmProviderModel {
  _FakeModel(this.providerCode, this.modelId);
  @override
  final String providerCode;
  @override
  final String modelId;
}

class _FakeProject extends Fake implements Project {
  _FakeProject(this.id);
  @override
  final String id;
  @override
  String get name => 'My project';
}

class _FakeProjectLanguage extends Fake implements ProjectLanguage {
  _FakeProjectLanguage(this.id);
  @override
  final String id;
}

class _FakeLanguage extends Fake implements Language {
  _FakeLanguage(this.code);
  @override
  final String code;
}

class _FakeLang extends Fake implements ProjectLanguageWithInfo {
  _FakeLang({required this.projectLanguage, Language? language})
      : _language = language;
  @override
  final ProjectLanguage projectLanguage;
  final Language? _language;
  @override
  Language? get language => _language;
}

class _FakeProjectWithDetails extends Fake implements ProjectWithDetails {
  _FakeProjectWithDetails({required this.project, required this.languages});
  @override
  final Project project;
  @override
  final List<ProjectLanguageWithInfo> languages;
}

/// Bulk handlers stubbed so the retranslate-all run completes immediately with
/// a success outcome instead of executing the real translation pipeline.
class _StubBulkHandlers extends BulkHandlers {
  const _StubBulkHandlers();
  @override
  Future<ProjectOutcome> translateReviews({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) async =>
      const ProjectOutcome(status: ProjectResultStatus.succeeded);
}

/// Editor model selection stubbed to a fixed value.
class _StubLlmModel extends SelectedLlmModel {
  _StubLlmModel(this._value);
  final String? _value;
  @override
  String? build() => _value;
}

class _StubLlmProviderSettings extends LlmProviderSettings {
  _StubLlmProviderSettings(this._settings);
  final Map<String, String> _settings;
  @override
  Future<Map<String, String>> build() async => _settings;
}

/// Target-language notifier stubbed so the dialog's `asData.value` resolves
/// synchronously to a fixed code (the per-row provider override supplies the
/// rows; this one feeds the subtitle and the retranslate-all scope).
class _StubBulkTargetLanguage extends BulkTargetLanguageNotifier {
  _StubBulkTargetLanguage(this._code);
  final String? _code;
  @override
  Future<String?> build() async => _code;
}

/// Drains [TokenDialog] footer RenderFlex overflows (wide Ahem glyphs in tests
/// push the footer ~15px past the dialog width; production fonts fit). Mirrors
/// the sibling retranslate test's drainer — anything else re-throws.
void _drainTokenDialogOverflow(WidgetTester tester) {
  while (true) {
    final e = tester.takeException();
    if (e == null) return;
    final msg = e.toString();
    if (msg.contains('A RenderFlex overflowed')) continue;
    if (msg.startsWith('Multiple exceptions')) continue;
    throw e;
  }
}

const _row = BulkReviewRow(
  projectId: 'proj-1',
  projectName: 'My project',
  projectLanguageId: 'pl-1',
  unitId: 'unit-1',
  versionId: 'v-1',
  key: 'unit_key',
  sourceText: 'Hello',
  translatedText: 'Bonjour',
);

/// Second row in the same project with a missing translation — exercises the
/// list separator (>=2 rows) and the empty-translation styling branch.
const _rowNoTranslation = BulkReviewRow(
  projectId: 'proj-1',
  projectName: 'My project',
  projectLanguageId: 'pl-1',
  unitId: 'unit-2',
  versionId: 'v-2',
  key: 'unit_key_2',
  sourceText: 'World',
  translatedText: null,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  late _MockRunner runner;
  late _MockVersionRepo versionRepo;
  late _MockModelRepo modelRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    runner = _MockRunner();
    versionRepo = _MockVersionRepo();
    modelRepo = _MockModelRepo();
    when(() => runner.run(
          projectLanguageId: any(named: 'projectLanguageId'),
          projectId: any(named: 'projectId'),
          unitIds: any(named: 'unitIds'),
          skipTM: any(named: 'skipTM'),
          providerId: any(named: 'providerId'),
          modelId: any(named: 'modelId'),
        )).thenAnswer((_) async => 1);
  });

  // Builds a single matching project that lines up with [_row] so the
  // retranslate-all scope filter resolves to a non-empty project list.
  ProjectWithDetails matchingProject() => _FakeProjectWithDetails(
        project: _FakeProject('proj-1'),
        languages: [
          _FakeLang(
            projectLanguage: _FakeProjectLanguage('pl-1'),
            language: _FakeLanguage('fr'),
          ),
        ],
      );

  Future<void> pumpDialog(
    WidgetTester tester, {
    List<Override> overrides = const [],
    String? selectedModelId,
    Map<String, String> llmSettings = const {
      SettingsKeys.activeProvider: 'anthropic',
    },
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(body: BulkReviewDialog()),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        selectedLlmModelProvider
            .overrideWith(() => _StubLlmModel(selectedModelId)),
        llmProviderSettingsProvider
            .overrideWith(() => _StubLlmProviderSettings(llmSettings)),
        bulkTargetLanguageProvider
            .overrideWith(() => _StubBulkTargetLanguage('fr')),
        translationVersionRepositoryProvider.overrideWithValue(versionRepo),
        llmProviderModelRepositoryProvider.overrideWithValue(modelRepo),
        headlessBatchTranslationRunnerProvider.overrideWithValue(runner),
        ...overrides,
      ],
    ));
    if (settle) {
      await tester.pumpAndSettle();
      _drainTokenDialogOverflow(tester);
    }
  }

  // -------------------------------------------------------------------------
  // Render states
  // -------------------------------------------------------------------------

  testWidgets('renders the empty state when there are no review rows',
      (tester) async {
    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => const []),
    ]);

    expect(find.text(t.projects.bulk.review.emptyTitle), findsOneWidget);
    expect(find.text(t.projects.bulk.review.emptySubtitle), findsOneWidget);
  });

  testWidgets(
      'renders a multi-row list with a divider and the empty-translation '
      'placeholder', (tester) async {
    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider
          .overrideWith((ref) async => [_row, _rowNoTranslation]),
    ]);

    // Two rows => at least one Divider between them.
    expect(find.byType(Divider), findsWidgets);
    // The row without a translation shows the italic placeholder text.
    expect(find.text(t.projects.bulk.review.emptyTranslation), findsOneWidget);
  });

  testWidgets('renders the error state when the rows provider fails',
      (tester) async {
    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider
          .overrideWith((ref) async => throw Exception('boom')),
    ]);

    expect(
      find.text(
        t.projects.bulk.review.loadFailed(error: 'Exception: boom'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders a spinner while the rows provider is loading',
      (tester) async {
    final completer = Completer<List<BulkReviewRow>>();
    await pumpDialog(
      tester,
      settle: false,
      overrides: [
        bulkReviewRowsProvider.overrideWith((ref) => completer.future),
      ],
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    completer.complete(const []);
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);
  });

  testWidgets('refresh action invalidates the rows provider', (tester) async {
    var builds = 0;
    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async {
        builds++;
        return const <BulkReviewRow>[];
      }),
    ]);
    expect(builds, 1);

    await tester.tap(find.text(t.common.actions.refresh));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    expect(builds, 2);
  });

  // -------------------------------------------------------------------------
  // Per-row validate
  // -------------------------------------------------------------------------

  testWidgets('per-row validate accepts the version on success',
      (tester) async {
    when(() => versionRepo.acceptBatch(any()))
        .thenAnswer((_) async => const Ok(1));

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
    ]);

    await tester.tap(find.byTooltip(t.projects.bulk.review.tooltipValidate));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    verify(() => versionRepo.acceptBatch(['v-1'])).called(1);
    expect(find.text(t.projects.bulk.review.validateFailed(error: 'x')),
        findsNothing);
  });

  testWidgets(
      'shows the per-row spinner while a validate is in flight and the '
      'leading busy spinner while validate-all runs', (tester) async {
    final gate = Completer<Result<int, TWMTDatabaseException>>();
    when(() => versionRepo.acceptBatch(any()))
        .thenAnswer((_) => gate.future);

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
    ]);

    // Per-row validate in flight => the tile's action button swaps its icon
    // for a CircularProgressIndicator (the _RowActionButton busy branch).
    await tester.tap(find.byTooltip(t.projects.bulk.review.tooltipValidate));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    gate.complete(const Ok(1));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    // Validate-all in flight => the leading _InlineSpinner with its label.
    final gate2 = Completer<Result<int, TWMTDatabaseException>>();
    when(() => versionRepo.acceptBatch(any()))
        .thenAnswer((_) => gate2.future);
    await tester.tap(find.text(t.projects.bulk.review.validateAll));
    await tester.pump();
    expect(find.text(t.projects.bulk.review.working), findsOneWidget);

    gate2.complete(const Ok(1));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);
  });

  testWidgets('per-row validate surfaces an error dialog on failure',
      (tester) async {
    when(() => versionRepo.acceptBatch(any())).thenAnswer(
      (_) async => const Err(TWMTDatabaseException('db down')),
    );

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
    ]);

    await tester.tap(find.byTooltip(t.projects.bulk.review.tooltipValidate));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    // Errors surface through TokenDialog.showError (a SnackBar would assert in
    // the app's Scaffold-less FluentScaffold shell), so the error title shows.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(t.common.error), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Per-row retranslate (selected editor model path)
  // -------------------------------------------------------------------------

  testWidgets(
      'per-row retranslate resolves the selected editor model and runs',
      (tester) async {
    when(() => modelRepo.getById('model-1')).thenAnswer(
      (_) async => Ok(_FakeModel('anthropic', 'claude-x')),
    );

    await pumpDialog(
      tester,
      selectedModelId: 'model-1',
      overrides: [
        bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
      ],
    );

    await tester.tap(find.byTooltip(t.projects.bulk.review.tooltipRetranslate));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    verify(() => runner.run(
          projectLanguageId: 'pl-1',
          projectId: 'proj-1',
          unitIds: any(named: 'unitIds'),
          skipTM: true,
          providerId: 'provider_anthropic',
          modelId: 'claude-x',
        )).called(1);
  });

  testWidgets('per-row retranslate surfaces an error when the runner throws',
      (tester) async {
    when(() => modelRepo.getById('model-1')).thenAnswer(
      (_) async => Ok(_FakeModel('anthropic', 'claude-x')),
    );
    when(() => runner.run(
          projectLanguageId: any(named: 'projectLanguageId'),
          projectId: any(named: 'projectId'),
          unitIds: any(named: 'unitIds'),
          skipTM: any(named: 'skipTM'),
          providerId: any(named: 'providerId'),
          modelId: any(named: 'modelId'),
        )).thenAnswer((_) async => throw StateError('runner exploded'));

    await pumpDialog(
      tester,
      selectedModelId: 'model-1',
      overrides: [
        bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
      ],
    );

    await tester.tap(find.byTooltip(t.projects.bulk.review.tooltipRetranslate));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(t.common.error), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Validate all
  // -------------------------------------------------------------------------

  testWidgets('validate all accepts every version on success', (tester) async {
    when(() => versionRepo.acceptBatch(any()))
        .thenAnswer((_) async => const Ok(2));

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
    ]);

    await tester.tap(find.text(t.projects.bulk.review.validateAll));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    verify(() => versionRepo.acceptBatch(['v-1'])).called(1);
  });

  testWidgets('validate all surfaces an error dialog on failure',
      (tester) async {
    when(() => versionRepo.acceptBatch(any())).thenAnswer(
      (_) async => const Err(TWMTDatabaseException('batch failed')),
    );

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
    ]);

    await tester.tap(find.text(t.projects.bulk.review.validateAll));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(t.common.error), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Retranslate all
  // -------------------------------------------------------------------------

  testWidgets(
      'retranslate all opens the progress dialog and starts the bulk run',
      (tester) async {
    final scope = AsyncValue<BulkScope>.data((
      visible: [matchingProject()],
      matching: [matchingProject()],
    ));

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
      visibleProjectsForBulkProvider.overrideWith((ref) => scope),
      bulkHandlersProvider.overrideWithValue(const _StubBulkHandlers()),
    ]);

    await tester.tap(find.text(t.projects.bulk.review.retranslateAll));
    await tester.pump();
    await tester.pump();

    expect(find.byType(BulkOperationProgressDialog), findsOneWidget);

    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);
  });

  testWidgets(
      'retranslate all is a no-op when no visible project matches the rows',
      (tester) async {
    final scope = AsyncValue<BulkScope>.data((
      visible: const [],
      matching: const [],
    ));

    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
      visibleProjectsForBulkProvider.overrideWith((ref) => scope),
    ]);

    await tester.tap(find.text(t.projects.bulk.review.retranslateAll));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    expect(find.byType(BulkOperationProgressDialog), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Close
  // -------------------------------------------------------------------------

  testWidgets('close pops the dialog', (tester) async {
    await pumpDialog(tester, overrides: [
      bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
    ]);

    expect(find.byType(BulkReviewDialog), findsOneWidget);
    await tester.tap(find.text(t.common.actions.close));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);

    // The dialog is the route's home, so Navigator.pop tears the whole
    // widget down — confirming the close-button onTap path ran.
    expect(find.byType(BulkReviewDialog), findsNothing);
  });
}
