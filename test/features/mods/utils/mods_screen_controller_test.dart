import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/utils/mods_screen_controller.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';
import 'package:twmt/services/projects/i_project_initialization_service.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// Regression tests for ModsScreenController.
//
// M26 — handleRefresh(): the listenManual completion condition used to be
// `next.hasValue && !next.isLoading`. A rescan that errors with no retained
// data settles as AsyncError with hasValue == false, so the condition never
// fired: modsLoadingState stayed true forever (toolbar stuck on
// 'Rescanning…') and the subscription leaked on every retry. The listener
// must also complete on error.
//
// M28 — _createProjectFromMod(): the try/catch used to extend past the
// successful initialization, and its catch unconditionally ran
// service.deleteProject(projectId) — an exception in a post-creation step
// (provider refresh / updateModImported / navigation) deleted the fully
// initialized project and showed a misleading 'Failed to create project'
// toast. Post-creation errors must leave the project intact and surface a
// 'Project created, but…' warning instead.

class _MockProjectRepository extends Mock implements ProjectRepository {}

class _MockWorkshopModRepository extends Mock
    implements WorkshopModRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockInitService extends Mock
    implements IProjectInitializationService {}

/// DetectedMods stub whose scan fails with no retained data (first visit /
/// retry-after-error: AsyncError with hasValue == false).
class _FailingDetectedMods extends DetectedMods {
  @override
  Future<List<DetectedMod>> build() async {
    throw Exception('RPFM CLI not found');
  }
}

/// DetectedMods stub whose scan succeeds.
class _SucceedingDetectedMods extends DetectedMods {
  @override
  Future<List<DetectedMod>> build() async => const <DetectedMod>[];
}

/// DetectedMods stub for the M28 flow: build succeeds, but the local
/// post-creation cache update throws (the representative post-creation
/// failure inside the controller's second try block).
class _ImportMarkThrowingDetectedMods extends DetectedMods {
  @override
  Future<List<DetectedMod>> build() async => const <DetectedMod>[];

  @override
  void updateModImported(String workshopId, String projectId) {
    throw StateError('provider update exploded after creation');
  }
}

/// SelectedGame stub: no game selected (keeps refresh() off the session
/// cache and away from SharedPreferences).
class _StubSelectedGame extends SelectedGame {
  @override
  Future<ConfiguredGame?> build() async => null;
}

const _mod = DetectedMod(
  workshopId: 'wid-1',
  name: 'My Mod',
  packFilePath: 'C:/workshop/wid-1/my_mod.pack',
);

void main() {
  setUpAll(() {
    registerFallbackValue(Project(
      id: '_',
      name: '_',
      gameInstallationId: '_',
      createdAt: 0,
      updatedAt: 0,
    ));
    registerFallbackValue(ProjectLanguage(
      id: '_',
      projectId: '_',
      languageId: '_',
      createdAt: 0,
      updatedAt: 0,
    ));
  });

  setUp(() async => TestBootstrap.registerFakes());

  group('handleRefresh (M26)', () {
    late WidgetRef capturedRef;

    Future<void> pumpRefreshProbe(
      WidgetTester tester, {
      required Override detectedModsOverride,
    }) async {
      // Manual ProviderScope (instead of createThemedTestableWidget) so the
      // Riverpod 3 default retry can be disabled: a failing AsyncNotifier
      // build is otherwise auto-retried with exponential backoff, keeping
      // the provider in AsyncLoading(hasError: true, isLoading: true) for
      // minutes of fake time before it settles as AsyncError(isLoading:
      // false) — the state the refresh listener must complete on.
      await tester.pumpWidget(ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          loggingServiceProvider.overrideWithValue(FakeLogger()),
          detectedModsOverride,
          selectedGameProvider.overrideWith(() => _StubSelectedGame()),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                // Watch the flag like the real toolbar does — it is an
                // autoDispose provider and would reset between unlistened
                // reads otherwise.
                final isLoading = ref.watch(modsLoadingStateProvider);
                return Text('loading:$isLoading');
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> refreshAndSettle(WidgetTester tester) async {
      final future = ModsScreenController(capturedRef).handleRefresh();
      await tester.pumpAndSettle();
      await future;
      await tester.pumpAndSettle();
    }

    testWidgets(
        'a rescan that errors with no retained data clears the loading flag '
        '(no stuck "Rescanning…" state)', (tester) async {
      await pumpRefreshProbe(
        tester,
        detectedModsOverride:
            detectedModsProvider.overrideWith(() => _FailingDetectedMods()),
      );

      await refreshAndSettle(tester);

      expect(find.text('loading:false'), findsOneWidget,
          reason: 'an AsyncError with hasValue == false must complete the '
              'refresh listener — otherwise the toolbar refresh button is '
              'permanently disabled and the subscription leaks per retry');
    });

    testWidgets(
        'retrying after an error completes again (the listener must not '
        'have leaked a stuck subscription)', (tester) async {
      await pumpRefreshProbe(
        tester,
        detectedModsOverride:
            detectedModsProvider.overrideWith(() => _FailingDetectedMods()),
      );

      await refreshAndSettle(tester);
      expect(find.text('loading:false'), findsOneWidget);

      // Retry — exactly what the error body's Retry button does.
      await refreshAndSettle(tester);
      expect(find.text('loading:false'), findsOneWidget);
    });

    testWidgets('a successful rescan also clears the loading flag (sanity)',
        (tester) async {
      await pumpRefreshProbe(
        tester,
        detectedModsOverride: detectedModsProvider
            .overrideWith(() => _SucceedingDetectedMods()),
      );

      await refreshAndSettle(tester);

      expect(find.text('loading:false'), findsOneWidget);
    });
  });

  group('project creation from mod (M28)', () {
    late _MockProjectRepository projectRepo;
    late _MockWorkshopModRepository workshopModRepo;
    late _MockLanguageRepository languageRepo;
    late _MockProjectLanguageRepository projectLanguageRepo;
    late _MockGameInstallationRepository gameRepo;
    late _MockSettingsService settings;
    late _MockInitService initService;

    setUp(() {
      projectRepo = _MockProjectRepository();
      workshopModRepo = _MockWorkshopModRepository();
      languageRepo = _MockLanguageRepository();
      projectLanguageRepo = _MockProjectLanguageRepository();
      gameRepo = _MockGameInstallationRepository();
      settings = _MockSettingsService();
      initService = _MockInitService();

      // No existing project for the mod → creation path.
      when(() => projectRepo.getAll())
          .thenAnswer((_) async => const Ok(<Project>[]));
      when(() => projectRepo.insert(any())).thenAnswer((invocation) async =>
          Ok(invocation.positionalArguments.first as Project));
      // Stubbed so that, were the old catch-all to call deleteProject, the
      // failure would show up as the verifyNever below rather than as a
      // missing-stub error.
      when(() => projectRepo.delete(any()))
          .thenAnswer((_) async => const Ok(null));

      when(() => workshopModRepo.getByWorkshopId('wid-1'))
          .thenAnswer((_) async => Ok(WorkshopMod(
                id: 'wm-1',
                workshopId: 'wid-1',
                title: 'My Mod',
                appId: 1142710,
                workshopUrl: 'https://steamcommunity.com/sharedfiles/'
                    'filedetails/?id=wid-1',
                createdAt: 0,
                updatedAt: 0,
              )));

      when(() => gameRepo.getAll()).thenAnswer((_) async => const Ok([
            GameInstallation(
              id: 'gi-1',
              gameCode: 'wh3',
              gameName: 'WH3',
              steamAppId: '1142710',
              installationPath: 'C:/games/wh3',
              createdAt: 0,
              updatedAt: 0,
            ),
          ]));

      when(() => settings.getString('rpfm_schema_path'))
          .thenAnswer((_) async => 'C:/rpfm/schemas');
      when(() => settings.getString('default_target_language',
              defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => 'fr');

      when(() => languageRepo.getByCode('fr')).thenAnswer(
        (_) async => Ok(Language(
          id: 'lang_fr',
          code: 'fr',
          name: 'French',
          nativeName: 'Français',
        )),
      );
      when(() => projectLanguageRepo.insert(any())).thenAnswer(
          (invocation) async =>
              Ok(invocation.positionalArguments.first as ProjectLanguage));

      when(() => initService.logStream)
          .thenAnswer((_) => const Stream<InitializationLogMessage>.empty());
      when(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer((_) async => const Ok(42));
    });

    testWidgets(
        'an exception in a post-creation step must NOT delete the created '
        'project and must surface a "Project created" warning, not a '
        'creation failure', (tester) async {
      // The initialization dialog is 640x~520; the default 800x600 test
      // surface overflows it and pushes the Close button out of hit-test
      // range, silently breaking tester.tap.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => ModsScreenController(ref)
                  .handleModRowTap(context, const [_mod], 'wid-1'),
              child: const Text('import'),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          projectRepositoryProvider.overrideWithValue(projectRepo),
          workshopModRepositoryProvider.overrideWithValue(workshopModRepo),
          languageRepositoryProvider.overrideWithValue(languageRepo),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
          settingsServiceProvider.overrideWithValue(settings),
          projectInitializationServiceProvider.overrideWithValue(initService),
          // The post-creation step that throws: marking the mod imported in
          // the local cache (runs after the project is fully initialized).
          detectedModsProvider
              .overrideWith(() => _ImportMarkThrowingDetectedMods()),
        ],
      ));
      await tester.pumpAndSettle();

      // Kick off creation; the initialization dialog opens.
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      expect(find.text('Close'), findsOneWidget,
          reason: 'initialization (mocked Ok) must complete and offer Close');

      // Closing the dialog returns success=true → post-creation steps run,
      // and updateModImported throws.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // The fully initialized project must survive the post-creation error.
      verifyNever(() => projectRepo.delete(any()));

      // And the user must not be told creation failed.
      expect(find.textContaining('Project created'), findsOneWidget,
          reason: 'post-creation errors must be surfaced as a warning that '
              'the project exists, not as a creation failure');
      expect(find.textContaining('Failed to create project'), findsNothing);

      // The project row was actually persisted.
      verify(() => projectRepo.insert(any())).called(1);

      // Drain the toast auto-dismiss timer.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets(
        'sanity (cleanup still bounded to pre-initialization failures): a '
        'declined initialization dialog still deletes the half-created '
        'project', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Initialization fails → dialog shows the error and Close pops false.
      when(() => initService.initializeProject(
            projectId: any(named: 'projectId'),
            packFilePath: any(named: 'packFilePath'),
          )).thenAnswer(
          (_) async => Err(ServiceException('no loc files found')));

      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => ModsScreenController(ref)
                  .handleModRowTap(context, const [_mod], 'wid-1'),
              child: const Text('import'),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          projectRepositoryProvider.overrideWithValue(projectRepo),
          workshopModRepositoryProvider.overrideWithValue(workshopModRepo),
          languageRepositoryProvider.overrideWithValue(languageRepo),
          projectLanguageRepositoryProvider
              .overrideWithValue(projectLanguageRepo),
          gameInstallationRepositoryProvider.overrideWithValue(gameRepo),
          settingsServiceProvider.overrideWithValue(settings),
          projectInitializationServiceProvider.overrideWithValue(initService),
          detectedModsProvider
              .overrideWith(() => _ImportMarkThrowingDetectedMods()),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      verify(() => projectRepo.delete(any())).called(1);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
