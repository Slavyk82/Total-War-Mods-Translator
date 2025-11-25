import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/projects_screen_providers.dart';
import '../widgets/project_grid.dart';
import '../widgets/projects_toolbar.dart';
import '../widgets/edit_project_dialog.dart';
import '../widgets/export_project_dialog.dart';

/// Projects screen displaying all translation projects.
///
/// Features:
/// - Responsive grid/list view of project cards
/// - Search, filter, and sort functionality
/// - Pagination (20 items per page)
/// - Create new project wizard
/// - Navigate to project details
/// - Export and delete actions
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projectsAsync = ref.watch(paginatedProjectsProvider);

    return FluentScaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(theme),
            const SizedBox(height: 24),
            // Toolbar with search, filter, sort controls
            const ProjectsToolbar(),
            const SizedBox(height: 24),
            // Projects grid/list
            Expanded(
              child: projectsAsync.when(
                data: (projects) => _buildContent(context, ref, projects),
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
          FluentIcons.folder_24_regular,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Text(
          'Projects',
          style: theme.textTheme.headlineLarge,
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<ProjectWithDetails> projects,
  ) {
    final theme = Theme.of(context);

    if (projects.isEmpty) {
      return _buildEmptyState(context, theme, ref);
    }

    return Column(
      children: [
        // Projects grid/list
        Expanded(
          child: ProjectGrid(
            projects: projects,
            onProjectTap: (projectId) => _navigateToProject(context, projectId),
            onProjectEdit: (projectId) => _editProject(context, projectId),
            onProjectExport: (projectId) => _exportProject(context, projectId),
            onProjectDelete: (projectId) =>
                _confirmDeleteProject(context, ref, projectId),
          ),
        ),
        const SizedBox(height: 16),
        // Pagination controls
        _buildPagination(context, ref, theme),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme, WidgetRef ref) {
    final filter = ref.watch(projectsFilterProvider);
    final hasActiveFilters = filter.searchQuery.isNotEmpty ||
        filter.statusFilters.isNotEmpty ||
        filter.gameFilters.isNotEmpty ||
        filter.languageFilters.isNotEmpty ||
        filter.showOnlyWithUpdates;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasActiveFilters
                ? FluentIcons.filter_dismiss_24_regular
                : FluentIcons.folder_24_regular,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            hasActiveFilters ? 'No projects match filters' : 'No projects yet',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasActiveFilters
                ? 'Try adjusting your filters'
                : 'Go to Mods screen to create a project from a mod',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
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
            'Loading projects...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
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
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load projects',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    final totalPagesAsync = ref.watch(totalPagesProvider);
    final filter = ref.watch(projectsFilterProvider);

    return totalPagesAsync.when(
      data: (totalPages) {
        if (totalPages <= 1) {
          return const SizedBox.shrink();
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PaginationButton(
              icon: FluentIcons.chevron_left_24_regular,
              onTap: filter.currentPage > 0
                  ? () {
                      ref.read(projectsFilterProvider.notifier).updatePage(
                        filter.currentPage - 1,
                      );
                    }
                  : null,
            ),
            const SizedBox(width: 16),
            Text(
              'Page ${filter.currentPage + 1} of $totalPages',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(width: 16),
            _PaginationButton(
              icon: FluentIcons.chevron_right_24_regular,
              onTap: filter.currentPage < totalPages - 1
                  ? () {
                      ref.read(projectsFilterProvider.notifier).updatePage(
                        filter.currentPage + 1,
                      );
                    }
                  : null,
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  void _navigateToProject(BuildContext context, String projectId) {
    context.go('/projects/$projectId');
  }

  void _editProject(BuildContext context, String projectId) {
    showDialog(
      context: context,
      builder: (context) => EditProjectDialog(projectId: projectId),
    );
  }

  void _exportProject(BuildContext context, String projectId) {
    showDialog(
      context: context,
      builder: (context) => ExportProjectDialog(projectId: projectId),
    );
  }

  void _confirmDeleteProject(
    BuildContext context,
    WidgetRef ref,
    String projectId,
  ) {
    print('DEBUG: _confirmDeleteProject called for project: $projectId');
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              FluentIcons.warning_24_regular,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            const Text('Delete Project'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this project? This action cannot be undone.',
        ),
        actions: [
          _FluentButton(
            icon: FluentIcons.dismiss_24_regular,
            label: 'Cancel',
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
          const SizedBox(width: 8),
          _FluentButton(
            icon: FluentIcons.delete_24_regular,
            label: 'Delete',
            onTap: () {
              Navigator.of(dialogContext).pop();
              _deleteProject(context, ref, projectId);
            },
          ),
        ],
      ),
    );
  }

  void _deleteProject(BuildContext context, WidgetRef ref, String projectId) async {
    print('DEBUG: _deleteProject called for project: $projectId');
    final projectRepo = ref.read(projectRepositoryProvider);
    print('DEBUG: projectRepo obtained');

    // Show loading indicator and capture its context
    final dialogContext = context;
    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (loadingContext) => PopScope(
        canPop: false,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );

    // Delete the project
    print('DEBUG: Calling projectRepo.delete()');
    final result = await projectRepo.delete(projectId);
    print('DEBUG: Delete result: ${result.isOk ? "OK" : "ERROR - ${result.error}"}');

    // Close loading indicator using root navigator
    if (dialogContext.mounted) {
      print('DEBUG: Closing loading dialog');
      Navigator.of(dialogContext, rootNavigator: true).pop();
    }

    if (!context.mounted) {
      print('DEBUG: Context not mounted after dialog close, returning');
      return;
    }

    if (result.isOk) {
      print('DEBUG: Delete successful, refreshing list');
      // Refresh projects list first
      if (context.mounted) {
        try {
          ref.invalidate(projectsWithDetailsProvider);
        } catch (e) {
          print('DEBUG: Error invalidating provider: $e');
        }
        
        // Show success toast after refresh
        FluentToast.success(context, 'Project deleted successfully');
      }
    } else {
      print('DEBUG: Delete failed with error: ${result.error}');
      if (context.mounted) {
        FluentToast.error(
          context,
          'Failed to delete project: ${result.error}',
        );
      }
    }
  }
}

/// Pagination button with Fluent Design hover effect
class _PaginationButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PaginationButton({
    required this.icon,
    this.onTap,
  });

  @override
  State<_PaginationButton> createState() => _PaginationButtonState();
}

class _PaginationButtonState extends State<_PaginationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isEnabled && _isHovered
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: isEnabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

/// Reusable Fluent Design button widget
class _FluentButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _FluentButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  State<_FluentButton> createState() => _FluentButtonState();
}

class _FluentButtonState extends State<_FluentButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.9)
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
