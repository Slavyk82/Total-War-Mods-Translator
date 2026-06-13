// Widget coverage tests for the Create-Project wizard.
//
// Covers two source files end-to-end:
//   * step_basic_info.dart  — rendered in isolation (manual entry + auto-filled
//     detected-mod variants) so its fields, dropdown and loading branches run.
//   * create_project_dialog.dart — the 2-step wizard: navigation between steps,
//     validation, and the `_createProject` happy/sad paths.
//
// The top-level `resolveDefaultTargetLanguage` and
// `initializeProjectFilesOrRollback` helpers are exercised by dedicated unit
// tests elsewhere and are not re-tested here.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/widgets/create_project/create_project_dialog.dart';
import 'package:twmt/features/projects/widgets/create_project/project_creation_state.dart';
import 'package:twmt/features/projects/widgets/create_project/step_basic_info.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/glossary/glossary_auto_provisioning_service.dart';
import 'package:twmt/services/projects/i_project_initialization_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

import '../../../../helpers/test_bootstrap.dart';

class _MockProjectRepo extends Mock implements ProjectRepository {}

class _MockProjectLangRepo extends Mock implements ProjectLanguageRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockSettings extends Mock implements SettingsService {}

class _MockWorkshopRepo extends Mock implements WorkshopModRepository {}

class _MockInitService extends Mock implements IProjectInitializationService {}

class _MockGlossaryProvisioning extends Mock
    implements GlossaryAutoProvisioningService {}

GameInstallation _game({
  required String id,
  String name = 'WARHAMMER III',
  String? appId = '1142710',
  String? installPath = 'C:/games/wh3',
}) {
  return GameInstallation(
    id: id,
    gameCode: 'wh3',
    gameName: name,
    installationPath: installPath,
    steamAppId: appId,
    createdAt: 1,
    updatedAt: 1,
  );
}

Language _lang({String id = 'lang-de', String code = 'de'}) => Language(
      id: id,
      code: code,
      name: code.toUpperCase(),
      nativeName: code,
      isActive: true,
    );

DetectedMod _detectedMod() => const DetectedMod(
      workshopId: '99887766',
      name: 'My Cool Mod',
      packFilePath: 'C:/workshop/mod.pack',
      imageUrl: 'http://img',
    );

WorkshopMod _workshopMod() => const WorkshopMod(
      id: 'wm-1',
      workshopId: '99887766',
      title: 'My Cool Mod',
      appId: 1142710,
      workshopUrl: 'http://workshop',
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  late _MockProjectRepo projectRepo;
  late _MockProjectLangRepo projectLangRepo;
  late _MockLanguageRepo langRepo;
  late _MockSettings settings;
  late _MockWorkshopRepo workshopRepo;
  late _MockInitService initService;
  late _MockGlossaryProvisioning glossary;

  setUpAll(() {
    registerFallbackValue(
      const Project(
        id: 'x',
        name: 'x',
        gameInstallationId: 'g',
        batchSize: 25,
        parallelBatches: 3,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    registerFallbackValue(
      const ProjectLanguage(
        id: 'x',
        projectId: 'p',
        languageId: 'l',
        progressPercent: 0,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    projectRepo = _MockProjectRepo();
    projectLangRepo = _MockProjectLangRepo();
    langRepo = _MockLanguageRepo();
    settings = _MockSettings();
    workshopRepo = _MockWorkshopRepo();
    initService = _MockInitService();
    glossary = _MockGlossaryProvisioning();

    // Glossary provisioning is fetched directly from the ServiceLocator.
    GetIt.I.registerSingleton<GlossaryAutoProvisioningService>(glossary);
    when(() => glossary.provisionForProject(
          projectId: any(named: 'projectId'),
          targetLanguageIds: any(named: 'targetLanguageIds'),
        )).thenAnswer((_) async {});

    when(() => settings.getString(
          any(),
          defaultValue: any(named: 'defaultValue'),
        )).thenAnswer((_) async => 'de');
    when(() => settings.getString(any()))
        .thenAnswer((_) async => 'C:/rpfm/schema');
    when(() => langRepo.getByCode(any())).thenAnswer(
      (_) async => Ok<Language, TWMTDatabaseException>(_lang()),
    );
    when(() => projectRepo.insert(any())).thenAnswer(
      (inv) async => Ok<Project, TWMTDatabaseException>(
        inv.positionalArguments.first as Project,
      ),
    );
    when(() => projectRepo.delete(any())).thenAnswer(
      (_) async => Ok<void, TWMTDatabaseException>(null),
    );
    when(() => projectLangRepo.insert(any())).thenAnswer(
      (inv) async => Ok<ProjectLanguage, TWMTDatabaseException>(
        inv.positionalArguments.first as ProjectLanguage,
      ),
    );
    when(() => workshopRepo.getByWorkshopId(any())).thenAnswer(
      (_) async => Ok<WorkshopMod, TWMTDatabaseException>(_workshopMod()),
    );
    when(() => initService.logStream).thenAnswer(
      (_) => const Stream<InitializationLogMessage>.empty(),
    );
    when(() => initService.initializeProject(
          projectId: any(named: 'projectId'),
          packFilePath: any(named: 'packFilePath'),
        )).thenAnswer((_) async => Ok<int, ServiceException>(7));
  });

  tearDown(() async {
    await ServiceLocator.reset();
  });

  List<Override> overrides({List<GameInstallation>? games}) => <Override>[
        allGameInstallationsProvider.overrideWith(
          (ref) async => games ?? [_game(id: 'g1')],
        ),
        projectRepositoryProvider.overrideWithValue(projectRepo),
        projectLanguageRepositoryProvider.overrideWithValue(projectLangRepo),
        languageRepositoryProvider.overrideWithValue(langRepo),
        settingsServiceProvider.overrideWithValue(settings),
        workshopModRepositoryProvider.overrideWithValue(workshopRepo),
        projectInitializationServiceProvider.overrideWithValue(initService),
      ];

  Future<void> pumpDialog(
    WidgetTester tester, {
    DetectedMod? detectedMod,
    List<GameInstallation>? games,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(games: games),
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(
            body: CreateProjectDialog(detectedMod: detectedMod),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------------
  // step_basic_info.dart in isolation
  // -------------------------------------------------------------------------
  group('StepBasicInfo', () {
    Future<void> pumpStep(
      WidgetTester tester, {
      required ProjectCreationState state,
      List<GameInstallation>? games,
    }) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(games: games),
          child: MaterialApp(
            theme: ThemeData.light().copyWith(extensions: [slateTokens]),
            home: Scaffold(
              // StatefulBuilder so the step's setState-driven callbacks rebuild.
              body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: StepBasicInfo(state: state, formKey: formKey),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('manual entry renders name field + game dropdown',
        (tester) async {
      final state = ProjectCreationState();
      addTearDown(state.dispose);

      await pumpStep(tester, state: state);

      expect(
        find.text(t.projects.createProject.basicInfo.descriptionManual),
        findsOneWidget,
      );
      expect(
        find.text(t.projects.createProject.basicInfo.fieldProjectName),
        findsOneWidget,
      );
      expect(
        find.text(t.projects.createProject.basicInfo.fieldGame),
        findsOneWidget,
      );
    });

    testWidgets('typing into the name field updates the controller',
        (tester) async {
      final state = ProjectCreationState();
      addTearDown(state.dispose);

      await pumpStep(tester, state: state);

      await tester.enterText(find.byType(TextField).first, 'Hello Project');
      await tester.pump();

      expect(state.nameController.text, 'Hello Project');
    });

    testWidgets('selecting a game from the dropdown sets selectedGameId',
        (tester) async {
      final state = ProjectCreationState();
      addTearDown(state.dispose);

      await pumpStep(
        tester,
        state: state,
        games: [
          _game(id: 'g1', name: 'WARHAMMER III'),
          _game(id: 'g2', name: 'TROY'),
        ],
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      // Tap the second game option in the opened menu.
      await tester.tap(find.text('TROY').last);
      await tester.pumpAndSettle();

      expect(state.selectedGameId, 'g2');
    });

    testWidgets('game-load error surfaces the error message', (tester) async {
      final state = ProjectCreationState();
      addTearDown(state.dispose);

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allGameInstallationsProvider.overrideWith(
              (ref) async => throw Exception('boom'),
            ),
            ...overrides().sublist(1),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(extensions: [slateTokens]),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StepBasicInfo(state: state, formKey: formKey),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The error branch of `_buildGameSelection` renders the localized string.
      expect(
        find.textContaining('boom'),
        findsOneWidget,
      );
    });

    testWidgets('auto-filled detected-mod variant loads workshop data',
        (tester) async {
      final state = ProjectCreationState(detectedMod: _detectedMod());
      addTearDown(state.dispose);

      await pumpStep(tester, state: state);

      // The read-only summary rows render the auto-filled description.
      expect(
        find.text(t.projects.createProject.basicInfo.descriptionAutoFilled),
        findsOneWidget,
      );
      // The workshop load resolved the workshop mod + matching game.
      expect(state.workshopMod, isNotNull);
      expect(state.selectedGameId, 'g1');
      verify(() => workshopRepo.getByWorkshopId('99887766')).called(1);
    });

    testWidgets('detected-mod load tolerates a repo error', (tester) async {
      when(() => workshopRepo.getByWorkshopId(any())).thenAnswer(
        (_) async => Err<WorkshopMod, TWMTDatabaseException>(
          TWMTDatabaseException('not found'),
        ),
      );
      final state = ProjectCreationState(detectedMod: _detectedMod());
      addTearDown(state.dispose);

      await pumpStep(tester, state: state);

      // Still renders the auto-filled summary; no workshop mod resolved.
      expect(
        find.text(t.projects.createProject.basicInfo.descriptionAutoFilled),
        findsOneWidget,
      );
      expect(state.workshopMod, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // create_project_dialog.dart wizard
  // -------------------------------------------------------------------------
  group('CreateProjectDialog', () {
    testWidgets('opens on step 1 with header, step title and footer actions',
        (tester) async {
      await pumpDialog(tester);

      expect(find.text(t.projects.createProject.title), findsOneWidget);
      expect(find.text(t.projects.createProject.steps.basicInfo), findsOneWidget);
      expect(find.text(t.projects.createProject.actions.next), findsOneWidget);
      expect(find.text(t.common.actions.cancel), findsOneWidget);
      // No Back button on the first manual step.
      expect(find.text(t.common.actions.back), findsNothing);
    });

    testWidgets('Next with no game selected surfaces the selectGame error',
        (tester) async {
      await pumpDialog(tester);

      // Provide a name so form validation passes; game stays unselected.
      await tester.enterText(find.byType(TextField).first, 'Proj');
      await tester.tap(find.text(t.projects.createProject.actions.next));
      await tester.pumpAndSettle();

      expect(
        find.text(t.projects.createProject.errors.selectGame),
        findsOneWidget,
      );
      // Still on step 1.
      expect(find.text(t.projects.createProject.steps.basicInfo), findsOneWidget);
    });

    testWidgets('selecting a game then Next advances to settings step and Back '
        'returns', (tester) async {
      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'Proj');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WARHAMMER III').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.projects.createProject.actions.next));
      await tester.pumpAndSettle();

      // Now on translation settings step.
      expect(
        find.text(t.projects.createProject.steps.translationSettings),
        findsOneWidget,
      );
      expect(find.text(t.projects.createProject.actions.create), findsOneWidget);
      expect(find.text(t.common.actions.back), findsOneWidget);

      // Back returns to step 1.
      await tester.tap(find.text(t.common.actions.back));
      await tester.pumpAndSettle();
      expect(find.text(t.projects.createProject.steps.basicInfo), findsOneWidget);
    });

    testWidgets('Cancel pops the dialog', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: ThemeData.light().copyWith(extensions: [slateTokens]),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog(
                      context: context,
                      useRootNavigator: false,
                      builder: (_) => const CreateProjectDialog(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(t.projects.createProject.title), findsOneWidget);

      await tester.tap(find.text(t.common.actions.cancel));
      await tester.pumpAndSettle();
      expect(find.text(t.projects.createProject.title), findsNothing);
    });

    testWidgets('create with no source file inserts project + language and pops',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(games: [_game(id: 'g1')]),
          child: MaterialApp(
            theme: ThemeData.light().copyWith(extensions: [slateTokens]),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await showDialog(
                        context: context,
                        useRootNavigator: false,
                        builder: (_) => const CreateProjectDialog(),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Step 1: name + game.
      await tester.enterText(find.byType(TextField).first, 'New Project');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WARHAMMER III').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.projects.createProject.actions.next));
      await tester.pumpAndSettle();

      // Step 2: create (no source file → success toast, then pop). The
      // success toast schedules a ~4s dismissal timer on the root overlay;
      // drain it so the test ends with no pending timers.
      await tester.tap(find.text(t.projects.createProject.actions.create));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      verify(() => projectRepo.insert(any())).called(1);
      verify(() => projectLangRepo.insert(any())).called(1);
      verify(() => glossary.provisionForProject(
            projectId: any(named: 'projectId'),
            targetLanguageIds: any(named: 'targetLanguageIds'),
          )).called(1);
      // Dialog popped on success.
      expect(find.text(t.projects.createProject.title), findsNothing);
    });

    testWidgets('create surfaces the error banner when project insert fails',
        (tester) async {
      when(() => projectRepo.insert(any())).thenAnswer(
        (_) async => Err<Project, TWMTDatabaseException>(
          TWMTDatabaseException('insert blew up'),
        ),
      );

      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'New Project');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WARHAMMER III').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.projects.createProject.actions.next));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.projects.createProject.actions.create));
      await tester.pumpAndSettle();

      // The error banner surfaces the failure; dialog stays open.
      expect(find.textContaining('insert blew up'), findsOneWidget);
      verifyNever(() => projectLangRepo.insert(any()));
    });

    testWidgets(
        'detected-mod dialog opens directly on the settings step (step 1 '
        'skipped)', (tester) async {
      await pumpDialog(tester, detectedMod: _detectedMod());

      // Step 1 is skipped: we start on translation settings with no Back button
      // (current step == minStep == 1), and the Create action is shown.
      expect(
        find.text(t.projects.createProject.steps.translationSettings),
        findsOneWidget,
      );
      expect(find.text(t.projects.createProject.actions.create), findsOneWidget);
      // No Back button because current step == minStep.
      expect(find.text(t.common.actions.back), findsNothing);
    });

    testWidgets(
        'create from skipped detected-mod step (no resolved game) surfaces the '
        'gameMustBeSelected error', (tester) async {
      // When step 1 is skipped the basic-info step never runs its workshop
      // load, so neither selectedGameId nor workshopMod is set and the
      // `_createProject` game-resolution guard fails.
      await pumpDialog(tester, detectedMod: _detectedMod());

      await tester.tap(find.text(t.projects.createProject.actions.create));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(t.projects.createProject.errors.gameMustBeSelected),
        findsOneWidget,
      );
      // No project row was inserted because creation aborted on the guard.
      verifyNever(() => projectRepo.insert(any()));
    });

    testWidgets('project-language insert failure rolls back the project',
        (tester) async {
      when(() => projectLangRepo.insert(any())).thenAnswer(
        (_) async => Err<ProjectLanguage, TWMTDatabaseException>(
          TWMTDatabaseException('lang insert failed'),
        ),
      );

      await pumpDialog(tester);

      await tester.enterText(find.byType(TextField).first, 'New Project');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WARHAMMER III').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.projects.createProject.actions.next));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.projects.createProject.actions.create));
      await tester.pumpAndSettle();

      expect(find.textContaining('lang insert failed'), findsOneWidget);
      verify(() => projectRepo.delete(any())).called(1);
    });
  });

  // -------------------------------------------------------------------------
  // initializeProjectFilesOrRollback (top-level helper used by the dialog).
  // The dialog's UI wrapper `_initializeProjectFiles` is only reachable for a
  // detected-mod project after its basic-info step has resolved a game, which
  // the wizard skips — so we drive the underlying rollback decision directly.
  // -------------------------------------------------------------------------
  group('initializeProjectFilesOrRollback', () {
    test('schema unconfigured → rolls back without touching the init service',
        () async {
      final outcome = await initializeProjectFilesOrRollback(
        initService: initService,
        projectRepo: projectRepo,
        projectId: 'p1',
        packFilePath: 'C:/m/a.pack',
        schemaPath: '   ',
      );

      expect(outcome.success, isFalse);
      expect(outcome.failure, ProjectInitFailure.schemaNotConfigured);
      verify(() => projectRepo.delete('p1')).called(1);
      verifyNever(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          ));
    });

    test('init error → rolls back and reports the error', () async {
      when(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer((_) async =>
          Err<int, ServiceException>(ServiceException('boom pack')));

      final outcome = await initializeProjectFilesOrRollback(
        initService: initService,
        projectRepo: projectRepo,
        projectId: 'p2',
        packFilePath: 'C:/m/b.pack',
        schemaPath: 'C:/schema',
      );

      expect(outcome.success, isFalse);
      expect(outcome.failure, ProjectInitFailure.initError);
      expect(outcome.error, contains('boom pack'));
      verify(() => projectRepo.delete('p2')).called(1);
    });

    test('success → no rollback, reports unit count', () async {
      final outcome = await initializeProjectFilesOrRollback(
        initService: initService,
        projectRepo: projectRepo,
        projectId: 'p3',
        packFilePath: 'C:/m/c.pack',
        schemaPath: 'C:/schema',
      );

      expect(outcome.success, isTrue);
      expect(outcome.unitsImported, 7);
      verifyNever(() => projectRepo.delete(any()));
    });

    test('rollback tolerates a delete failure', () async {
      when(() => projectRepo.delete(any())).thenThrow(Exception('db down'));

      final outcome = await initializeProjectFilesOrRollback(
        initService: initService,
        projectRepo: projectRepo,
        projectId: 'p4',
        packFilePath: 'C:/m/d.pack',
        schemaPath: null,
      );

      expect(outcome.failure, ProjectInitFailure.schemaNotConfigured);
    });
  });
}
