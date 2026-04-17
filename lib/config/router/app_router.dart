import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

// Screens
import '../../features/home/screens/home_screen.dart';
import '../../features/mods/screens/mods_screen.dart';
import '../../features/projects/screens/projects_screen.dart';
import '../../features/projects/screens/batch_pack_export_screen.dart';
import '../../features/projects/screens/project_detail_screen.dart';
import '../../features/translation_editor/screens/translation_editor_screen.dart';
import '../../features/glossary/screens/glossary_screen.dart';
import '../../features/translation_memory/screens/translation_memory_screen.dart';
import '../../features/pack_compilation/screens/pack_compilation_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/help/screens/help_screen.dart';
import '../../features/game_translation/screens/game_translation_screen.dart';
import '../../features/steam_publish/screens/steam_publish_screen.dart';
import '../../features/steam_publish/screens/workshop_publish_screen.dart';
import '../../features/steam_publish/screens/batch_workshop_publish_screen.dart';

// Layout
import '../../widgets/layouts/main_layout_router.dart';

// Router utilities
import 'route_transitions.dart';

/// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Route path constants.
///
/// Paths are nested by sidebar group (Sources, Work, Resources, Publishing,
/// System) — see `NavigationTree`. Use `legacyRedirects` to map pre-restructure
/// URLs onto the new ones.
class AppRoutes {
  // Root
  static const String rootRedirect = '/work/home';

  // Sources
  static const String mods = '/sources/mods';
  static const String gameFiles = '/sources/game-files';

  // Work
  static const String home = '/work/home';
  static const String projects = '/work/projects';
  static const String batchPackExport = '/work/projects/batch-export';

  // Resources
  static const String glossary = '/resources/glossary';
  static const String translationMemory = '/resources/tm';

  // Publishing
  static const String packCompilation = '/publishing/pack';
  static const String packCompilationNew = '/publishing/pack/new';
  static String packCompilationEdit(String id) => '/publishing/pack/$id/edit';
  static const String compilationIdParam = 'compilationId';
  static const String steamPublish = '/publishing/steam';
  static const String steamPublishSingle = '/publishing/steam/single';
  static const String steamPublishBatch = '/publishing/steam/batch';

  // System
  static const String settings = '/system/settings';
  static const String settingsGeneral = '/system/settings/general';
  static const String settingsLlm = '/system/settings/llm';
  static const String help = '/system/help';

  // Detail / parameterised routes
  static String projectDetail(String projectId) => '$projects/$projectId';
  static String translationEditor(String projectId, String languageId) =>
      '$projects/$projectId/editor/$languageId';

  // Path parameter names
  static const String projectIdParam = 'projectId';
  static const String languageIdParam = 'languageId';
}

/// Legacy URL → new URL map. Longest match wins (handled by
/// [appRouterRedirect]). Retained for one cycle to absorb any path that may
/// have been persisted by the app (Windows shortcuts, cached state).
const Map<String, String> legacyRedirects = {
  '/': '/work/home',
  '/mods': '/sources/mods',
  '/game-translation': '/sources/game-files',
  '/projects': '/work/projects',
  '/glossary': '/resources/glossary',
  '/translation-memory': '/resources/tm',
  '/pack-compilation': '/publishing/pack',
  '/steam-publish': '/publishing/steam',
  '/settings': '/system/settings',
  '/help': '/system/help',
};

/// Pure redirect function. Returns the new path or `null` if no redirect
/// applies. Matches the longest legacy prefix so
/// `/projects/abc/editor/fr` → `/work/projects/abc/editor/fr`.
String? appRouterRedirect(String path) {
  if (path == '/') return legacyRedirects['/'];

  String? bestMatch;
  int bestLen = 0;
  legacyRedirects.forEach((legacy, newPrefix) {
    if (legacy == '/') return; // handled above
    if (path == legacy || path.startsWith('$legacy/')) {
      if (legacy.length > bestLen) {
        bestLen = legacy.length;
        final tail = path.substring(legacy.length);
        bestMatch = '$newPrefix$tail';
      }
    }
  });
  return bestMatch;
}

/// GoRouter configuration provider
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.rootRedirect,
    debugLogDiagnostics: true,
    redirect: (context, state) => appRouterRedirect(state.uri.path),
    routes: [
      // Shell route - wraps all main screens with MainLayoutRouter
      ShellRoute(
        builder: (context, state, child) {
          return MainLayoutRouter(child: child);
        },
        routes: [
          // Home
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const HomeScreen(),
                state: state,
              );
            },
          ),

          // Mods
          GoRoute(
            path: AppRoutes.mods,
            name: 'mods',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const ModsScreen(),
                state: state,
              );
            },
          ),

          // Projects
          GoRoute(
            path: AppRoutes.projects,
            name: 'projects',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const ProjectsScreen(),
                state: state,
              );
            },
            routes: [
              // Batch Pack Export
              GoRoute(
                path: 'batch-export',
                name: 'batchPackExport',
                pageBuilder: (context, state) {
                  return FluentPageTransitions.slideFromRightTransition(
                    child: const BatchPackExportScreen(),
                    state: state,
                  );
                },
              ),
              // Project Detail
              GoRoute(
                path: ':${AppRoutes.projectIdParam}',
                name: 'projectDetail',
                pageBuilder: (context, state) {
                  final projectId = state.pathParameters[AppRoutes.projectIdParam]!;

                  return FluentPageTransitions.slideFromRightTransition(
                    child: ProjectDetailScreen(projectId: projectId),
                    state: state,
                  );
                },
                routes: [
                  // Translation Editor
                  GoRoute(
                    path: 'editor/:${AppRoutes.languageIdParam}',
                    name: 'translationEditor',
                    pageBuilder: (context, state) {
                      final projectId = state.pathParameters[AppRoutes.projectIdParam]!;
                      final languageId = state.pathParameters[AppRoutes.languageIdParam]!;

                      return FluentPageTransitions.slideFromRightTransition(
                        child: TranslationEditorScreen(
                          projectId: projectId,
                          languageId: languageId,
                        ),
                        state: state,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Game Files
          GoRoute(
            path: AppRoutes.gameFiles,
            name: 'gameFiles',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const GameTranslationScreen(),
                state: state,
              );
            },
          ),

          // Glossary
          GoRoute(
            path: AppRoutes.glossary,
            name: 'glossary',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const GlossaryScreen(),
                state: state,
              );
            },
          ),

          // Translation Memory
          GoRoute(
            path: AppRoutes.translationMemory,
            name: 'translationMemory',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const TranslationMemoryScreen(),
                state: state,
              );
            },
          ),

          // Pack Compilation
          GoRoute(
            path: AppRoutes.packCompilation,
            name: 'packCompilation',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const PackCompilationScreen(),
                state: state,
              );
            },
            routes: [
              GoRoute(
                path: 'new',
                name: 'packCompilationNew',
                pageBuilder: (context, state) {
                  return FluentPageTransitions.slideFromRightTransition(
                    child: const PackCompilationScreen(), // replaced in Task 5
                    state: state,
                  );
                },
              ),
              GoRoute(
                path: ':${AppRoutes.compilationIdParam}/edit',
                name: 'packCompilationEdit',
                pageBuilder: (context, state) {
                  return FluentPageTransitions.slideFromRightTransition(
                    child: const PackCompilationScreen(), // replaced in Task 5
                    state: state,
                  );
                },
              ),
            ],
          ),

          // Steam Publish
          GoRoute(
            path: AppRoutes.steamPublish,
            name: 'steamPublish',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const SteamPublishScreen(),
                state: state,
              );
            },
            routes: [
              GoRoute(
                path: 'single',
                name: 'steamPublishSingle',
                pageBuilder: (context, state) {
                  return FluentPageTransitions.slideFromRightTransition(
                    child: const WorkshopPublishScreen(),
                    state: state,
                  );
                },
              ),
              GoRoute(
                path: 'batch',
                name: 'steamPublishBatch',
                pageBuilder: (context, state) {
                  return FluentPageTransitions.slideFromRightTransition(
                    child: const BatchWorkshopPublishScreen(),
                    state: state,
                  );
                },
              ),
            ],
          ),

          // Settings
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const SettingsScreen(),
                state: state,
              );
            },
          ),

          // Help
          GoRoute(
            path: AppRoutes.help,
            name: 'help',
            pageBuilder: (context, state) {
              return FluentPageTransitions.fadeTransition(
                child: const HelpScreen(),
                state: state,
              );
            },
          ),
        ],
      ),
    ],
    // Error handler
    errorBuilder: (context, state) {
      return FluentScaffold(
        header: FluentHeader(title: 'Error'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FluentIcons.error_circle_24_regular, size: 48),
              const SizedBox(height: 16),
              Text(
                'Route not found: ${state.uri.path}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FluentButton(
                onPressed: () => context.go(AppRoutes.home),
                icon: const Icon(FluentIcons.home_24_regular),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    },
  );
});

/// Extension methods for type-safe navigation
extension GoRouterExtensions on BuildContext {
  void goHome() => go(AppRoutes.home);
  void goMods() => go(AppRoutes.mods);
  void goGameFiles() => go(AppRoutes.gameFiles);
  void goProjects() => go(AppRoutes.projects);
  void goGlossary() => go(AppRoutes.glossary);
  void goTranslationMemory() => go(AppRoutes.translationMemory);
  void goPackCompilation() => go(AppRoutes.packCompilation);
  void goPackCompilationNew() => go(AppRoutes.packCompilationNew);
  void goPackCompilationEdit(String id) => go(AppRoutes.packCompilationEdit(id));
  void goBatchPackExport() => go(AppRoutes.batchPackExport);
  void goSteamPublish() => go(AppRoutes.steamPublish);
  void goWorkshopPublishSingle() => go(AppRoutes.steamPublishSingle);
  void goWorkshopPublishBatch() => go(AppRoutes.steamPublishBatch);
  void goSettings() => go(AppRoutes.settings);
  void goHelp() => go(AppRoutes.help);

  void goProjectDetail(String projectId) => go(AppRoutes.projectDetail(projectId));
  void goTranslationEditor(String projectId, String languageId) =>
      go(AppRoutes.translationEditor(projectId, languageId));
}
