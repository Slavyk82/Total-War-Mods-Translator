import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Toolbar for the Mods screen.
///
/// Composed on top of the shared [FilterToolbar] primitive introduced in
/// Plan 5a. Row 1 hosts a title, mod count and the primary actions (search,
/// hidden toggle, import local pack, refresh). Row 2 hosts the STATE filter
/// pill group.
class ModsToolbar extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final int totalMods;
  final int filteredMods;
  final ModsFilter currentFilter;
  final ValueChanged<ModsFilter> onFilterChanged;
  final int notImportedCount;
  final int needsUpdateCount;
  final bool showHidden;
  final ValueChanged<bool> onShowHiddenChanged;
  final int hiddenCount;
  final int projectsWithPendingChanges;
  final VoidCallback? onNavigateToProjects;
  final VoidCallback? onImportLocalPack;

  const ModsToolbar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onRefresh,
    this.isRefreshing = false,
    required this.totalMods,
    required this.filteredMods,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.notImportedCount,
    required this.needsUpdateCount,
    required this.showHidden,
    required this.onShowHiddenChanged,
    required this.hiddenCount,
    this.projectsWithPendingChanges = 0,
    this.onNavigateToProjects,
    this.onImportLocalPack,
  });

  @override
  Widget build(BuildContext context) {
    return FilterToolbar(
      leading: _Leading(
        totalMods: totalMods,
        filteredMods: filteredMods,
        searchActive: searchQuery.isNotEmpty,
        projectsWithPendingChanges: projectsWithPendingChanges,
        onNavigateToProjects: onNavigateToProjects,
      ),
      expandLeading: false,
      trailing: _buildTrailing(context),
      pillGroups: [_buildStateGroup()],
    );
  }

  List<Widget> _buildTrailing(BuildContext context) {
    return [
      Expanded(
        child: ListSearchField(
          width: null,
          value: searchQuery,
          hintText: 'Search mods...',
          onChanged: onSearchChanged,
          onClear: () => onSearchChanged(''),
        ),
      ),
      if (onImportLocalPack != null)
        SmallTextButton(
          label: 'Import pack',
          icon: FluentIcons.folder_add_24_regular,
          tooltip: TooltipStrings.modsImportLocalPack,
          onTap: onImportLocalPack,
        ),
      _RefreshButton(
        isRefreshing: isRefreshing,
        onTap: onRefresh,
      ),
    ];
  }

  FilterPillGroup _buildStateGroup() {
    final isAll = currentFilter == ModsFilter.all;
    return FilterPillGroup(
      label: 'STATE',
      pills: [
        FilterPill(
          label: 'All',
          selected: isAll,
          tooltip: TooltipStrings.modsFilterAll,
          onToggle: () => onFilterChanged(ModsFilter.all),
        ),
        FilterPill(
          label: 'Not imported',
          selected: currentFilter == ModsFilter.notImported,
          count: notImportedCount,
          tooltip: TooltipStrings.modsFilterNotImported,
          onToggle: () => onFilterChanged(
            currentFilter == ModsFilter.notImported
                ? ModsFilter.all
                : ModsFilter.notImported,
          ),
        ),
        FilterPill(
          label: 'Needs update',
          selected: currentFilter == ModsFilter.needsUpdate,
          count: needsUpdateCount,
          tooltip: TooltipStrings.modsFilterNeedsUpdate,
          onToggle: () => onFilterChanged(
            currentFilter == ModsFilter.needsUpdate
                ? ModsFilter.all
                : ModsFilter.needsUpdate,
          ),
        ),
        FilterPill(
          label: 'Hidden',
          selected: showHidden,
          count: hiddenCount > 0 ? hiddenCount : null,
          tooltip: TooltipStrings.modsHiddenToggle,
          onToggle: () => onShowHiddenChanged(!showHidden),
        ),
      ],
    );
  }
}

// =============================================================================
// Leading (title + count + pending-projects banner)
// =============================================================================

class _Leading extends StatelessWidget {
  final int totalMods;
  final int filteredMods;
  final bool searchActive;
  final int projectsWithPendingChanges;
  final VoidCallback? onNavigateToProjects;

  const _Leading({
    required this.totalMods,
    required this.filteredMods,
    required this.searchActive,
    required this.projectsWithPendingChanges,
    required this.onNavigateToProjects,
  });

  @override
  Widget build(BuildContext context) {
    final countLabel = searchActive
        ? '$filteredMods / $totalMods ${totalMods == 1 ? 'mod' : 'mods'}'
        : '$totalMods ${totalMods == 1 ? 'mod' : 'mods'}';
    return ListToolbarLeading(
      icon: FluentIcons.cube_24_regular,
      title: 'Mods',
      countLabel: countLabel,
      trailing: [
        if (projectsWithPendingChanges > 0)
          _PendingProjectsBanner(
            count: projectsWithPendingChanges,
            onTap: onNavigateToProjects,
          ),
      ],
    );
  }
}

class _PendingProjectsBanner extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _PendingProjectsBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StatusPill(
      label: '$count project${count > 1 ? 's' : ''} pending',
      foreground: tokens.err,
      background: tokens.errBg,
      icon: FluentIcons.warning_24_filled,
      tooltip: 'Projects with pending translation changes. Click to view.',
      onTap: onTap,
    );
  }
}

// =============================================================================
// Trailing widgets
// =============================================================================

class _RefreshButton extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback onTap;
  const _RefreshButton({required this.isRefreshing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: TooltipStrings.modsRefresh,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: isRefreshing
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: isRefreshing ? null : onTap,
          child: Container(
            height: 32,
            width: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: isRefreshing
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                : Icon(
                    FluentIcons.arrow_sync_24_regular,
                    size: 16,
                    color: tokens.textMid,
                  ),
          ),
        ),
      ),
    );
  }
}
