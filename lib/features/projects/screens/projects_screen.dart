import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../config/router/app_router.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';
import '../providers/projects_screen_providers.dart';

/// Projects screen — filterable list archetype per UI spec §7.1.
///
/// Uses [FilterToolbar] + [ListRow] primitives and the token palette.
/// Existing feature set is preserved: search, sort, quick filters,
/// batch-selection mode with language picker + pack export.
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
    final tokens = context.tokens;
    final projectsAsync = ref.watch(paginatedProjectsProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);
    final selectionState = ref.watch(batchProjectSelectionProvider);

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterToolbar(
            leading: _buildLeading(projectsAsync),
            trailing: _buildTrailingActions(selectionState),
            pillGroups: [_buildQuickFilterGroup()],
          ),
          if (selectionState.isSelectionMode)
            _SelectionBar(
              selectionState: selectionState,
              languages: languagesAsync.asData?.value ?? const [],
              allProjectIds: projectsAsync.asData?.value
                      .map((p) => p.project.id)
                      .toList() ??
                  const [],
              onExportSelected: () => _startBatchExport(
                context,
                projectsAsync.asData?.value ?? const [],
                selectionState,
                languagesAsync.asData?.value ?? const [],
              ),
            ),
          Expanded(
            child: projectsAsync.when(
              data: (projects) => _buildContent(projects, selectionState),
              loading: () => _buildLoading(),
              error: (e, _) => _buildError(e),
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

  List<Widget> _buildTrailingActions(BatchProjectSelectionState selection) {
    return [
      const _SearchField(),
      const _SortButton(),
      _SelectionModeButton(selectionState: selection),
    ];
  }

  FilterPillGroup _buildQuickFilterGroup() {
    final currentFilter = ref.watch(
      projectsFilterProvider.select((s) => s.quickFilter),
    );

    FilterPill pill(String label, ProjectQuickFilter filter, String tooltip) {
      return FilterPill(
        label: label,
        selected: currentFilter == filter,
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
      clearTooltip: TooltipStrings.projectsFilterClear,
      onClear: () => ref
          .read(projectsFilterProvider.notifier)
          .setQuickFilter(ProjectQuickFilter.none),
      pills: [
        pill(
          'Needs Update',
          ProjectQuickFilter.needsUpdate,
          TooltipStrings.projectsFilterNeedsUpdate,
        ),
        pill(
          'Incomplete',
          ProjectQuickFilter.incomplete,
          TooltipStrings.projectsFilterIncomplete,
        ),
        pill(
          'Has Complete',
          ProjectQuickFilter.hasCompleteLanguage,
          TooltipStrings.projectsFilterHasComplete,
        ),
        pill(
          'Exported',
          ProjectQuickFilter.exported,
          TooltipStrings.projectsFilterExported,
        ),
        pill(
          'Not Exported',
          ProjectQuickFilter.notExported,
          TooltipStrings.projectsFilterNotExported,
        ),
        pill(
          'Export Outdated',
          ProjectQuickFilter.exportOutdated,
          TooltipStrings.projectsFilterExportOutdated,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  Widget _buildContent(
    List<ProjectWithDetails> projects,
    BatchProjectSelectionState selectionState,
  ) {
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
              final isSelected =
                  selectionState.selectedProjectIds.contains(projectId);
              return _ProjectRow(
                details: details,
                selected: isSelected,
                isResyncing: resyncState.resyncingProjects.contains(projectId),
                onTap: () {
                  if (selectionState.isSelectionMode) {
                    ref
                        .read(batchProjectSelectionProvider.notifier)
                        .toggleProject(projectId);
                  } else {
                    context.go(AppRoutes.projectDetail(projectId));
                  }
                },
                onResync: () => _handleResync(context, projectId),
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
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
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
                fontStyle: tokens.fontDisplayItalic
                    ? FontStyle.italic
                    : FontStyle.normal,
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

  void _startBatchExport(
    BuildContext context,
    List<ProjectWithDetails> allProjects,
    BatchProjectSelectionState selectionState,
    List<Language> languages,
  ) {
    if (!selectionState.canExport) return;

    final Language? selectedLanguage = _findLanguage(
      languages,
      selectionState.selectedLanguageId,
    );
    if (selectedLanguage == null) return;

    final projectsToExport = allProjects
        .where((p) => selectionState.selectedProjectIds.contains(p.project.id))
        .map((p) => ProjectExportInfo(id: p.project.id, name: p.project.name))
        .toList();
    if (projectsToExport.isEmpty) return;

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

/// Returns the first [Language] whose id matches [id], or null if not found.
/// Replaces the older untyped `firstWhere(..., orElse: () => null)` pattern.
Language? _findLanguage(List<Language> languages, String? id) {
  if (id == null) return null;
  for (final l in languages) {
    if (l.id == id) return l;
  }
  return null;
}

// =============================================================================
// Toolbar widgets (search, sort, selection toggle)
// =============================================================================

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query =
        ref.watch(projectsFilterProvider.select((s) => s.searchQuery));
    return ListSearchField(
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

class _SortButton extends ConsumerWidget {
  const _SortButton();

  IconData _iconFor(ProjectSortOption option) {
    switch (option) {
      case ProjectSortOption.name:
        return FluentIcons.text_sort_ascending_24_regular;
      case ProjectSortOption.dateModified:
        return FluentIcons.calendar_24_regular;
      case ProjectSortOption.dateExported:
        return FluentIcons.arrow_export_24_regular;
      case ProjectSortOption.progress:
        return FluentIcons.chart_multiple_24_regular;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final sortBy =
        ref.watch(projectsFilterProvider.select((s) => s.sortBy));
    return PopupMenuButton<ProjectSortOption>(
      tooltip: 'Sort projects',
      offset: const Offset(0, 36),
      color: tokens.panel,
      itemBuilder: (context) => ProjectSortOption.values
          .map(
            (option) => PopupMenuItem(
              value: option,
              child: Row(
                children: [
                  Icon(_iconFor(option), size: 16, color: tokens.textMid),
                  const SizedBox(width: 10),
                  Text(
                    option.displayName,
                    style:
                        tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onSelected: (option) =>
          ref.read(projectsFilterProvider.notifier).updateSort(option),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tokens.panel2,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(sortBy), size: 16, color: tokens.textMid),
            const SizedBox(width: 6),
            Text(
              sortBy.displayName,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.textMid,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              FluentIcons.chevron_down_24_regular,
              size: 14,
              color: tokens.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionModeButton extends ConsumerWidget {
  final BatchProjectSelectionState selectionState;
  const _SelectionModeButton({required this.selectionState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final isActive = selectionState.isSelectionMode;
    return Tooltip(
      message: isActive
          ? 'Exit selection mode'
          : 'Select multiple projects for batch export',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            final notifier = ref.read(batchProjectSelectionProvider.notifier);
            if (isActive) {
              notifier.exitSelectionMode();
            } else {
              notifier.enterSelectionMode();
            }
          },
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
                  isActive
                      ? FluentIcons.checkbox_indeterminate_24_regular
                      : FluentIcons.checkbox_unchecked_24_regular,
                  size: 16,
                  color: isActive ? tokens.accent : tokens.textMid,
                ),
                const SizedBox(width: 6),
                Text(
                  'Selection',
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
// Selection bar (shown below toolbar when in batch-selection mode)
// =============================================================================

class _SelectionBar extends ConsumerWidget {
  final BatchProjectSelectionState selectionState;
  final List<Language> languages;
  final List<String> allProjectIds;
  final VoidCallback onExportSelected;

  const _SelectionBar({
    required this.selectionState,
    required this.languages,
    required this.allProjectIds,
    required this.onExportSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final Language? selectedLanguage = _findLanguage(
      languages,
      selectionState.selectedLanguageId,
    );
    final canExport = selectionState.canExport;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(tokens.radiusPill),
            ),
            child: Text(
              '${selectionState.selectedCount} selected',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.accentFg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SmallTextButton(
            label: 'All',
            tooltip: 'Select all projects',
            onTap: () => ref
                .read(batchProjectSelectionProvider.notifier)
                .selectAll(allProjectIds),
          ),
          const SizedBox(width: 6),
          SmallTextButton(
            label: 'None',
            tooltip: 'Deselect all projects',
            onTap: () => ref
                .read(batchProjectSelectionProvider.notifier)
                .deselectAll(),
          ),
          const Spacer(),
          // Language picker
          PopupMenuButton<String>(
            tooltip: 'Pick target language',
            enabled: languages.isNotEmpty,
            color: tokens.panel,
            offset: const Offset(0, 36),
            itemBuilder: (context) => languages
                .map<PopupMenuEntry<String>>(
                  (lang) => PopupMenuItem<String>(
                    value: lang.id,
                    child: Text(
                      lang.name,
                      style: tokens.fontBody
                          .copyWith(fontSize: 13, color: tokens.text),
                    ),
                  ),
                )
                .toList(),
            onSelected: (id) => ref
                .read(batchProjectSelectionProvider.notifier)
                .setLanguage(id),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: tokens.panel2,
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.translate_24_regular,
                    size: 14,
                    color: tokens.textMid,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selectedLanguage?.name ?? 'Select language',
                    style: tokens.fontBody.copyWith(
                      fontSize: 12.5,
                      color: tokens.textMid,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    FluentIcons.chevron_down_24_regular,
                    size: 12,
                    color: tokens.textDim,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Export button
          Tooltip(
            message: !canExport
                ? selectionState.selectedProjectIds.isEmpty
                    ? 'Select at least one project'
                    : 'Select a target language'
                : 'Export selected projects as .pack files',
            waitDuration: const Duration(milliseconds: 400),
            child: MouseRegion(
              cursor: canExport
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                onTap: canExport ? onExportSelected : null,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: canExport ? tokens.accent : tokens.panel2,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.arrow_export_24_regular,
                        size: 14,
                        color: canExport ? tokens.accentFg : tokens.textFaint,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Export',
                        style: tokens.fontBody.copyWith(
                          fontSize: 12.5,
                          color: canExport ? tokens.accentFg : tokens.textFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SmallTextButton(
            label: 'Cancel',
            tooltip: 'Exit selection mode',
            onTap: () => ref
                .read(batchProjectSelectionProvider.notifier)
                .exitSelectionMode(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// List header + row
// =============================================================================

const List<ListRowColumn> _projectColumns = [
  ListRowColumn.fixed(56), // cover
  ListRowColumn.flex(3), // name + meta
  ListRowColumn.fixed(140), // target language
  ListRowColumn.fixed(200), // progress
  ListRowColumn.fixed(180), // last modified
  ListRowColumn.fixed(150), // status pill
];

class _ProjectsListHeader extends StatelessWidget {
  const _ProjectsListHeader();

  @override
  Widget build(BuildContext context) {
    return ListRowHeader(
      columns: _projectColumns,
      labels: const ['', 'Project', 'Language', 'Progress', 'Modified', 'Status'],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final ProjectWithDetails details;
  final bool selected;
  final bool isResyncing;
  final VoidCallback onTap;
  final VoidCallback onResync;

  const _ProjectRow({
    required this.details,
    required this.selected,
    required this.isResyncing,
    required this.onTap,
    required this.onResync,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final project = details.project;
    final firstLanguage = details.languages.isNotEmpty
        ? details.languages.first
        : null;
    final otherLanguages = details.languages.length - 1;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final lastModified = DateFormat('dd/MM/yyyy HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(project.updatedAt * 1000));
    final exportStr = details.lastPackExport != null
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(
            details.lastPackExport!.exportedAt * 1000))
        : null;

    return ListRow(
      columns: _projectColumns,
      selected: selected,
      onTap: onTap,
      children: [
        _CoverThumbnail(
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
                    Icon(
                      FluentIcons.cloud_24_regular,
                      size: 12,
                      color: tokens.textDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      project.modSteamId!,
                      style: tokens.fontMono.copyWith(
                        fontSize: 11,
                        color: tokens.textDim,
                      ),
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
        // Target language column
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: firstLanguage == null
              ? Text(
                  '—',
                  style: tokens.fontBody
                      .copyWith(fontSize: 12, color: tokens.textFaint),
                )
              : Row(
                  children: [
                    Text(
                      firstLanguage.language?.name ?? 'Unknown',
                      style: tokens.fontBody.copyWith(
                        fontSize: 12.5,
                        color: tokens.textMid,
                      ),
                    ),
                    if (otherLanguages > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '+$otherLanguages',
                        style: tokens.fontMono.copyWith(
                          fontSize: 11,
                          color: tokens.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        // Progress column
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _ProgressBar(percent: details.overallProgress),
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

class _CoverThumbnail extends StatelessWidget {
  final String? imageUrl;
  final bool isGameTranslation;
  final String? gameCode;
  const _CoverThumbnail({
    required this.imageUrl,
    required this.isGameTranslation,
    required this.gameCode,
  });

  IconData _iconFor(String? code) {
    switch (code?.toLowerCase()) {
      case 'wh3':
      case 'wh2':
      case 'wh1':
        return FluentIcons.shield_24_regular;
      case 'troy':
        return FluentIcons.crown_24_regular;
      case 'threekingdoms':
      case '3k':
        return FluentIcons.people_24_regular;
      default:
        return FluentIcons.games_24_regular;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget fallback() => Icon(
          _iconFor(gameCode),
          size: 22,
          color: tokens.textMid,
        );

    Widget img;
    if (isGameTranslation) {
      img = Image.asset(
        'assets/twmt_icon.png',
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      img = Image.file(
        File(imageUrl!),
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else {
      img = fallback();
    }
    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.panel,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: img,
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double percent;
  const _ProgressBar({required this.percent});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final clamped = percent.clamp(0.0, 100.0);
    final Color color;
    if (clamped >= 100) {
      color = tokens.ok;
    } else if (clamped >= 50) {
      color = tokens.accent;
    } else if (clamped > 0) {
      color = tokens.warn;
    } else {
      color = tokens.textFaint;
    }
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: tokens.panel),
                  FractionallySizedBox(
                    widthFactor: clamped / 100,
                    child: Container(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${clamped.toInt()}%',
            textAlign: TextAlign.right,
            style: tokens.fontMono.copyWith(
              fontSize: 11.5,
              color: tokens.textMid,
            ),
          ),
        ),
      ],
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
        tooltip: TooltipStrings.projectsFilterExportOutdated,
      );
    }
    if (details.hasBeenExported) {
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
