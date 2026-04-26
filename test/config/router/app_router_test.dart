import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';

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

void main() {
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
}
