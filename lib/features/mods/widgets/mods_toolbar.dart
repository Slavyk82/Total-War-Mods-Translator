import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

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
      trailing: _buildTrailing(context),
      pillGroups: [_buildStateGroup()],
    );
  }

  List<Widget> _buildTrailing(BuildContext context) {
    return [
      ListSearchField(
        value: searchQuery,
        hintText: 'Search mods...',
        onChanged: onSearchChanged,
        onClear: () => onSearchChanged(''),
      ),
      _HiddenToggle(
        showHidden: showHidden,
        hiddenCount: hiddenCount,
        onChanged: onShowHiddenChanged,
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
    final tokens = context.tokens;
    final countLabel = searchActive
        ? '$filteredMods / $totalMods ${totalMods == 1 ? 'mod' : 'mods'}'
        : '$totalMods ${totalMods == 1 ? 'mod' : 'mods'}';
    return Row(
      children: [
        Icon(
          FluentIcons.cube_24_regular,
          size: 20,
          color: tokens.textMid,
        ),
        const SizedBox(width: 10),
        Text(
          'Mods',
          style: tokens.fontDisplay.copyWith(
            fontSize: 20,
            color: tokens.text,
            fontStyle: tokens.fontDisplayItalic
                ? FontStyle.italic
                : FontStyle.normal,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          countLabel,
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.textDim,
          ),
        ),
        if (projectsWithPendingChanges > 0) ...[
          const SizedBox(width: 16),
          _PendingProjectsBanner(
            count: projectsWithPendingChanges,
            onTap: onNavigateToProjects,
          ),
        ],
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
    return Tooltip(
      message: 'Projects with pending translation changes. Click to view.',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor:
            onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: tokens.errBg,
              borderRadius: BorderRadius.circular(tokens.radiusPill),
              border: Border.all(color: tokens.err.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.warning_24_filled,
                  size: 14,
                  color: tokens.err,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count project${count > 1 ? 's' : ''} pending',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.err,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.arrow_right_24_regular,
                  size: 12,
                  color: tokens.err,
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
// Trailing widgets
// =============================================================================

class _HiddenToggle extends StatelessWidget {
  final bool showHidden;
  final int hiddenCount;
  final ValueChanged<bool> onChanged;
  const _HiddenToggle({
    required this.showHidden,
    required this.hiddenCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = showHidden ? tokens.accent : tokens.textMid;
    final bg = showHidden ? tokens.accentBg : tokens.panel2;
    final borderColor = showHidden ? tokens.accent : tokens.border;
    return Tooltip(
      message: TooltipStrings.modsHiddenToggle,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!showHidden),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  showHidden
                      ? FluentIcons.eye_24_filled
                      : FluentIcons.eye_off_24_regular,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Text(
                  'Hidden',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hiddenCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$hiddenCount',
                    style: tokens.fontMono.copyWith(
                      fontSize: 11,
                      color: tokens.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
