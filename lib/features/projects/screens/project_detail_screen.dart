import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart' hide FluentIconButton;
import 'package:twmt/config/router/app_router.dart';
import '../providers/project_detail_providers.dart';
import '../providers/projects_screen_providers.dart';
import '../widgets/project_overview_section.dart';
import '../widgets/language_card.dart';
import '../widgets/project_stats_card.dart';
import '../widgets/add_language_dialog.dart';
import '../widgets/project_settings_card.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Project detail screen showing comprehensive project information.
///
/// Displays project overview, target languages with progress,
/// translation statistics, and action buttons.
/// Organized in a responsive layout with sections.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectDetailsAsync = ref.watch(projectDetailsProvider(projectId));

    return FluentScaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      header: FluentHeader(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: FluentIconButton(
          icon: const Icon(FluentIcons.arrow_left_24_regular),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        title: projectDetailsAsync.when(
          data: (details) => details.project.name,
          loading: () => 'Loading...',
          error: (error, stackTrace) => 'Project Details',
        ),
      ),
      body: projectDetailsAsync.when(
        data: (details) => _buildContent(context, ref, details),
        loading: () => _buildLoading(context),
        error: (error, stack) => _buildError(context, error),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ProjectDetails details,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjectOverviewSection(
            project: details.project,
            gameInstallation: details.gameInstallation,
            onEdit: () => _handleEditProject(context, details),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildLanguagesSection(context, ref, details),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: _buildStatsSection(context, ref, details),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildLanguagesSection(context, ref, details),
                    const SizedBox(height: 24),
                    _buildStatsSection(context, ref, details),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagesSection(
    BuildContext context,
    WidgetRef ref,
    ProjectDetails details,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              FluentIcons.translate_24_regular,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Target Languages',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _buildAddLanguageButton(context, details),
          ],
        ),
        const SizedBox(height: 16),
        if (details.languages.isEmpty)
          _buildEmptyLanguages(context)
        else
          _buildLanguagesList(context, details),
      ],
    );
  }

  Widget _buildLanguagesList(BuildContext context, ProjectDetails details) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: details.languages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final langDetails = details.languages[index];
        return LanguageCard(
          projectLanguage: langDetails.projectLanguage,
          language: langDetails.language,
          totalUnits: details.stats.totalUnits,
          translatedUnits: details.stats.translatedUnits,
          onOpenEditor: () => _handleOpenEditor(
            context,
            details.project.id,
            langDetails.projectLanguage.languageId,
          ),
        );
      },
    );
  }

  Widget _buildEmptyLanguages(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(48.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.translate_off_24_regular,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Target Languages',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a target language to start translating',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddLanguageButton(BuildContext context, ProjectDetails details) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleAddLanguage(context, details),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.add_24_regular,
                size: 16,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Add Language',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection(
    BuildContext context,
    WidgetRef ref,
    ProjectDetails details,
  ) {
    return Column(
      children: [
        ProjectStatsCard(stats: details.stats),
        const SizedBox(height: 16),
        ProjectSettingsCard(
          project: details.project,
          onSave: (batchSize, parallelBatches, customPrompt) =>
              _handleSaveSettings(
            context,
            ref,
            details,
            batchSize,
            parallelBatches,
            customPrompt,
          ),
        ),
        const SizedBox(height: 16),
        ProjectActionsCard(
          onExport: () => _handleExportAll(context, details),
          onDelete: () => _handleDeleteProject(context, ref, details),
        ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading project details...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Project',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Go Back',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleEditProject(BuildContext context, ProjectDetails details) {
    FluentToast.info(context, 'Edit project: ${details.project.name}');
  }

  void _handleAddLanguage(BuildContext context, ProjectDetails details) {
    final existingLanguageIds =
        details.languages.map((l) => l.projectLanguage.languageId).toList();

    showDialog(
      context: context,
      builder: (context) => AddLanguageDialog(
        projectId: details.project.id,
        existingLanguageIds: existingLanguageIds,
      ),
    );
  }

  void _handleOpenEditor(
    BuildContext context,
    String projectId,
    String languageId,
  ) {
    context.push(AppRoutes.translationEditor(projectId, languageId));
  }

  Future<void> _handleSaveSettings(
    BuildContext context,
    WidgetRef ref,
    ProjectDetails details,
    int batchSize,
    int parallelBatches,
    String? customPrompt,
  ) async {
    final projectRepo = ref.read(projectRepositoryProvider);

    final updatedProject = details.project.copyWith(
      batchSize: batchSize,
      parallelBatches: parallelBatches,
      customPrompt: customPrompt,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final result = await projectRepo.update(updatedProject);

    if (!context.mounted) return;

    if (result.isOk) {
      // Refresh project details
      ref.invalidate(projectDetailsProvider(details.project.id));

      FluentToast.success(context, 'Settings saved successfully');
    } else {
      FluentToast.error(context, 'Failed to save settings: ${result.error}');
    }
  }

  void _handleExportAll(BuildContext context, ProjectDetails details) {
    FluentToast.info(context, 'Export all languages for: ${details.project.name}');
  }

  void _handleDeleteProject(
    BuildContext context,
    WidgetRef ref,
    ProjectDetails details,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
          'Are you sure you want to delete "${details.project.name}"? This action cannot be undone.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              // Show loading indicator and capture context
              final loadingDialogContext = context;
              showDialog(
                context: loadingDialogContext,
                barrierDismissible: false,
                builder: (loadingContext) => PopScope(
                  canPop: false,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              );

              // Delete the project
              final projectRepo = ref.read(projectRepositoryProvider);
              final result = await projectRepo.delete(details.project.id);

              // Close loading indicator using root navigator
              if (loadingDialogContext.mounted) {
                Navigator.of(loadingDialogContext, rootNavigator: true).pop();
              }

              if (!context.mounted) return;

              if (result.isOk) {
                // Refresh projects list
                ref.invalidate(projectsWithDetailsProvider);
                
                // Navigate to projects list
                if (context.mounted) {
                  context.go(AppRoutes.projects);
                }
                
                // Show success toast after navigation
                if (context.mounted) {
                  FluentToast.success(
                    context,
                    'Project "${details.project.name}" deleted successfully',
                  );
                }
              } else {
                if (context.mounted) {
                  FluentToast.error(
                    context,
                    'Failed to delete project: ${result.error}',
                  );
                }
              }
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
