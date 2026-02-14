import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/app_router.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
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
/// - Batch selection and export
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
      // Also reset selection mode when entering the screen
      ref.read(batchProjectSelectionProvider.notifier).exitSelectionMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectsAsync = ref.watch(paginatedProjectsProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final selectionState = ref.watch(batchProjectSelectionProvider);

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
            projectsAsync.when(
              data: (projects) => ProjectsToolbar(
                languages: languagesAsync.asData?.value ?? [],
                allProjectIds: projects.map((p) => p.project.id).toList(),
                onExportSelected: () => _startBatchExport(
                  context,
                  projects,
                  selectionState,
                  languagesAsync.asData?.value ?? [],
                ),
              ),
              loading: () => const ProjectsToolbar(),
              error: (_, _) => const ProjectsToolbar(),
            ),
            const SizedBox(height: 24),
            // Projects grid/list
            Expanded(
              child: projectsAsync.when(
                data: (projects) => _buildContent(context, projects, selectionState),
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
    BatchProjectSelectionState selectionState,
  ) {
    final theme = Theme.of(context);
    final resyncState = ref.watch(projectResyncProvider);

    if (projects.isEmpty) {
      return _buildEmptyState(context, theme);
    }

    return ProjectGrid(
      projects: projects,
      onProjectTap: (projectId) => _navigateToProject(context, projectId),
      onResync: (projectId) => _handleResync(context, projectId),
      resyncingProjects: resyncState.resyncingProjects,
      isSelectionMode: selectionState.isSelectionMode,
      selectedProjectIds: selectionState.selectedProjectIds,
      onSelectionToggle: (projectId) {
        ref.read(batchProjectSelectionProvider.notifier).toggleProject(projectId);
      },
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

  Future<void> _handleResync(BuildContext context, String projectId) async {
    try {
      await ref.read(projectResyncProvider.notifier).resync(projectId);
      if (context.mounted) {
        FluentToast.success(context, 'Project resynced successfully');
        // Refresh the projects list
        ref.invalidate(projectsWithDetailsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        FluentToast.error(context, 'Resync failed: $e');
      }
    }
  }

  void _startBatchExport(
    BuildContext context,
    List<ProjectWithDetails> allProjects,
    BatchProjectSelectionState selectionState,
    List<dynamic> languages,
  ) {
    if (!selectionState.canExport) return;

    // Find the selected language
    final selectedLanguage = languages.cast<dynamic>().firstWhere(
      (l) => l.id == selectionState.selectedLanguageId,
      orElse: () => null,
    );

    if (selectedLanguage == null) return;

    // Build project info list
    final projectsToExport = allProjects
        .where((p) => selectionState.selectedProjectIds.contains(p.project.id))
        .map((p) => ProjectExportInfo(
              id: p.project.id,
              name: p.project.name,
            ))
        .toList();

    if (projectsToExport.isEmpty) return;

    // Stage data and navigate to export screen
    ref.read(batchExportStagingProvider.notifier).set(
      BatchExportStagingData(
        projects: projectsToExport,
        languageCode: selectedLanguage.code,
        languageName: selectedLanguage.name,
      ),
    );
    context.goBatchPackExport();
  }
}
