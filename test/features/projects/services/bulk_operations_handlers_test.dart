import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';
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
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/services/translation/i_validation_service.dart';

// ---------------------------------------------------------------------------
// Mocks / Fakes
// ---------------------------------------------------------------------------

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockModelRepo extends Mock implements LlmProviderModelRepository {}

class _MockValidationService extends Mock implements IValidationService {}

class _MockRunner extends Mock implements HeadlessBatchTranslationRunner {}

class _MockExportService extends Mock implements ExportOrchestratorService {}

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
  _FakeLang({
    required this.projectLanguage,
    Language? language,
    this.translatedUnits = 0,
    this.needsReviewUnits = 0,
  }) : _language = language;

  @override
  final ProjectLanguage projectLanguage;
  final Language? _language;
  @override
  Language? get language => _language;
  @override
  final int translatedUnits;
  @override
  final int needsReviewUnits;
}

class _FakeProjectWithDetails extends Fake implements ProjectWithDetails {
  _FakeProjectWithDetails({required this.project, required this.languages});
  @override
  final Project project;
  @override
  final List<ProjectLanguageWithInfo> languages;
}

// Fake notifiers for the codegen providers.
class _FakeSelectedLlmModel extends SelectedLlmModel {
  _FakeSelectedLlmModel(this._value);
  final String? _value;
  @override
  String? build() => _value;
}

class _FakeLlmProviderSettings extends LlmProviderSettings {
  _FakeLlmProviderSettings(this._value);
  final Map<String, String> _value;
  @override
  Future<Map<String, String>> build() async => _value;
}

/// Exposes the container's [Ref] so handler functions (which require a `Ref`)
/// can be driven directly in tests.
final _refExposeProvider = Provider<Ref>((ref) => ref);

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ProjectWithDetails _project({
  String id = 'proj-1',
  List<ProjectLanguageWithInfo> languages = const [],
}) =>
    _FakeProjectWithDetails(project: _FakeProject(id), languages: languages);

ProjectLanguageWithInfo _lang({
  String code = 'fr',
  String projectLanguageId = 'pl-1',
  int translatedUnits = 0,
  int needsReviewUnits = 0,
}) =>
    _FakeLang(
      projectLanguage: _FakeProjectLanguage(projectLanguageId),
      language: _FakeLanguage(code),
      translatedUnits: translatedUnits,
      needsReviewUnits: needsReviewUnits,
    );

/// Wires every provider the handlers may touch.
ProviderContainer _container({
  required _MockVersionRepo versionRepo,
  _MockUnitRepo? unitRepo,
  _MockValidationService? validationService,
  _MockRunner? runner,
  _MockExportService? exportService,
  _MockModelRepo? modelRepo,
  String? selectedModelId,
  Map<String, String> settings = const {'active_llm_provider': 'anthropic'},
}) {
  return ProviderContainer(
    overrides: [
      translationVersionRepositoryProvider.overrideWithValue(versionRepo),
      translationUnitRepositoryProvider
          .overrideWithValue(unitRepo ?? _MockUnitRepo()),
      validationServiceProvider
          .overrideWithValue(validationService ?? _MockValidationService()),
      headlessBatchTranslationRunnerProvider
          .overrideWithValue(runner ?? _MockRunner()),
      exportOrchestratorServiceProvider
          .overrideWithValue(exportService ?? _MockExportService()),
      llmProviderModelRepositoryProvider
          .overrideWithValue(modelRepo ?? _MockModelRepo()),
      selectedLlmModelProvider
          .overrideWith(() => _FakeSelectedLlmModel(selectedModelId)),
      llmProviderSettingsProvider
          .overrideWith(() => _FakeLlmProviderSettings(settings)),
    ],
  );
}

Ref _refOf(ProviderContainer c) => c.read(_refExposeProvider);

/// Stubs the version repo so [runHeadlessValidationRescan] returns all-zeros
/// (no translated versions => no validation work).
void _stubEmptyRescan(_MockVersionRepo repo) {
  when(() => repo.normalizeStatusEncoding())
      .thenAnswer((_) async => const Ok(0));
  when(() => repo.getByProjectLanguage(any()))
      .thenAnswer((_) async => const Ok([]));
}

/// Common runner.run() stub returning [count] translated units.
void _stubRunnerRun(_MockRunner runner, int count) {
  when(() => runner.run(
        projectLanguageId: any(named: 'projectLanguageId'),
        projectId: any(named: 'projectId'),
        unitIds: any(named: 'unitIds'),
        skipTM: any(named: 'skipTM'),
        providerId: any(named: 'providerId'),
        modelId: any(named: 'modelId'),
        onProgress: any(named: 'onProgress'),
      )).thenAnswer((_) async => count);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // translationSettingsProvider.build() loads SharedPreferences async; the
    // handlers only read its synchronous default, but the async load must not
    // throw MissingPluginException.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registerFallbackValue(<String>[]);
  });

  // ----- runBulkTranslate ---------------------------------------------------

  group('runBulkTranslate', () {
    test('skips when target language not configured', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang(code: 'de')]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when no untranslated units', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getUntranslatedIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok([]));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('fails when no LLM model and no active provider', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getUntranslatedIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok(['u1']));
      final container = _container(versionRepo: versionRepo, settings: const {});
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
    });

    test('succeeds using active provider setting (modelId null)', () async {
      final versionRepo = _MockVersionRepo();
      final runner = _MockRunner();
      final steps = <String>[];
      when(() => versionRepo.getUntranslatedIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok(['u1', 'u2']));
      _stubEmptyRescan(versionRepo);
      _stubRunnerRun(runner, 2);

      final container = _container(versionRepo: versionRepo, runner: runner);
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
        onProgress: (s, p) => steps.add(s),
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
      final captured = verify(() => runner.run(
            projectLanguageId: any(named: 'projectLanguageId'),
            projectId: any(named: 'projectId'),
            unitIds: any(named: 'unitIds'),
            skipTM: any(named: 'skipTM'),
            providerId: captureAny(named: 'providerId'),
            modelId: captureAny(named: 'modelId'),
            onProgress: any(named: 'onProgress'),
          )).captured;
      expect(captured[0], 'provider_anthropic');
      expect(captured[1], isNull);
    });

    test('succeeds resolving provider via selected model row', () async {
      final versionRepo = _MockVersionRepo();
      final runner = _MockRunner();
      final modelRepo = _MockModelRepo();
      when(() => versionRepo.getUntranslatedIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok(['u1']));
      _stubEmptyRescan(versionRepo);
      when(() => modelRepo.getById('model-1'))
          .thenAnswer((_) async => Ok(_FakeModel('openai', 'gpt-4o')));
      _stubRunnerRun(runner, 1);

      final container = _container(
        versionRepo: versionRepo,
        runner: runner,
        modelRepo: modelRepo,
        selectedModelId: 'model-1',
      );
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
      final captured = verify(() => runner.run(
            projectLanguageId: any(named: 'projectLanguageId'),
            projectId: any(named: 'projectId'),
            unitIds: any(named: 'unitIds'),
            skipTM: any(named: 'skipTM'),
            providerId: captureAny(named: 'providerId'),
            modelId: captureAny(named: 'modelId'),
            onProgress: any(named: 'onProgress'),
          )).captured;
      expect(captured[0], 'provider_openai');
      expect(captured[1], 'gpt-4o');
    });

    test('falls back to active provider when model lookup fails', () async {
      final versionRepo = _MockVersionRepo();
      final runner = _MockRunner();
      final modelRepo = _MockModelRepo();
      when(() => versionRepo.getUntranslatedIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok(['u1']));
      _stubEmptyRescan(versionRepo);
      when(() => modelRepo.getById('model-x')).thenAnswer(
          (_) async => const Err(TWMTDatabaseException('not found')));
      _stubRunnerRun(runner, 1);

      final container = _container(
        versionRepo: versionRepo,
        runner: runner,
        modelRepo: modelRepo,
        selectedModelId: 'model-x',
      );
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
    });

    test('fails when repo throws', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getUntranslatedIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenThrow(StateError('boom'));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
      expect(outcome.error, isNotNull);
    });
  });

  // ----- runBulkTranslateReviews -------------------------------------------

  group('runBulkTranslateReviews', () {
    test('skips when target language not configured', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkTranslateReviews(
        ref: _refOf(container),
        project: _project(languages: [_lang(code: 'de')]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when no needsReview units on language', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkTranslateReviews(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 0)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when needsReview rows resolve to empty', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getNeedsReviewRows(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok([]));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkTranslateReviews(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 3)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('fails when no LLM model resolved', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getNeedsReviewRows(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => Ok([
            const NeedsReviewRow(
              unitId: 'u1',
              versionId: 'v1',
              key: 'k',
              sourceText: 's',
              translatedText: 't',
            ),
          ]));
      final container = _container(versionRepo: versionRepo, settings: const {});
      addTearDown(container.dispose);

      final outcome = await runBulkTranslateReviews(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 1)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
    });

    test('succeeds and forces skipTM = true', () async {
      final versionRepo = _MockVersionRepo();
      final runner = _MockRunner();
      when(() => versionRepo.getNeedsReviewRows(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => Ok([
            const NeedsReviewRow(
              unitId: 'u1',
              versionId: 'v1',
              key: 'k',
              sourceText: 's',
              translatedText: 't',
            ),
          ]));
      _stubRunnerRun(runner, 1);
      final container = _container(versionRepo: versionRepo, runner: runner);
      addTearDown(container.dispose);

      final outcome = await runBulkTranslateReviews(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 1)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
      final captured = verify(() => runner.run(
            projectLanguageId: any(named: 'projectLanguageId'),
            projectId: any(named: 'projectId'),
            unitIds: any(named: 'unitIds'),
            skipTM: captureAny(named: 'skipTM'),
            providerId: any(named: 'providerId'),
            modelId: any(named: 'modelId'),
            onProgress: any(named: 'onProgress'),
          )).captured;
      expect(captured.single, isTrue);
    });

    test('fails when repo throws', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getNeedsReviewRows(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenThrow(StateError('boom'));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkTranslateReviews(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 2)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
    });
  });

  // ----- runBulkRescan ------------------------------------------------------

  group('runBulkRescan', () {
    test('skips when target language not configured', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkRescan(
        ref: _refOf(container),
        project: _project(languages: [_lang(code: 'de')]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when no translated units', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkRescan(
        ref: _refOf(container),
        project: _project(languages: [_lang(translatedUnits: 0)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('succeeds running the rescan', () async {
      final versionRepo = _MockVersionRepo();
      _stubEmptyRescan(versionRepo);
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkRescan(
        ref: _refOf(container),
        project: _project(languages: [_lang(translatedUnits: 5)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
    });

    test('fails when rescan throws', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.normalizeStatusEncoding())
          .thenThrow(StateError('boom'));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkRescan(
        ref: _refOf(container),
        project: _project(languages: [_lang(translatedUnits: 5)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
    });
  });

  // ----- runBulkForceValidate ----------------------------------------------

  group('runBulkForceValidate', () {
    test('skips when target language not configured', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkForceValidate(
        ref: _refOf(container),
        project: _project(languages: [_lang(code: 'de')]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when no needsReview units', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkForceValidate(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 0)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('skips when needsReview ids resolve to empty', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getNeedsReviewIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok([]));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkForceValidate(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 2)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('succeeds clearing flags', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getNeedsReviewIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer((_) async => const Ok(['v1', 'v2']));
      when(() => versionRepo.acceptBatch(any()))
          .thenAnswer((_) async => const Ok(2));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkForceValidate(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 2)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
      verify(() => versionRepo.acceptBatch(['v1', 'v2'])).called(1);
    });

    test('fails when repo throws', () async {
      final versionRepo = _MockVersionRepo();
      when(() => versionRepo.getNeedsReviewIds(
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenThrow(StateError('boom'));
      final container = _container(versionRepo: versionRepo);
      addTearDown(container.dispose);

      final outcome = await runBulkForceValidate(
        ref: _refOf(container),
        project: _project(languages: [_lang(needsReviewUnits: 2)]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
    });
  });

  // ----- runBulkGeneratePack ------------------------------------------------

  group('runBulkGeneratePack', () {
    test('skips when target language not configured', () async {
      final container = _container(versionRepo: _MockVersionRepo());
      addTearDown(container.dispose);

      final outcome = await runBulkGeneratePack(
        ref: _refOf(container),
        project: _project(languages: [_lang(code: 'de')]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
    });

    test('succeeds when export returns Ok and drives progress', () async {
      final exportService = _MockExportService();
      final steps = <String>[];
      when(() => exportService.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            generatePackImage: any(named: 'generatePackImage'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((invocation) async {
        final cb = invocation.namedArguments[#onProgress]
            as ExportProgressCallback?;
        cb?.call('writing', 0.5);
        return const Ok(ExportResult(
          outputPath: 'out.pack',
          entryCount: 42,
          fileSize: 2 * 1024 * 1024,
          languageCodes: ['fr'],
        ));
      });
      final container = _container(
        versionRepo: _MockVersionRepo(),
        exportService: exportService,
      );
      addTearDown(container.dispose);

      final outcome = await runBulkGeneratePack(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
        onProgress: (s, p) => steps.add(s),
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
      expect(steps, contains('writing'));
    });

    test('succeeds without onProgress (null callback branch)', () async {
      final exportService = _MockExportService();
      when(() => exportService.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            generatePackImage: any(named: 'generatePackImage'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => const Ok(ExportResult(
            outputPath: 'out.pack',
            entryCount: 1,
            fileSize: 1024,
            languageCodes: ['fr'],
          )));
      final container = _container(
        versionRepo: _MockVersionRepo(),
        exportService: exportService,
      );
      addTearDown(container.dispose);

      final outcome = await runBulkGeneratePack(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.succeeded);
    });

    test('fails when export returns Err', () async {
      final exportService = _MockExportService();
      when(() => exportService.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            generatePackImage: any(named: 'generatePackImage'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
          (_) async => const Err(FileServiceException('export failed')));
      final container = _container(
        versionRepo: _MockVersionRepo(),
        exportService: exportService,
      );
      addTearDown(container.dispose);

      final outcome = await runBulkGeneratePack(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
      expect(outcome.error, isNotNull);
    });

    test('fails when export throws', () async {
      final exportService = _MockExportService();
      when(() => exportService.exportToPack(
            projectId: any(named: 'projectId'),
            languageCodes: any(named: 'languageCodes'),
            outputPath: any(named: 'outputPath'),
            validatedOnly: any(named: 'validatedOnly'),
            generatePackImage: any(named: 'generatePackImage'),
            onProgress: any(named: 'onProgress'),
          )).thenThrow(StateError('boom'));
      final container = _container(
        versionRepo: _MockVersionRepo(),
        exportService: exportService,
      );
      addTearDown(container.dispose);

      final outcome = await runBulkGeneratePack(
        ref: _refOf(container),
        project: _project(languages: [_lang()]),
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.failed);
    });
  });
}
