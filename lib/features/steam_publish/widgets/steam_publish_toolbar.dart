import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../providers/steam_publish_providers.dart';

/// Toolbar for the Steam Publish screen.
///
/// Row 1 hosts title + count/selection, plus trailing actions (select all,
/// select outdated, search, publish, refresh, settings).
/// Row 2 hosts the STATE filter pill group.
class SteamPublishToolbar extends StatelessWidget {
  final int totalItems;
  final int filteredItems;
  final int selectedCount;
  final int outdatedCount;
  final int noPackCount;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final SteamPublishDisplayFilter currentFilter;
  final ValueChanged<SteamPublishDisplayFilter> onFilterChanged;
  final VoidCallback onSelectAll;
  final VoidCallback? onSelectOutdated;
  final VoidCallback? onPublishSelection;
  final String? publishDisabledTooltip;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  const SteamPublishToolbar({
    super.key,
    required this.totalItems,
    required this.filteredItems,
    required this.selectedCount,
    required this.outdatedCount,
    required this.noPackCount,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.onSelectAll,
    required this.onSelectOutdated,
    required this.onPublishSelection,
    required this.publishDisabledTooltip,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return FilterToolbar(
      leading: _Leading(
        totalItems: totalItems,
        filteredItems: filteredItems,
        selectedCount: selectedCount,
        searchActive: searchQuery.isNotEmpty,
      ),
      trailing: _buildTrailing(context),
      pillGroups: [_buildStateGroup()],
    );
  }

  List<Widget> _buildTrailing(BuildContext context) {
    return [
      SmallTextButton(
        label: 'Select all',
        icon: FluentIcons.checkbox_checked_24_regular,
        tooltip: totalItems == 0
            ? 'No items to select'
            : 'Select every item currently listed',
        onTap: totalItems > 0 ? onSelectAll : null,
      ),
      SmallTextButton(
        label: outdatedCount > 0
            ? 'Select outdated ($outdatedCount)'
            : 'Select outdated',
        icon: FluentIcons.warning_24_regular,
        tooltip: outdatedCount > 0
            ? 'Select every item whose pack is newer than its last publish'
            : 'No outdated items to select',
        onTap: onSelectOutdated,
      ),
      ListSearchField(
        value: searchQuery,
        hintText: 'Search packs...',
        onChanged: onSearchChanged,
        onClear: () => onSearchChanged(''),
      ),
      _PublishSelectionButton(
        selectedCount: selectedCount,
        disabledTooltip: publishDisabledTooltip,
        onPublish: onPublishSelection,
      ),
      SmallIconButton(
        icon: FluentIcons.arrow_sync_24_regular,
        tooltip: 'Refresh',
        onTap: onRefresh,
        size: 32,
        iconSize: 16,
      ),
      SmallIconButton(
        icon: FluentIcons.settings_24_regular,
        tooltip: 'Publish settings',
        onTap: onOpenSettings,
        size: 32,
        iconSize: 16,
      ),
    ];
  }

  FilterPillGroup _buildStateGroup() {
    return FilterPillGroup(
      label: 'STATE',
      pills: [
        FilterPill(
          label: 'All',
          selected: currentFilter == SteamPublishDisplayFilter.all,
          tooltip: 'Show every publishable item',
          onToggle: () => onFilterChanged(SteamPublishDisplayFilter.all),
        ),
        FilterPill(
          label: 'Outdated',
          selected: currentFilter == SteamPublishDisplayFilter.outdated,
          count: outdatedCount,
          tooltip:
              'Show only items whose pack was exported after their last Workshop publish',
          onToggle: () => onFilterChanged(
            currentFilter == SteamPublishDisplayFilter.outdated
                ? SteamPublishDisplayFilter.all
                : SteamPublishDisplayFilter.outdated,
          ),
        ),
        FilterPill(
          label: 'No pack',
          selected: currentFilter == SteamPublishDisplayFilter.noPackGenerated,
          count: noPackCount,
          tooltip: 'Show only items without a generated pack file',
          onToggle: () => onFilterChanged(
            currentFilter == SteamPublishDisplayFilter.noPackGenerated
                ? SteamPublishDisplayFilter.all
                : SteamPublishDisplayFilter.noPackGenerated,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Leading (crumb + title + count / selection)
// =============================================================================

class _Leading extends StatelessWidget {
  final int totalItems;
  final int filteredItems;
  final int selectedCount;
  final bool searchActive;

  const _Leading({
    required this.totalItems,
    required this.filteredItems,
    required this.selectedCount,
    required this.searchActive,
  });

  @override
  Widget build(BuildContext context) {
    final packLabel = totalItems == 1 ? 'pack' : 'packs';
    final base = searchActive
        ? '$filteredItems / $totalItems $packLabel'
        : '$totalItems $packLabel';
    final countLabel =
        selectedCount > 0 ? '$base · $selectedCount selected' : base;
    return ListToolbarLeading(
      icon: FluentIcons.cloud_arrow_up_24_regular,
      title: 'Publish on Steam',
      countLabel: countLabel,
    );
  }
}

// =============================================================================
// Trailing widgets
// =============================================================================

class _PublishSelectionButton extends StatelessWidget {
  final int selectedCount;
  final String? disabledTooltip;
  final VoidCallback? onPublish;

  const _PublishSelectionButton({
    required this.selectedCount,
    required this.disabledTooltip,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPublish != null && selectedCount > 0;
    final label = selectedCount > 0 ? 'Publish ($selectedCount)' : 'Publish';
    final String tooltip;
    if (selectedCount == 0) {
      tooltip = 'Select at least one item to publish';
    } else if (disabledTooltip != null && disabledTooltip!.isNotEmpty) {
      tooltip = disabledTooltip!;
    } else {
      tooltip = 'Publish selected items to Steam Workshop';
    }
    final core = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPublish : null,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? tokens.accent : tokens.panel2,
            border: Border.all(
              color: enabled ? tokens.accent : tokens.border,
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.cloud_arrow_up_24_regular,
                size: 14,
                color: enabled ? tokens.accentFg : tokens.textDim,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: enabled ? tokens.accentFg : tokens.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: core,
    );
  }
}

