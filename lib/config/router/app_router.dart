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
import '../../features/projects/screens/project_detail_screen.dart';
import '../../features/translation_editor/screens/translation_editor_screen.dart';
import '../../features/glossary/screens/glossary_screen.dart';
import '../../features/translation_memory/screens/translation_memory_screen.dart';
import '../../features/pack_compilation/screens/pack_compilation_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/help/screens/help_screen.dart';

// Layout
import '../../widgets/layouts/main_layout_router.dart';

// Router utilities
import 'route_transitions.dart';

/// Route path constants
class AppRoutes {
  // Main routes
  static const String home = '/';
  static const String mods = '/mods';
  static const String projects = '/projects';
  static const String glossary = '/glossary';
  static const String translationMemory = '/translation-memory';
  static const String packCompilation = '/pack-compilation';
  static const String settings = '/settings';
  static const String help = '/help';

  // Detail routes
  static String projectDetail(String projectId) => '/projects/$projectId';
  static String translationEditor(String projectId, String languageId) =>
      '/projects/$projectId/editor/$languageId';

  // Settings sub-routes
  static const String settingsGeneral = '/settings/general';
  static const String settingsLlm = '/settings/llm';

  // Path parameters
  static const String projectIdParam = 'projectId';
  static const String languageIdParam = 'languageId';
}

/// GoRouter configuration provider
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    routes: [
      // Shell route - wraps all main screens with MainLayout
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
  void goProjects() => go(AppRoutes.projects);
  void goGlossary() => go(AppRoutes.glossary);
  void goTranslationMemory() => go(AppRoutes.translationMemory);
  void goPackCompilation() => go(AppRoutes.packCompilation);
  void goSettings() => go(AppRoutes.settings);
  void goHelp() => go(AppRoutes.help);

  void goProjectDetail(String projectId) => go(AppRoutes.projectDetail(projectId));
  void goTranslationEditor(String projectId, String languageId) =>
      go(AppRoutes.translationEditor(projectId, languageId));
}
