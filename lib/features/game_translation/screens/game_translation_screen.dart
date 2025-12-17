import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/router/app_router.dart';
import '../../../widgets/layouts/fluent_scaffold.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../projects/providers/projects_screen_providers.dart';
import '../../projects/widgets/project_grid.dart';
import '../providers/game_translation_providers.dart';
import '../widgets/create_game_translation/create_game_translation_dialog.dart';

/// Screen for managing game translation projects.
///
/// Displays a list of game translation projects (projects with type='game')
/// that allow translating the base game's localization files.
class GameTranslationScreen extends ConsumerWidget {
  const GameTranslationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projectsAsync = ref.watch(gameTranslationProjectsProvider);

    return FluentScaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(theme),
            const SizedBox(height: 24),
            // Projects grid
            Expanded(
              child: projectsAsync.when(
                data: (projects) => _buildContent(context, theme, projects),
                loading: () => _buildLoading(theme),
                error: (error, stack) => _buildError(theme, error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(
          FluentIcons.globe_24_regular,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Game Translation',
            style: theme.textTheme.headlineLarge,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    List<ProjectWithDetails> projects,
  ) {
    if (projects.isEmpty) {
      return _buildEmptyState(context, theme);
    }

    return ProjectGrid(
      projects: projects,
      onProjectTap: (projectId) => _navigateToProject(context, projectId),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.globe_24_regular,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No game translations yet',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new translation to translate the base game',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Consumer(
            builder: (context, ref, child) {
              final hasPacksAsync = ref.watch(hasLocalPacksProvider);
              return hasPacksAsync.when(
                data: (hasPacks) {
                  if (!hasPacks) {
                    return Column(
                      children: [
                        Icon(
                          FluentIcons.warning_24_regular,
                          size: 24,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No localization packs found for this game',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    );
                  }
                  return FluentButton(
                    onPressed: () => _showCreateDialog(context, ref),
                    icon: const Icon(FluentIcons.add_24_regular),
                    child: const Text('Create Game Translation'),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (_, _) => const Text('Error loading packs'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading game translations...',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading game translations',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CreateGameTranslationDialog(),
    );
  }

  void _navigateToProject(BuildContext context, String projectId) {
    context.go(AppRoutes.projectDetail(projectId));
  }
}
