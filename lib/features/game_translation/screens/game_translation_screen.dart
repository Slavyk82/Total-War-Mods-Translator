import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../widgets/detail/home_back_toolbar.dart';
import '../../../widgets/layouts/fluent_scaffold.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/lists/list_toolbar_leading.dart';
import '../../projects/providers/projects_screen_providers.dart';
import '../../projects/utils/open_project_editor.dart';
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
    final hasPacksAsync = ref.watch(hasLocalPacksProvider);
    // During loading/error treat packs as available (permissive). Empty data
    // means no packs detected — disable the toolbar Create button.
    final hasPacks = hasPacksAsync.value ?? true;
    final count = projectsAsync.asData?.value.length ?? 0;

    return FluentScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(
            leading: ListToolbarLeading(
              icon: FluentIcons.globe_24_regular,
              title: 'Game Translation',
              countLabel: '$count ${count == 1 ? 'translation' : 'translations'}',
            ),
          ),
          FilterToolbar(
            leading: const SizedBox.shrink(),
            expandLeading: false,
            trailing: [
              SmallTextButton(
                label: 'Create Game Translation',
                icon: FluentIcons.add_24_regular,
                filled: true,
                tooltip: hasPacks
                    ? null
                    : 'No localization packs found for this game',
                onTap:
                    hasPacks ? () => _showCreateDialog(context, ref) : null,
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: projectsAsync.when(
                data: (projects) =>
                    _buildContent(context, ref, theme, projects),
                loading: () => _buildLoading(theme),
                error: (error, stack) => _buildError(theme, error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    List<ProjectWithDetails> projects,
  ) {
    if (projects.isEmpty) {
      return _buildEmptyState(context, theme);
    }

    return ProjectGrid(
      projects: projects,
      onProjectTap: (projectId) => _navigateToProject(context, ref, projectId),
      onDelete: (projectId) {
        final details = projects.firstWhere(
          (p) => p.project.id == projectId,
        );
        _handleDeleteProject(context, ref, details);
      },
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

  void _navigateToProject(BuildContext context, WidgetRef ref, String projectId) {
    openProjectEditor(context, ref, projectId);
  }

  /// Confirm + delete a game translation project.
  ///
  /// Mirrors `projects_screen.dart:_handleDeleteProject` but invalidates the
  /// game-translations provider instead of patching the optimistic notifier,
  /// since `gameTranslationProjectsProvider` is a plain FutureProvider.
  Future<void> _handleDeleteProject(
    BuildContext context,
    WidgetRef ref,
    ProjectWithDetails details,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TokenConfirmDialog(
        title: 'Delete Game Translation',
        message:
            'Are you sure you want to delete "${details.project.name}"?',
        warningMessage: 'This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmIcon: FluentIcons.delete_24_regular,
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(shared_repo.projectRepositoryProvider)
        .delete(details.project.id);
    if (!context.mounted) return;
    if (result.isOk) {
      ref.invalidate(gameTranslationProjectsProvider);
      FluentToast.success(
        context,
        'Game translation "${details.project.name}" deleted',
      );
    } else {
      FluentToast.error(
        context,
        'Failed to delete game translation: ${result.error}',
      );
    }
  }
}
