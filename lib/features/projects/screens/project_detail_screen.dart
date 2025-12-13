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
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Project detail screen showing comprehensive project information.
///
/// Displays project overview, target languages with progress,
/// translation statistics, and action buttons.
/// Organized in a responsive layout with sections.
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final projectDetailsAsync = ref.watch(projectDetailsProvider(widget.projectId));

    return FluentScaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      header: FluentHeader(
        backgroundColor: Theme.of(context).colorScheme.surface,
        leading: FluentIconButton(
          icon: const Icon(FluentIcons.arrow_left_24_regular),
          onPressed: () {
            // Increment stats version to force refresh of all dependent providers
            ref.read(translationStatsVersionProvider.notifier).increment();
            Navigator.of(context).pop();
          },
          tooltip: 'Back',
        ),
        title: projectDetailsAsync.when(
          data: (details) => details.project.name,
          loading: () => 'Loading...',
          error: (error, stackTrace) => 'Project Details',
        ),
      ),
      body: projectDetailsAsync.when(
        data: (details) => _buildContent(context, details),
        loading: () => _buildLoading(context),
        error: (error, stack) => _buildError(context, error),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ProjectDetails details,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjectOverviewSection(
            project: details.project,
            onDelete: () => _handleDeleteProject(context, details),
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
                      child: _buildLanguagesSection(context, details),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: _buildStatsSection(details),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildLanguagesSection(context, details),
                    const SizedBox(height: 24),
                    _buildStatsSection(details),
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
          totalUnits: langDetails.totalUnits,
          translatedUnits: langDetails.translatedUnits,
          onOpenEditor: () => _handleOpenEditor(
            context,
            details.project.id,
            langDetails.projectLanguage.languageId,
          ),
          onDelete: () => _handleDeleteLanguage(
            context,
            details,
            langDetails,
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

  Widget _buildStatsSection(ProjectDetails details) {
    return ProjectStatsCard(stats: details.stats);
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

  Future<void> _handleOpenEditor(
    BuildContext context,
    String projectId,
    String languageId,
  ) async {
    // Navigate to editor and wait for it to be popped
    await context.push(AppRoutes.translationEditor(projectId, languageId));

    // Refresh data when returning from editor to ensure stats are up to date
    if (mounted) {
      ref.invalidate(projectDetailsProvider(widget.projectId));
      ref.invalidate(projectsWithDetailsProvider);
    }
  }

  void _handleDeleteProject(
    BuildContext context,
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

  void _handleDeleteLanguage(
    BuildContext context,
    ProjectDetails details,
    ProjectLanguageDetails langDetails,
  ) {
    final languageName = langDetails.language.displayName;
    final translatedCount = langDetails.translatedUnits;
    final hasTranslations = translatedCount > 0;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "$languageName" from this project?',
            ),
            if (hasTranslations) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.warning_24_regular,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will permanently delete $translatedCount translation(s).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              // Delete the project language
              final projectLangRepo = ref.read(projectLanguageRepositoryProvider);
              final result = await projectLangRepo.delete(langDetails.projectLanguage.id);

              if (!context.mounted) return;

              if (result.isOk) {
                // Force refresh project details immediately
                ref.invalidate(projectDetailsProvider(widget.projectId));
                ref.invalidate(projectsWithDetailsProvider);
                // Trigger re-read to force UI update
                ref.read(projectDetailsProvider(widget.projectId));

                FluentToast.success(
                  context,
                  '"$languageName" removed from project',
                );
              } else {
                FluentToast.error(
                  context,
                  'Failed to delete language: ${result.error}',
                );
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
