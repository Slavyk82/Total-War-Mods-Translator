import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../providers/projects_screen_providers.dart';
import '../widgets/project_grid.dart';
import '../widgets/projects_toolbar.dart';

/// Projects screen displaying all translation projects.
///
/// Features:
/// - Responsive grid/list view of project cards
/// - Search, filter, and sort functionality
/// - Pagination (20 items per page)
/// - Create new project wizard
/// - Navigate to project details
/// - Export and delete actions
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  @override
  void initState() {
    super.initState();
    // Reset filters when navigating to this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(projectsFilterProvider.notifier).resetAll();
    });
  }

  @override
  Widget build(BuildContext context) {
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
                data: (projects) => _buildContent(context, projects),
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
    List<ProjectWithDetails> projects,
  ) {
    final theme = Theme.of(context);

    if (projects.isEmpty) {
      return _buildEmptyState(context, theme);
    }

    return ProjectGrid(
      projects: projects,
      onProjectTap: (projectId) => _navigateToProject(context, projectId),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    final filter = ref.watch(projectsFilterProvider);
    final hasActiveFilters = filter.searchQuery.isNotEmpty ||
        filter.gameFilters.isNotEmpty ||
        filter.languageFilters.isNotEmpty ||
        filter.showOnlyWithUpdates ||
        filter.quickFilter != ProjectQuickFilter.none;

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

  void _navigateToProject(BuildContext context, String projectId) {
    context.go('/projects/$projectId');
  }
}
