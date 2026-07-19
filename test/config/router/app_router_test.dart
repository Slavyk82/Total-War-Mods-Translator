import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/game_translation/screens/game_translation_screen.dart';
import 'package:twmt/features/glossary/screens/glossary_screen.dart';
import 'package:twmt/features/home/screens/home_screen.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart'
    show ModsFilter;
import 'package:twmt/features/mods/screens/mods_screen.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_list_screen.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart'
    show ProjectQuickFilter;
import 'package:twmt/features/projects/screens/batch_pack_export_screen.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/features/steam_publish/screens/batch_workshop_publish_screen.dart';
import 'package:twmt/features/steam_publish/screens/steam_publish_screen.dart';
import 'package:twmt/features/steam_publish/screens/workshop_publish_screen.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/features/translation_memory/screens/translation_memory_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/layouts/main_layout_router.dart';

/// Minimal router used only to exercise the redirect logic. Uses the real
/// `legacyRedirects` + `rootRedirect` from [AppRoutes] but dummy screens.
GoRouter _buildTestRouter({required String initial}) {
  return GoRouter(
    initialLocation: initial,
    redirect: (context, state) => appRouterRedirect(state.uri.path),
    routes: [
      for (final path in [
        AppRoutes.home,
        AppRoutes.mods,
        AppRoutes.gameFiles,
        AppRoutes.projects,
        AppRoutes.batchPackExport,
        AppRoutes.glossary,
        AppRoutes.translationMemory,
        AppRoutes.packCompilation,
        AppRoutes.steamPublish,
        AppRoutes.steamPublishSingle,
        AppRoutes.steamPublishBatch,
        AppRoutes.settings,
      ])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('at:$path')),
        ),
      GoRoute(
        path: '${AppRoutes.projects}/:projectId',
        builder: (_, s) =>
            Scaffold(body: Text('project:${s.pathParameters['projectId']}')),
      ),
      GoRoute(
        path: '${AppRoutes.projects}/:projectId/editor/:languageId',
        builder: (_, s) => Scaffold(
          body: Text(
            'editor:${s.pathParameters['projectId']}/${s.pathParameters['languageId']}',
          ),
        ),
      ),
    ],
  );
}

/// Builds a real [GoRouterState] against [configuration] for invoking
/// pageBuilders and the errorBuilder directly (without mounting the heavy
/// screens they construct).
GoRouterState _routerState(
  RouteConfiguration configuration,
  String location, {
  Map<String, String> pathParameters = const {},
}) {
  final uri = Uri.parse(location);
  return GoRouterState(
    configuration,
    uri: uri,
    matchedLocation: uri.path,
    fullPath: uri.path,
    pathParameters: pathParameters,
    pageKey: ValueKey<String>(uri.path),
  );
}

/// Recursively flattens all [GoRoute]s of a route tree.
Iterable<GoRoute> _flattenGoRoutes(List<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route;
    yield* _flattenGoRoutes(route.routes);
  }
}

/// Reads the production router from a fresh [ProviderContainer].
GoRouter _readAppRouter() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(goRouterProvider);
}

GoRoute _routeNamed(GoRouter router, String name) =>
    _flattenGoRoutes(router.configuration.routes)
        .firstWhere((route) => route.name == name);

/// Invokes the pageBuilder of the route [name] and returns the produced
/// transition page (its child is the constructed, unmounted screen).
CustomTransitionPage<dynamic> _buildPage(
  GoRouter router,
  BuildContext context,
  String name,
  String location, {
  Map<String, String> pathParameters = const {},
}) {
  final page = _routeNamed(router, name).pageBuilder!(
    context,
    _routerState(
      router.configuration,
      location,
      pathParameters: pathParameters,
    ),
  );
  return page as CustomTransitionPage<dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppRoutes nested paths', () {
    test('home is /work/home', () {
      expect(AppRoutes.home, '/work/home');
    });
    test('mods is /sources/mods', () {
      expect(AppRoutes.mods, '/sources/mods');
    });
    test('gameFiles is /sources/game-files', () {
      expect(AppRoutes.gameFiles, '/sources/game-files');
    });
    test('projects is /work/projects', () {
      expect(AppRoutes.projects, '/work/projects');
    });
    test('translationEditor composes /work/projects/<id>/editor/<lang>', () {
      expect(
        AppRoutes.translationEditor('abc', 'fr-FR'),
        '/work/projects/abc/editor/fr-FR',
      );
    });
    test('batchPackExport is /work/projects/batch-export', () {
      expect(AppRoutes.batchPackExport, '/work/projects/batch-export');
    });
    test('glossary is /resources/glossary', () {
      expect(AppRoutes.glossary, '/resources/glossary');
    });
    test('translationMemory is /resources/tm', () {
      expect(AppRoutes.translationMemory, '/resources/tm');
    });
    test('packCompilation is /publishing/pack', () {
      expect(AppRoutes.packCompilation, '/publishing/pack');
    });
    test('steamPublish is /publishing/steam', () {
      expect(AppRoutes.steamPublish, '/publishing/steam');
    });
    test('steamPublishSingle is /publishing/steam/single', () {
      expect(AppRoutes.steamPublishSingle, '/publishing/steam/single');
    });
    test('settings is /system/settings', () {
      expect(AppRoutes.settings, '/system/settings');
    });
    test('rootRedirect is /work/home', () {
      expect(AppRoutes.rootRedirect, '/work/home');
    });
  });

  group('appRouterRedirect', () {
    test('root / redirects to /work/home', () {
      expect(appRouterRedirect('/'), '/work/home');
    });
    test('legacy /mods redirects to /sources/mods', () {
      expect(appRouterRedirect('/mods'), '/sources/mods');
    });
    test('legacy /game-translation redirects to /sources/game-files', () {
      expect(appRouterRedirect('/game-translation'), '/sources/game-files');
    });
    test('legacy /projects redirects to /work/projects', () {
      expect(appRouterRedirect('/projects'), '/work/projects');
    });
    test('legacy nested /projects/<id> redirects to /work/projects/<id>', () {
      expect(
        appRouterRedirect('/projects/abc-123'),
        '/work/projects/abc-123',
      );
    });
    test('legacy deep /projects/<id>/editor/<lang> redirects correctly', () {
      expect(
        appRouterRedirect('/projects/abc-123/editor/fr-FR'),
        '/work/projects/abc-123/editor/fr-FR',
      );
    });
    test('legacy /glossary redirects to /resources/glossary', () {
      expect(appRouterRedirect('/glossary'), '/resources/glossary');
    });
    test('legacy /translation-memory redirects to /resources/tm', () {
      expect(appRouterRedirect('/translation-memory'), '/resources/tm');
    });
    test('legacy /pack-compilation redirects to /publishing/pack', () {
      expect(appRouterRedirect('/pack-compilation'), '/publishing/pack');
    });
    test('legacy /steam-publish redirects to /publishing/steam', () {
      expect(appRouterRedirect('/steam-publish'), '/publishing/steam');
    });
    test('legacy /steam-publish/batch redirects correctly', () {
      expect(
        appRouterRedirect('/steam-publish/batch'),
        '/publishing/steam/batch',
      );
    });
    test('legacy /settings redirects to /system/settings', () {
      expect(appRouterRedirect('/settings'), '/system/settings');
    });
    test('new-path input returns null (no redirect)', () {
      expect(appRouterRedirect('/sources/mods'), isNull);
      expect(appRouterRedirect('/work/projects/abc'), isNull);
      expect(appRouterRedirect('/system/settings'), isNull);
    });
    test('unknown path returns null (no redirect, falls through to errorBuilder)', () {
      expect(appRouterRedirect('/nowhere'), isNull);
    });
  });

  group('GoRouter integration', () {
    testWidgets('/ navigates to /work/home', (tester) async {
      final router = _buildTestRouter(initial: '/');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('at:/work/home'), findsOneWidget);
    });

    testWidgets('/mods navigates to /sources/mods screen', (tester) async {
      final router = _buildTestRouter(initial: '/mods');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('at:/sources/mods'), findsOneWidget);
    });

    testWidgets('/projects/abc navigates to /work/projects/abc', (tester) async {
      final router = _buildTestRouter(initial: '/projects/abc-123');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('project:abc-123'), findsOneWidget);
    });
  });

  group('appRouterRedirect query/fragment preservation', () {
    test('carries the query string across a legacy redirect', () {
      expect(
        appRouterRedirect('/mods', uri: Uri.parse('/mods?filter=needs-update')),
        '/sources/mods?filter=needs-update',
      );
    });

    test('carries the fragment across a legacy redirect', () {
      expect(
        appRouterRedirect('/settings', uri: Uri.parse('/settings#llm')),
        '/system/settings#llm',
      );
    });

    test('carries query and fragment together on nested legacy paths', () {
      expect(
        appRouterRedirect(
          '/projects/p1',
          uri: Uri.parse('/projects/p1?a=1&b=2#x'),
        ),
        '/work/projects/p1?a=1&b=2#x',
      );
    });

    test('root / keeps its query on redirect to home', () {
      expect(
        appRouterRedirect('/', uri: Uri.parse('/?filter=needs-review')),
        '/work/home?filter=needs-review',
      );
    });

    test('uri without query or fragment yields a clean path', () {
      expect(
        appRouterRedirect('/glossary', uri: Uri.parse('/glossary')),
        '/resources/glossary',
      );
    });

    test('non-legacy path returns null even with a uri', () {
      expect(
        appRouterRedirect('/work/home', uri: Uri.parse('/work/home?x=1')),
        isNull,
      );
    });
  });

  group('AppRoutes publishing & settings paths', () {
    test('packCompilationNew is /publishing/pack/new', () {
      expect(AppRoutes.packCompilationNew, '/publishing/pack/new');
    });
    test('packCompilationEdit composes /publishing/pack/<id>/edit', () {
      expect(AppRoutes.packCompilationEdit('c42'), '/publishing/pack/c42/edit');
    });
    test('steamPublishBatch is /publishing/steam/batch', () {
      expect(AppRoutes.steamPublishBatch, '/publishing/steam/batch');
    });
    test('settingsGeneral and settingsLlm nest under /system/settings', () {
      expect(AppRoutes.settingsGeneral, '/system/settings/general');
      expect(AppRoutes.settingsLlm, '/system/settings/llm');
    });
  });

  group('goRouterProvider configuration', () {
    test('roots at /work/home with the global navigator key', () {
      final router = _readAppRouter();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRoutes.rootRedirect,
      );
      expect(router.configuration.navigatorKey, same(rootNavigatorKey));
    });

    testWidgets('wires appRouterRedirect (with uri) as the top-level redirect',
        (tester) async {
      final router = _readAppRouter();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      final context = tester.element(find.byType(SizedBox));

      final redirected = router.configuration.topRedirect(
        context,
        _routerState(router.configuration, '/mods?filter=needs-update'),
      );
      expect(redirected, '/sources/mods?filter=needs-update');

      final untouched = router.configuration.topRedirect(
        context,
        _routerState(router.configuration, AppRoutes.home),
      );
      expect(untouched, isNull);
    });

    test('declares every expected named route under a single shell', () {
      final router = _readAppRouter();
      expect(router.configuration.routes, hasLength(1));
      expect(router.configuration.routes.single, isA<ShellRoute>());

      final names = _flattenGoRoutes(router.configuration.routes)
          .map((route) => route.name)
          .toList();
      expect(
        names,
        unorderedEquals([
          'home',
          'mods',
          'projects',
          'batchPackExport',
          'translationEditor',
          'gameFiles',
          'glossary',
          'translationMemory',
          'packCompilation',
          'packCompilationNew',
          'packCompilationEdit',
          'steamPublish',
          'steamPublishSingle',
          'steamPublishBatch',
          'settings',
        ]),
      );
    });
  });

  group('goRouterProvider pageBuilders', () {
    Future<BuildContext> pumpContext(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      return tester.element(find.byType(SizedBox));
    }

    testWidgets('top-level routes build their screens with a fade (150ms)',
        (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final cases = <String, (String, Type)>{
        'home': (AppRoutes.home, HomeScreen),
        'gameFiles': (AppRoutes.gameFiles, GameTranslationScreen),
        'glossary': (AppRoutes.glossary, GlossaryScreen),
        'translationMemory': (
          AppRoutes.translationMemory,
          TranslationMemoryScreen,
        ),
        'packCompilation': (
          AppRoutes.packCompilation,
          PackCompilationListScreen,
        ),
        'steamPublish': (AppRoutes.steamPublish, SteamPublishScreen),
        'settings': (AppRoutes.settings, SettingsScreen),
      };
      for (final entry in cases.entries) {
        final (location, screenType) = entry.value;
        final page = _buildPage(router, context, entry.key, location);
        expect(page.child.runtimeType, screenType,
            reason: 'route ${entry.key} should build a $screenType');
        expect(page.transitionDuration, const Duration(milliseconds: 150),
            reason: 'route ${entry.key} should use the fade transition');
      }
    });

    testWidgets('mods route maps ?filter= onto ModsScreen.initialFilter',
        (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final filtered = _buildPage(
        router,
        context,
        'mods',
        '${AppRoutes.mods}?filter=needs-update',
      );
      expect(
        (filtered.child as ModsScreen).initialFilter,
        ModsFilter.needsUpdate,
      );

      final unfiltered = _buildPage(router, context, 'mods', AppRoutes.mods);
      expect((unfiltered.child as ModsScreen).initialFilter, isNull);
    });

    testWidgets(
        'projects route maps ?filter= onto ProjectsScreen.initialFilter',
        (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final filtered = _buildPage(
        router,
        context,
        'projects',
        '${AppRoutes.projects}?filter=needs-review',
      );
      expect(
        (filtered.child as ProjectsScreen).initialFilter,
        ProjectQuickFilter.needsReview,
      );

      final unfiltered =
          _buildPage(router, context, 'projects', AppRoutes.projects);
      expect((unfiltered.child as ProjectsScreen).initialFilter, isNull);
    });

    testWidgets('detail routes slide from the right (200ms)', (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final batchExport = _buildPage(
        router,
        context,
        'batchPackExport',
        AppRoutes.batchPackExport,
      );
      expect(batchExport.child, isA<BatchPackExportScreen>());
      expect(batchExport.transitionDuration, const Duration(milliseconds: 200));

      final editor = _buildPage(
        router,
        context,
        'translationEditor',
        AppRoutes.translationEditor('p1', 'fr-FR'),
        pathParameters: {
          AppRoutes.projectIdParam: 'p1',
          AppRoutes.languageIdParam: 'fr-FR',
        },
      );
      final editorScreen = editor.child as TranslationEditorScreen;
      expect(editorScreen.projectId, 'p1');
      expect(editorScreen.languageId, 'fr-FR');
      expect(editor.transitionDuration, const Duration(milliseconds: 200));
    });

    testWidgets('pack compilation new/edit routes build the editor screen',
        (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final create = _buildPage(
        router,
        context,
        'packCompilationNew',
        AppRoutes.packCompilationNew,
      );
      expect(
        (create.child as PackCompilationEditorScreen).compilationId,
        isNull,
      );

      final edit = _buildPage(
        router,
        context,
        'packCompilationEdit',
        AppRoutes.packCompilationEdit('c42'),
        pathParameters: {AppRoutes.compilationIdParam: 'c42'},
      );
      expect((edit.child as PackCompilationEditorScreen).compilationId, 'c42');
    });

    testWidgets('steam publish single/batch routes build the publish screens',
        (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final single = _buildPage(
        router,
        context,
        'steamPublishSingle',
        AppRoutes.steamPublishSingle,
      );
      expect(single.child, isA<WorkshopPublishScreen>());

      final batch = _buildPage(
        router,
        context,
        'steamPublishBatch',
        AppRoutes.steamPublishBatch,
      );
      expect(batch.child, isA<BatchWorkshopPublishScreen>());
    });

    testWidgets('shell route wraps the child in MainLayoutRouter',
        (tester) async {
      final router = _readAppRouter();
      final context = await pumpContext(tester);

      final shell = router.configuration.routes.single as ShellRoute;
      const child = SizedBox.shrink();
      final built = shell.builder!(
        context,
        _routerState(router.configuration, AppRoutes.home),
        child,
      );
      expect(built, isA<MainLayoutRouter>());
      expect((built as MainLayoutRouter).child, same(child));
    });
  });

  group('goRouterProvider errorBuilder', () {
    testWidgets('renders the route-not-found page and Go Home navigates home',
        (tester) async {
      final appRouter = _readAppRouter();
      final errorBuilder = appRouter.routerDelegate.builder.errorBuilder!;

      // Mount the real error page inside a dummy router so tapping "Go Home"
      // has a live GoRouter to navigate with (avoids mounting the real,
      // provider-heavy home screen).
      final testRouter = GoRouter(
        initialLocation: '/error',
        routes: [
          GoRoute(
            path: '/error',
            builder: (context, _) => errorBuilder(
              context,
              _routerState(appRouter.configuration, '/nowhere'),
            ),
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text('dummy-home')),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: testRouter,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(FluentScaffold), findsOneWidget);
      expect(find.text('Route not found: /nowhere'), findsOneWidget);

      await tester.tap(find.text('Go Home'));
      await tester.pumpAndSettle();
      expect(find.text('dummy-home'), findsOneWidget);
    });
  });

  group('GoRouterExtensions', () {
    GoRouter buildExtensionsRouter() {
      return GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          for (final path in [
            AppRoutes.home,
            AppRoutes.mods,
            AppRoutes.gameFiles,
            AppRoutes.projects,
            AppRoutes.batchPackExport,
            AppRoutes.glossary,
            AppRoutes.translationMemory,
            AppRoutes.packCompilation,
            AppRoutes.packCompilationNew,
            AppRoutes.steamPublish,
            AppRoutes.steamPublishSingle,
            AppRoutes.steamPublishBatch,
            AppRoutes.settings,
          ])
            GoRoute(
              path: path,
              builder: (_, _) => Scaffold(body: Text('at:$path')),
            ),
          GoRoute(
            path: '${AppRoutes.packCompilation}/:id/edit',
            builder: (_, s) =>
                Scaffold(body: Text('edit:${s.pathParameters['id']}')),
          ),
          GoRoute(
            path: '${AppRoutes.projects}/:projectId/editor/:languageId',
            builder: (_, s) => Scaffold(
              body: Text(
                'editor:${s.pathParameters['projectId']}/${s.pathParameters['languageId']}',
              ),
            ),
          ),
        ],
      );
    }

    testWidgets('each goX() helper navigates to its route', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: buildExtensionsRouter()),
      );
      await tester.pumpAndSettle();
      expect(find.text('at:${AppRoutes.home}'), findsOneWidget);

      Future<void> expectAt(
        void Function(BuildContext context) navigate,
        String marker,
      ) async {
        navigate(tester.element(find.byType(Scaffold).first));
        await tester.pumpAndSettle();
        expect(find.text(marker), findsOneWidget);
      }

      await expectAt((c) => c.goMods(), 'at:${AppRoutes.mods}');
      await expectAt((c) => c.goGameFiles(), 'at:${AppRoutes.gameFiles}');
      await expectAt((c) => c.goProjects(), 'at:${AppRoutes.projects}');
      await expectAt(
        (c) => c.goBatchPackExport(),
        'at:${AppRoutes.batchPackExport}',
      );
      await expectAt((c) => c.goGlossary(), 'at:${AppRoutes.glossary}');
      await expectAt(
        (c) => c.goTranslationMemory(),
        'at:${AppRoutes.translationMemory}',
      );
      await expectAt(
        (c) => c.goPackCompilation(),
        'at:${AppRoutes.packCompilation}',
      );
      await expectAt(
        (c) => c.goPackCompilationNew(),
        'at:${AppRoutes.packCompilationNew}',
      );
      await expectAt((c) => c.goPackCompilationEdit('c1'), 'edit:c1');
      await expectAt((c) => c.goSteamPublish(), 'at:${AppRoutes.steamPublish}');
      await expectAt(
        (c) => c.goWorkshopPublishSingle(),
        'at:${AppRoutes.steamPublishSingle}',
      );
      await expectAt(
        (c) => c.goWorkshopPublishBatch(),
        'at:${AppRoutes.steamPublishBatch}',
      );
      await expectAt((c) => c.goSettings(), 'at:${AppRoutes.settings}');
      await expectAt((c) => c.goTranslationEditor('p1', 'fr'), 'editor:p1/fr');
      await expectAt((c) => c.goHome(), 'at:${AppRoutes.home}');
    });
  });
}
