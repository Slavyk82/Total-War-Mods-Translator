import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/router/app_router.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/project_cover_thumbnail.dart';
import 'package:twmt/widgets/lists/status_pill.dart';
import 'package:twmt/widgets/detail/home_back_toolbar.dart';
import '../providers/projects_bulk_menu_visibility_provider.dart';
import '../providers/projects_screen_providers.dart';
import '../widgets/projects_bulk_menu_panel.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';

/// Projects screen — filterable list archetype per UI spec §7.1.
///
/// Uses [FilterToolbar] + [ListRow] primitives and the token palette.
/// Existing feature set is preserved: search, sort, quick filters.
class ProjectsScreen extends ConsumerStatefulWidget {
  /// Optional quick-filter to activate on mount — used when the Home
  /// dashboard navigates here with a `?filter=...` query param.
  final ProjectQuickFilter? initialFilter;

  const ProjectsScreen({super.key, this.initialFilter});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  @override
  void initState() {
    super.initState();
    // Reset filters when navigating to this screen, then apply the optional
    // initial quick-filter forwarded from the route's `?filter=...` param.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(projectsFilterProvider.notifier);
      notifier.resetAll();
      final initial = widget.initialFilter;
      if (initial != null && initial != ProjectQuickFilter.none) {
        notifier.setQuickFilter(initial);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProjectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GoRouter reuses the same page (and state) across `?filter=…` changes
    // because its pageKey is derived from the matched location without query
    // params. Re-apply the incoming filter so navigating from the Home "To
    // review" card always lands on the right filter, even when the Projects
    // screen is already on screen.
    if (oldWidget.initialFilter != widget.initialFilter) {
      final initial = widget.initialFilter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = ref.read(projectsFilterProvider.notifier);
        notifier.setQuickFilter(initial ?? ProjectQuickFilter.none);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final projectsAsync = ref.watch(paginatedProjectsProvider);
    final bulkMenuVisible = ref.watch(projectsBulkMenuVisibilityProvider);

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(leading: _buildLeading(projectsAsync)),
          FilterToolbar(
            leading: const SizedBox.shrink(),
            expandLeading: false,
            trailing: _buildTrailingActions(),
            pillGroups: [_buildQuickFilterGroup()],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: projectsAsync.when(
                    data: (projects) => _buildContent(projects),
                    loading: () => _buildLoading(),
                    error: (e, _) => _buildError(e),
                  ),
                ),
                if (bulkMenuVisible) const ProjectsBulkMenuPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Toolbar slots
  // ---------------------------------------------------------------------------

  Widget _buildLeading(AsyncValue<List<ProjectWithDetails>> async) {
    final count = async.asData?.value.length ?? 0;
    return ListToolbarLeading(
      icon: FluentIcons.folder_24_regular,
      title: 'Projects',
      countLabel: '$count ${count == 1 ? 'project' : 'projects'}',
    );
  }

  List<Widget> _buildTrailingActions() {
    return [
      const Expanded(child: _SearchField()),
      const _BulkMenuToggleButton(),
    ];
  }

  FilterPillGroup _buildQuickFilterGroup() {
    final currentFilter = ref.watch(
      projectsFilterProvider.select((s) => s.quickFilter),
    );
    final counts =
        ref.watch(projectQuickFilterCountsProvider).value ?? const {};

    FilterPill pill(String label, ProjectQuickFilter filter, String tooltip) {
      return FilterPill(
        label: label,
        selected: currentFilter == filter,
        count: counts[filter],
        tooltip: tooltip,
        onToggle: () {
          ref.read(projectsFilterProvider.notifier).setQuickFilter(
                currentFilter == filter ? ProjectQuickFilter.none : filter,
              );
        },
      );
    }

    return FilterPillGroup(
      label: 'STATE',
      clearLabel: 'Clear',
      clearTooltip: t.tooltips.projects.filterClear,
      onClear: () => ref
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.none),
      pills: [
        pill(
          'Needs Update',
          ProjectQuickFilter.needsUpdate,
          t.tooltips.projects.filterNeedsUpdate,
        ),
        pill(
          'Needs Review',
          ProjectQuickFilter.needsReview,
          t.tooltips.projects.filterNeedsReview,
        ),
        pill(
          'Incomplete',
          ProjectQuickFilter.incomplete,
          t.tooltips.projects.filterIncomplete,
        ),
        pill(
          'Completed',
          ProjectQuickFilter.hasCompleteLanguage,
          t.tooltips.projects.filterHasComplete,
        ),
        pill(
          'Exported',
          ProjectQuickFilter.exported,
          t.tooltips.projects.filterExported,
        ),
        pill(
          'Not Exported',
          ProjectQuickFilter.notExported,
          t.tooltips.projects.filterNotExported,
        ),
        pill(
          'Export Outdated',
          ProjectQuickFilter.exportOutdated,
          t.tooltips.projects.filterExportOutdated,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  Widget _buildContent(List<ProjectWithDetails> projects) {
    if (projects.isEmpty) {
      return _buildEmptyState();
    }

    final resyncState = ref.watch(projectResyncProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProjectsListHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final details = projects[index];
              final projectId = details.project.id;
              return _ProjectRow(
                details: details,
                isResyncing: resyncState.resyncingProjects.contains(projectId),
                onTap: () => openProjectEditor(context, ref, projectId),
                onResync: () => _handleResync(context, projectId),
                onDelete: () => _handleDeleteProject(context, details),
                onOpenLanguage: (languageId) => context.go(
                  AppRoutes.translationEditor(projectId, languageId),
                ),
                onLaunchSteam: (modId) => _launchSteamWorkshop(modId),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final tokens = context.tokens;
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
            size: 56,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 16),
          Text(
            hasActiveFilters ? 'No projects match filters' : 'No projects yet',
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilters
                ? 'Try adjusting your filters'
                : 'Go to Mods screen to create a project from a mod',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading projects...',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object error) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: tokens.err,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load projects',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleResync(BuildContext context, String projectId) async {
    try {
      await ref.read(projectResyncProvider.notifier).resync(projectId);
      if (context.mounted) {
        FluentToast.success(context, 'Project resynced successfully');
        ref.invalidate(projectsWithDetailsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        FluentToast.error(context, 'Resync failed: $e');
      }
    }
  }

  /// Open the Steam Workshop page for a given mod id in the user's browser.
  Future<void> _launchSteamWorkshop(String modId) async {
    final url = Uri.parse(
        'https://steamcommunity.com/sharedfiles/filedetails/?id=$modId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// Show a confirmation dialog, then delete the project and patch the list
  /// state optimistically via [ProjectsWithDetailsNotifier.removeProject].
  Future<void> _handleDeleteProject(
      BuildContext context, ProjectWithDetails details) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TokenConfirmDialog(
        title: 'Delete Project',
        message: 'Are you sure you want to delete "${details.project.name}"?',
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
      ref
          .read(projectsWithDetailsProvider.notifier)
          .removeProject(details.project.id);
      FluentToast.success(
          context, 'Project "${details.project.name}" deleted');
    } else {
      FluentToast.error(
          context, 'Failed to delete project: ${result.error}');
    }
  }

}

// =============================================================================
// Toolbar widgets (search, sort)
// =============================================================================

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query =
        ref.watch(projectsFilterProvider.select((s) => s.searchQuery));
    return ListSearchField(
      width: null,
      value: query,
      hintText: 'Search projects...',
      onChanged: (value) => ref
          .read(projectsFilterProvider.notifier)
          .updateSearchQuery(value),
      onClear: () => ref
          .read(projectsFilterProvider.notifier)
          .updateSearchQuery(''),
    );
  }
}

class _BulkMenuToggleButton extends ConsumerWidget {
  const _BulkMenuToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final isActive = ref.watch(projectsBulkMenuVisibilityProvider);
    return Tooltip(
      message: isActive ? 'Hide bulk menu' : 'Show bulk menu',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => ref
              .read(projectsBulkMenuVisibilityProvider.notifier)
              .toggle(),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isActive ? tokens.accentBg : tokens.panel2,
              border: Border.all(
                color: isActive ? tokens.accent : tokens.border,
              ),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.panel_right_24_regular,
                  size: 16,
                  color: isActive ? tokens.accent : tokens.textMid,
                ),
                const SizedBox(width: 6),
                Text(
                  isActive ? 'Hide bulk menu' : 'Show bulk menu',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: isActive ? tokens.accent : tokens.textMid,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// List header + row
// =============================================================================

const List<ListRowColumn> _projectColumns = [
  ListRowColumn.fixed(80), // cover
  ListRowColumn.flex(3), // name + meta
  ListRowColumn.flex(2), // languages + per-language progress
  ListRowColumn.fixed(180), // last modified
  ListRowColumn.fixed(150), // status pill
];

// Matches the IconButton footprint (16px icon + 12px padding) plus the
// right-side gap kept between the delete button and the list's scrollbar
// so the icon does not sit right next to the scroll track (miss-click risk).
const double _projectRowTrailingActionWidth = 52;

/// Interactive header for the projects list: click a sortable cell to cycle
/// the column's sort state (same column → flip direction, other column →
/// switch and pick a sensible default). Mirrors `ListRowHeader`'s chrome but
/// renders sortable cells with an arrow indicator.
class _ProjectsListHeader extends ConsumerWidget {
  const _ProjectsListHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final filter = ref.watch(projectsFilterProvider);
    final notifier = ref.read(projectsFilterProvider.notifier);

    Widget cell(
      String label,
      ProjectSortOption field,
    ) =>
        _SortableHeaderCell(
          label: label,
          field: field,
          activeField: filter.sortBy,
          ascending: filter.sortAscending,
          onTap: () => notifier.toggleSort(field),
        );

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 80),
          Expanded(
            flex: 3,
            child: cell('Project', ProjectSortOption.name),
          ),
          Expanded(
            flex: 2,
            child: cell('Languages & progress', ProjectSortOption.progress),
          ),
          SizedBox(
            width: 180,
            child: cell('Modified', ProjectSortOption.dateModified),
          ),
          SizedBox(
            width: 150,
            child: _StaticHeaderLabel(label: 'Status'),
          ),
          const SizedBox(width: _projectRowTrailingActionWidth),
        ],
      ),
    );
  }
}

class _StaticHeaderLabel extends StatelessWidget {
  const _StaticHeaderLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Text(
      label.toUpperCase(),
      textAlign: TextAlign.center,
      style: tokens.fontMono.copyWith(
        fontSize: 11,
        color: tokens.textDim,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _SortableHeaderCell extends StatelessWidget {
  const _SortableHeaderCell({
    required this.label,
    required this.field,
    required this.activeField,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final ProjectSortOption field;
  final ProjectSortOption activeField;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isActive = activeField == field;
    final color = isActive ? tokens.accent : tokens.textDim;
    final arrow = isActive
        ? (ascending
            ? FluentIcons.arrow_up_16_filled
            : FluentIcons.arrow_down_16_filled)
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: tokens.fontMono.copyWith(
                  fontSize: 11,
                  color: color,
                  letterSpacing: 0.8,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (arrow != null) ...[
              const SizedBox(width: 4),
              Icon(arrow, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final ProjectWithDetails details;
  final bool isResyncing;
  final VoidCallback onTap;
  final VoidCallback onResync;
  final VoidCallback onDelete;
  final ValueChanged<String> onOpenLanguage; // languageId
  final ValueChanged<String> onLaunchSteam; // modSteamId

  const _ProjectRow({
    required this.details,
    required this.isResyncing,
    required this.onTap,
    required this.onResync,
    required this.onDelete,
    required this.onOpenLanguage,
    required this.onLaunchSteam,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final project = details.project;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final lastModified = DateFormat('dd/MM/yyyy HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(project.updatedAt * 1000));
    final exportStr = details.lastPackExport != null
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(
            details.lastPackExport!.exportedAt * 1000))
        : null;

    return ListRow(
      columns: _projectColumns,
      onTap: onTap,
      // Null height → the row grows to fit the stacked per-language lines.
      // A project with 3+ configured languages blows past the default 56px
      // footprint; fixing the row height there causes a RenderFlex overflow.
      height: null,
      trailingAction: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IconButton(
          key: Key('project-row-delete-${project.id}'),
          icon: const Icon(FluentIcons.delete_24_regular, size: 16),
          tooltip: 'Delete project',
          onPressed: onDelete,
          color: Theme.of(context).colorScheme.error,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ),
      children: [
        ProjectCoverThumbnail(
          imageUrl: project.imageUrl,
          isGameTranslation: project.isGameTranslation,
          gameCode: details.gameInstallation?.gameCode,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (project.modSteamId != null) ...[
                    _SteamLinkPill(
                      modSteamId: project.modSteamId!,
                      onTap: () => onLaunchSteam(project.modSteamId!),
                    ),
                  ] else if (!project.isGameTranslation) ...[
                    Text(
                      'Local pack',
                      style: tokens.fontMono.copyWith(
                        fontSize: 11,
                        color: tokens.textDim,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Game translation',
                      style: tokens.fontMono.copyWith(
                        fontSize: 11,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                  if (project.modSteamId == null &&
                      !project.isGameTranslation) ...[
                    const SizedBox(width: 8),
                    _ResyncIcon(isResyncing: isResyncing, onTap: onResync),
                  ],
                  if (exportStr != null) ...[
                    const SizedBox(width: 10),
                    Icon(
                      FluentIcons.arrow_export_24_regular,
                      size: 12,
                      color: tokens.textFaint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      exportStr,
                      style: tokens.fontMono.copyWith(
                        fontSize: 10.5,
                        color: tokens.textFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Languages column — one clickable mini-progress-row per language.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _RowLanguagesCell(
            projectId: project.id,
            languages: details.languages,
            onOpenLanguage: onOpenLanguage,
          ),
        ),
        // Last modified
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            lastModified,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: tokens.textDim,
            ),
          ),
        ),
        // Status pill
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _StatusPill(details: details),
        ),
      ],
    );
  }
}

/// Clickable Steam Workshop pill used in the row's name+meta column.
///
/// Opens the Steam Workshop page for [modSteamId] in the user's browser via
/// [onTap]. Renders as the previous inline icon+id pair but with a pointer
/// cursor and a tooltip advertising the click target.
class _SteamLinkPill extends StatelessWidget {
  const _SteamLinkPill({required this.modSteamId, required this.onTap});
  final String modSteamId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: 'Open in Steam Workshop',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.cloud_24_regular,
                    size: 12, color: tokens.textDim),
                const SizedBox(width: 4),
                Text(
                  modSteamId,
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stack of one clickable mini-progress line per configured language.
///
/// Replaces the previous "target language" + "overall progress" columns.
/// Each line opens the editor directly on that language via [onOpenLanguage].
class _RowLanguagesCell extends StatelessWidget {
  const _RowLanguagesCell({
    required this.projectId,
    required this.languages,
    required this.onOpenLanguage,
  });

  final String projectId;
  final List<ProjectLanguageWithInfo> languages;
  final ValueChanged<String> onOpenLanguage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (languages.isEmpty) {
      return Text('No target language',
          style: tokens.fontBody
              .copyWith(fontSize: 12, color: tokens.textFaint));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in languages)
          _RowLanguageLine(
            key: Key(
                'project-row-lang-$projectId-${l.projectLanguage.languageId}'),
            details: l,
            onTap: () => onOpenLanguage(l.projectLanguage.languageId),
          ),
      ],
    );
  }
}

/// A single language/progress line rendered inside [_RowLanguagesCell].
///
/// Uses a plain [LinearProgressIndicator] (rather than the legacy
/// `_ProgressBar`) to keep the row dense when multiple languages stack.
class _RowLanguageLine extends StatelessWidget {
  const _RowLanguageLine({super.key, required this.details, required this.onTap});
  final ProjectLanguageWithInfo details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final percent = details.progressPercent.clamp(0.0, 100.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  details.language?.name ?? 'Unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textMid,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 4,
                    backgroundColor: tokens.border,
                    valueColor: AlwaysStoppedAnimation(tokens.accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text(
                  '${percent.toInt()}%',
                  textAlign: TextAlign.right,
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ProjectWithDetails details;
  const _StatusPill({required this.details});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final analysis = details.updateAnalysis;
    final hasModUpdateImpact = details.project.hasModUpdateImpact;

    if (hasModUpdateImpact) {
      return _pill(
        label: 'Mod updated',
        fg: tokens.warn,
        bg: tokens.warnBg,
        tooltip:
            'This project was modified by a mod update.\nSome translations may need review.',
      );
    }
    if (analysis != null && analysis.hasPendingChanges) {
      return _pill(
        label: analysis.summary,
        fg: tokens.err,
        bg: tokens.errBg,
        tooltip: _buildChangesTooltip(analysis),
      );
    }
    if (analysis != null) {
      return _pill(
        label: 'Up to date',
        fg: tokens.ok,
        bg: tokens.okBg,
      );
    }
    if (details.isModifiedSinceLastExport) {
      return _pill(
        label: 'Export outdated',
        fg: tokens.warn,
        bg: tokens.warnBg,
        tooltip: t.tooltips.projects.filterExportOutdated,
      );
    }
    if (details.hasBeenExported) {
      if (details.hasSteamPublishWorkflow &&
          !details.isPackPublishedOnSteam) {
        return _pill(
          label: 'Unpublished',
          fg: tokens.textDim,
          bg: tokens.panel,
          tooltip:
              'Pack generated locally — not yet published on Steam Workshop',
        );
      }
      return _pill(
        label: 'Exported',
        fg: tokens.ok,
        bg: tokens.okBg,
      );
    }
    return _pill(
      label: 'Draft',
      fg: tokens.textDim,
      bg: tokens.panel,
    );
  }

  String _buildChangesTooltip(ModUpdateAnalysis analysis) {
    final lines = <String>[];
    if (analysis.hasNewUnits) {
      lines.add('+${analysis.newUnitsCount} new translations to add');
    }
    if (analysis.hasRemovedUnits) {
      lines.add('-${analysis.removedUnitsCount} translations removed');
    }
    if (analysis.hasModifiedUnits) {
      lines.add('~${analysis.modifiedUnitsCount} source texts changed');
    }
    return lines.join('\n');
  }

  Widget _pill({
    required String label,
    required Color fg,
    required Color bg,
    String? tooltip,
  }) {
    return StatusPill(
      label: label,
      foreground: fg,
      background: bg,
      tooltip: tooltip,
    );
  }
}

class _ResyncIcon extends StatelessWidget {
  final bool isResyncing;
  final VoidCallback onTap;
  const _ResyncIcon({required this.isResyncing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (isResyncing) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: tokens.accent,
        ),
      );
    }
    return Tooltip(
      message: 'Resync with source pack file',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Icon(
            FluentIcons.arrow_sync_24_regular,
            size: 14,
            color: tokens.accent,
          ),
        ),
      ),
    );
  }
}
