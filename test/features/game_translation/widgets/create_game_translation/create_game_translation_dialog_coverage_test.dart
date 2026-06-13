// Widget coverage tests for the Create-Game-Translation wizard
// (`create_game_translation_dialog.dart`).
//
// The existing `create_game_translation_dialog_test.dart` covers the early
// navigation/validation surface (step 1 render, Next-without-pack, advancing to
// step 2). This file drives the deep, previously-uncovered region: the whole
// `_createProject` flow (happy path with extraction, project/language inserts,
// glossary provisioning, provider invalidation + pop), every failure/rollback
// branch, the progress/log UI, Back navigation, and Cancel.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/game/game_localization_service.dart';
import 'package:twmt/services/glossary/glossary_auto_provisioning_service.dart';
import 'package:twmt/services/projects/i_project_initialization_service.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/widgets/wizard/language_selection_tile.dart';

import '../../../../helpers/test_bootstrap.dart';

class _MockProjectRepo extends Mock implements ProjectRepository {}

class _MockProjectLangRepo extends Mock implements ProjectLanguageRepository {}

class _MockLanguageRepo extends Mock implements LanguageRepository {}

class _MockInitService extends Mock implements IProjectInitializationService {}

class _MockGlossaryProvisioning extends Mock
    implements GlossaryAutoProvisioningService {}

class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _game = ConfiguredGame(code: 'wh3', name: 'WARHAMMER III', path: 'C:/wh3');

GameInstallation _installation({String? installPath = 'C:/games/wh3'}) =>
    GameInstallation(
      id: 'gi-1',
      gameCode: 'wh3',
      gameName: 'WARHAMMER III',
      installationPath: installPath,
      createdAt: 1,
      updatedAt: 1,
    );

Language _lang({required String id, required String code}) => Language(
      id: id,
      code: code,
      name: code.toUpperCase(),
      nativeName: code,
      isActive: true,
    );

DetectedLocalPack _pack(String code) => DetectedLocalPack(
      languageCode: code,
      languageName: code.toUpperCase(),
      packFilePath: 'local_$code.pack',
      fileSizeBytes: 1024,
      lastModified: DateTime(2026, 1, 1),
    );

void main() {
  late _MockProjectRepo projectRepo;
  late _MockProjectLangRepo projectLangRepo;
  late _MockLanguageRepo langRepo;
  late _MockInitService initService;
  late _MockGlossaryProvisioning glossary;
  late StreamController<double> progressController;
  late StreamController<InitializationLogMessage> logController;

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
    initService = _MockInitService();
    glossary = _MockGlossaryProvisioning();
    progressController = StreamController<double>.broadcast();
    logController = StreamController<InitializationLogMessage>.broadcast();

    // Glossary provisioning is fetched directly from the ServiceLocator.
    GetIt.I.registerSingleton<GlossaryAutoProvisioningService>(glossary);
    when(() => glossary.provisionForProject(
          projectId: any(named: 'projectId'),
          targetLanguageIds: any(named: 'targetLanguageIds'),
        )).thenAnswer((_) async {});

    // Source-exclusion lookup: pack 'cn' maps to DB code 'zh'. Return a
    // non-matching language id so the target ('de') is never removed.
    when(() => langRepo.getByCode(any())).thenAnswer(
      (_) async => Ok<Language, TWMTDatabaseException>(
        _lang(id: 'lang-zh', code: 'zh'),
      ),
    );
    when(() => langRepo.getById(any())).thenAnswer(
      (_) async => Ok<Language, TWMTDatabaseException>(
        _lang(id: 'lang-de', code: 'de'),
      ),
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
    when(() => initService.progressStream)
        .thenAnswer((_) => progressController.stream);
    when(() => initService.logStream)
        .thenAnswer((_) => logController.stream);
    when(() => initService.initializeProject(
          projectId: any(named: 'projectId'),
          packFilePath: any(named: 'packFilePath'),
        )).thenAnswer((_) async => Ok<int, ServiceException>(42));
  });

  tearDown(() async {
    await progressController.close();
    await logController.close();
    await ServiceLocator.reset();
  });

  List<Override> overrides({
    List<DetectedLocalPack>? packs,
    List<GameInstallation>? installations,
    List<Language>? languages,
    ConfiguredGame? selectedGame = _game,
  }) =>
      <Override>[
        selectedGameProvider.overrideWith(
          () => _FakeSelectedGame(selectedGame),
        ),
        detectedLocalPacksProvider.overrideWith(
          (ref) async => packs ?? [_pack('cn')],
        ),
        allLanguagesProvider.overrideWith(
          (ref) async => languages ?? [_lang(id: 'lang-de', code: 'de')],
        ),
        allGameInstallationsProvider.overrideWith(
          (ref) async => installations ?? [_installation()],
        ),
        projectRepositoryProvider.overrideWithValue(projectRepo),
        projectLanguageRepositoryProvider.overrideWithValue(projectLangRepo),
        languageRepositoryProvider.overrideWithValue(langRepo),
        projectInitializationServiceProvider.overrideWithValue(initService),
      ];

  Future<void> pumpDialog(
    WidgetTester tester, {
    List<DetectedLocalPack>? packs,
    List<GameInstallation>? installations,
    List<Language>? languages,
    ConfiguredGame? selectedGame = _game,
    bool openViaButton = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final body = openViaButton
        ? Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  useRootNavigator: false,
                  builder: (_) => const CreateGameTranslationDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          )
        : const CreateGameTranslationDialog();

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(
          packs: packs,
          installations: installations,
          languages: languages,
          selectedGame: selectedGame,
        ),
        child: MaterialApp(
          theme: ThemeData.light().copyWith(extensions: [slateTokens]),
          home: Scaffold(body: body),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (openViaButton) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
  }

  // Selects the source pack, advances to step 2, then selects the 'de' target.
  Future<void> advanceToTargetsAndSelect(
    WidgetTester tester, {
    String packCode = 'cn',
  }) async {
    await tester.tap(
      find
          .ancestor(
            of: find.text('local_$packCode.pack'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.gameTranslation.wizard.actions.next));
    await tester.pumpAndSettle();

    // Select the single 'de' target language tile (displayName "DE (de)").
    await tester.tap(find.byType(LanguageSelectionTile).first);
    await tester.pumpAndSettle();
  }

  group('navigation', () {
    testWidgets('Back from step 2 returns to step 1', (tester) async {
      await pumpDialog(tester);

      await tester.tap(
        find
            .ancestor(
              of: find.text('local_cn.pack'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.gameTranslation.wizard.actions.next));
      await tester.pumpAndSettle();

      expect(find.text(t.gameTranslation.wizard.steps.selectTargets),
          findsOneWidget);

      await tester.tap(find.text(t.gameTranslation.wizard.actions.back));
      await tester.pumpAndSettle();

      expect(find.text(t.gameTranslation.wizard.steps.selectSource),
          findsOneWidget);
      expect(find.text(t.gameTranslation.wizard.actions.back), findsNothing);
    });

    testWidgets('Create with no target selected surfaces validation error',
        (tester) async {
      await pumpDialog(tester);

      await tester.tap(
        find
            .ancestor(
              of: find.text('local_cn.pack'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.gameTranslation.wizard.actions.next));
      await tester.pumpAndSettle();

      // On step 2 with nothing selected → Create surfaces the targets error.
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(
        find.text(t.gameTranslation.wizard.errors.selectTargetLanguage),
        findsWidgets,
      );
      verifyNever(() => projectRepo.insert(any()));
    });

    testWidgets('Cancel pops the dialog', (tester) async {
      await pumpDialog(tester, openViaButton: true);

      expect(find.text(t.gameTranslation.wizard.title), findsOneWidget);

      await tester.tap(find.text(t.gameTranslation.wizard.actions.cancel));
      await tester.pumpAndSettle();

      expect(find.text(t.gameTranslation.wizard.title), findsNothing);
    });

    testWidgets('header close button pops the dialog', (tester) async {
      await pumpDialog(tester, openViaButton: true);
      expect(find.text(t.gameTranslation.wizard.title), findsOneWidget);

      await tester.tap(find.byTooltip(t.common.actions.close));
      await tester.pumpAndSettle();

      expect(find.text(t.gameTranslation.wizard.title), findsNothing);
    });
  });

  group('create happy path', () {
    testWidgets(
        'creates project, languages, glossary, extracts and pops with id',
        (tester) async {
      // Gate extraction on a completer so we can assert the progress UI and
      // drive the progress/log listeners before the flow finishes + pops.
      final completer = Completer<Result<int, ServiceException>>();
      when(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer((_) => completer.future);

      await pumpDialog(tester, openViaButton: true);
      await advanceToTargetsAndSelect(tester);

      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      // Pump once to enter the loading/progress state.
      await tester.pump();

      // Progress UI is showing while extraction runs.
      expect(
        find.text(t.gameTranslation.wizard.progress.extracting),
        findsOneWidget,
      );

      // Emit a progress tick and a log line so those listeners run (and the
      // log list + _scrollToBottom render).
      progressController.add(0.5);
      logController.add(InitializationLogMessage(
        message: 'extracting loc files',
        level: InitializationLogLevel.info,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('extracting loc files'), findsOneWidget);

      // Finish extraction successfully; runAsync lets the awaited future and
      // the subscription cancels resolve so the dialog pops.
      await tester.runAsync(() async {
        completer.complete(const Ok<int, ServiceException>(42));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      verify(() => projectRepo.insert(any())).called(1);
      verify(() => projectLangRepo.insert(any())).called(1);
      verify(() => glossary.provisionForProject(
            projectId: any(named: 'projectId'),
            targetLanguageIds: any(named: 'targetLanguageIds'),
          )).called(1);
      verify(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).called(1);
      // Dialog popped on success.
      expect(find.text(t.gameTranslation.wizard.title), findsNothing);
    });

    testWidgets('renders an error-level log line in the progress list',
        (tester) async {
      await pumpDialog(tester);
      await advanceToTargetsAndSelect(tester);

      // Make extraction hang so the progress UI stays visible while we assert.
      final completer = Completer<Result<int, ServiceException>>();
      when(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer((_) => completer.future);

      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pump();

      logController.add(InitializationLogMessage(
        message: 'something failed during extraction',
        level: InitializationLogLevel.error,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('something failed during extraction'), findsOneWidget);

      // Finish extraction as an error so the loading spinner is torn down and
      // no timer/animation leaks. runAsync resolves the awaited future + the
      // subscription cancels.
      await tester.runAsync(() async {
        completer.complete(
          Err<int, ServiceException>(ServiceException('done')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    });
  });

  group('create failure / rollback branches', () {
    testWidgets('no game selected → error banner, no insert', (tester) async {
      // selectedGame null means step 1 still renders (StepSelectSource handles
      // null), but creation aborts on the "No game selected" guard. Packs are
      // provided explicitly because detectedLocalPacksProvider is overridden.
      await pumpDialog(tester, selectedGame: null);

      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(find.textContaining('No game selected'), findsOneWidget);
      verifyNever(() => projectRepo.insert(any()));
    });

    testWidgets('game installation not found → error banner', (tester) async {
      await pumpDialog(tester, installations: const []);

      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(find.textContaining('Game installation not found'), findsOneWidget);
      verifyNever(() => projectRepo.insert(any()));
    });

    testWidgets('installation without path → error banner', (tester) async {
      await pumpDialog(tester, installations: [_installation(installPath: null)]);

      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Game installation path is not configured'),
        findsOneWidget,
      );
      verifyNever(() => projectRepo.insert(any()));
    });

    testWidgets('source pack equals only target → targets-empty guard',
        (tester) async {
      // getByCode resolves the source pack to lang-de, which is the only
      // selected target — it gets removed, leaving the set empty and tripping
      // the in-flow "select target language" guard.
      when(() => langRepo.getByCode(any())).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'lang-de', code: 'de'),
        ),
      );

      await pumpDialog(tester);
      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(t.gameTranslation.wizard.errors.selectTargetLanguage),
        findsWidgets,
      );
      verifyNever(() => projectRepo.insert(any()));
    });

    testWidgets('project insert failure surfaces error, no rollback',
        (tester) async {
      when(() => projectRepo.insert(any())).thenAnswer(
        (_) async => Err<Project, TWMTDatabaseException>(
          TWMTDatabaseException('insert blew up'),
        ),
      );

      await pumpDialog(tester);
      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(find.textContaining('insert blew up'), findsOneWidget);
      // createdProjectId never set → no rollback delete.
      verifyNever(() => projectRepo.delete(any()));
      verifyNever(() => projectLangRepo.insert(any()));
    });

    testWidgets('project-language insert failure rolls back the project',
        (tester) async {
      when(() => projectLangRepo.insert(any())).thenAnswer(
        (_) async => Err<ProjectLanguage, TWMTDatabaseException>(
          TWMTDatabaseException('lang insert failed'),
        ),
      );

      await pumpDialog(tester);
      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      expect(find.textContaining('lang insert failed'), findsOneWidget);
      verify(() => projectRepo.delete(any())).called(1);
    });

    testWidgets('initialization failure rolls back the project',
        (tester) async {
      when(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer(
        (_) async => Err<int, ServiceException>(ServiceException('pack boom')),
      );

      await pumpDialog(tester);
      await advanceToTargetsAndSelect(tester);
      // runAsync lets the real event loop turn so the awaited init future and
      // the stream-subscription cancels in `_createProject`'s finally resolve.
      await tester.runAsync(() async {
        await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.textContaining('pack boom'), findsOneWidget);
      verify(() => projectRepo.delete(any())).called(1);
    });

    testWidgets('rollback tolerates a delete failure', (tester) async {
      when(() => projectLangRepo.insert(any())).thenAnswer(
        (_) async => Err<ProjectLanguage, TWMTDatabaseException>(
          TWMTDatabaseException('lang insert failed'),
        ),
      );
      when(() => projectRepo.delete(any())).thenThrow(Exception('db down'));

      await pumpDialog(tester);
      await advanceToTargetsAndSelect(tester);
      await tester.tap(find.text(t.gameTranslation.wizard.actions.create));
      await tester.pumpAndSettle();

      // Original error still surfaces despite the failed cleanup.
      expect(find.textContaining('lang insert failed'), findsOneWidget);
    });
  });
}
