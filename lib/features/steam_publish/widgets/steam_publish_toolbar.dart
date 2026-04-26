import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../providers/steam_publish_providers.dart';

/// Toolbar for the Steam Publish screen.
///
/// Row 1 hosts the trailing actions (search, select all, deselect all,
/// publish, refresh, settings). Row 2 hosts the STATE filter pill group.
/// The screen title (icon + name + counts) is rendered higher up by
/// `HomeBackToolbar`.
class SteamPublishToolbar extends StatelessWidget {
  final int totalItems;
  final int outdatedCount;
  final int noPackCount;
  final int compilationsCount;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final SteamPublishDisplayFilter currentFilter;
  final ValueChanged<SteamPublishDisplayFilter> onFilterChanged;
  final VoidCallback onSelectAll;
  final bool allSelected;
  final VoidCallback? onDeselectAll;
  final VoidCallback? onPublishSelection;
  final String? publishDisabledTooltip;
  final int selectedCount;
  final int publishableSelectedCount;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  const SteamPublishToolbar({
    super.key,
    required this.totalItems,
    required this.outdatedCount,
    required this.noPackCount,
    required this.compilationsCount,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.onSelectAll,
    required this.allSelected,
    required this.onDeselectAll,
    required this.onPublishSelection,
    required this.publishDisabledTooltip,
    required this.selectedCount,
    required this.publishableSelectedCount,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return FilterToolbar(
      leading: const SizedBox.shrink(),
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
          hintText: t.steamPublish.toolbar.searchHint,
          onChanged: onSearchChanged,
          onClear: () => onSearchChanged(''),
        ),
      ),
      SmallTextButton(
        label: t.steamPublish.toolbar.selectAll,
        icon: FluentIcons.checkbox_checked_24_regular,
        tooltip: totalItems == 0
            ? t.steamPublish.toolbar.tooltips.noItemsToSelect
            : (allSelected
                ? t.steamPublish.toolbar.tooltips.allAlreadySelected
                : t.steamPublish.toolbar.tooltips.selectAllListed),
        onTap: (totalItems > 0 && !allSelected) ? onSelectAll : null,
      ),
      SmallTextButton(
        label: t.steamPublish.toolbar.deselectAll,
        icon: FluentIcons.checkbox_unchecked_24_regular,
        tooltip: selectedCount == 0
            ? t.steamPublish.toolbar.tooltips.noItemsSelected
            : t.steamPublish.toolbar.tooltips.clearSelection,
        onTap: onDeselectAll,
      ),
      _PublishSelectionButton(
        publishableCount: publishableSelectedCount,
        selectedCount: selectedCount,
        disabledTooltip: publishDisabledTooltip,
        onPublish: onPublishSelection,
      ),
      SmallTextButton(
        label: t.steamPublish.toolbar.refresh,
        icon: FluentIcons.arrow_sync_24_regular,
        tooltip: t.steamPublish.toolbar.refresh,
        onTap: onRefresh,
      ),
      SmallTextButton(
        label: t.steamPublish.toolbar.workshopTemplate,
        icon: FluentIcons.settings_24_regular,
        tooltip: t.steamPublish.toolbar.tooltips.configureTemplates,
        onTap: onOpenSettings,
      ),
    ];
  }

  FilterPillGroup _buildStateGroup() {
    return FilterPillGroup(
      label: 'STATE',
      pills: [
        FilterPill(
          label: t.steamPublish.toolbar.filters.all,
          selected: currentFilter == SteamPublishDisplayFilter.all,
          tooltip: 'Show every publishable item',
          onToggle: () => onFilterChanged(SteamPublishDisplayFilter.all),
        ),
        FilterPill(
          label: t.steamPublish.toolbar.filters.outdated,
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
          label: t.steamPublish.toolbar.filters.noPack,
          selected: currentFilter == SteamPublishDisplayFilter.noPackGenerated,
          count: noPackCount,
          tooltip: 'Show only items without a generated pack file',
          onToggle: () => onFilterChanged(
            currentFilter == SteamPublishDisplayFilter.noPackGenerated
                ? SteamPublishDisplayFilter.all
                : SteamPublishDisplayFilter.noPackGenerated,
          ),
        ),
        FilterPill(
          label: t.steamPublish.toolbar.filters.compilations,
          selected: currentFilter == SteamPublishDisplayFilter.compilations,
          count: compilationsCount,
          tooltip: 'Show only pack compilations',
          onToggle: () => onFilterChanged(
            currentFilter == SteamPublishDisplayFilter.compilations
                ? SteamPublishDisplayFilter.all
                : SteamPublishDisplayFilter.compilations,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Leading (icon + title + count / selection)
//
// Public so [SteamPublishScreen] can mount it inside `HomeBackToolbar.leading`.
// =============================================================================

class SteamPublishToolbarLeading extends StatelessWidget {
  final int totalItems;
  final int filteredItems;
  final int selectedCount;
  final bool searchActive;
  final int subsTotal;

  const SteamPublishToolbarLeading({
    super.key,
    required this.totalItems,
    required this.filteredItems,
    required this.selectedCount,
    required this.searchActive,
    this.subsTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    final packLabel = totalItems == 1
        ? t.steamPublish.toolbar.counts.pack
        : t.steamPublish.toolbar.counts.packs;
    final base = searchActive
        ? '$filteredItems / $totalItems $packLabel'
        : '$totalItems $packLabel';
    final selectedSegment =
        selectedCount > 0 ? ' · $selectedCount selected' : '';
    final subsSegment = subsTotal > 0
        ? ' · ${NumberFormat('#,###', 'en_US').format(subsTotal).replaceAll(',', ' ')} subs'
        : '';
    return ListToolbarLeading(
      icon: FluentIcons.cloud_arrow_up_24_regular,
      title: t.steamPublish.screen.title,
      countLabel: '$base$selectedSegment$subsSegment',
    );
  }
}

// =============================================================================
// Trailing widgets
// =============================================================================

class _PublishSelectionButton extends StatelessWidget {
  final int publishableCount;
  final int selectedCount;
  final String? disabledTooltip;
  final VoidCallback? onPublish;

  const _PublishSelectionButton({
    required this.publishableCount,
    required this.selectedCount,
    required this.disabledTooltip,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPublish != null && publishableCount > 0;
    final baseLabel = t.steamPublish.toolbar.publish;
    final label = publishableCount > 0
        ? t.steamPublish.toolbar.publishWithCount(count: publishableCount)
        : baseLabel;
    final String tooltip;
    if (selectedCount == 0) {
      tooltip = t.steamPublish.toolbar.tooltips.selectAtLeastOne;
    } else if (publishableCount == 0) {
      tooltip = disabledTooltip != null && disabledTooltip!.isNotEmpty
          ? disabledTooltip!
          : t.steamPublish.toolbar.tooltips.noPackOrWorkshopId;
    } else if (publishableCount < selectedCount) {
      final skipped = selectedCount - publishableCount;
      tooltip = t.steamPublish.toolbar.tooltips
          .publishSkipped(count: publishableCount, skipped: skipped);
    } else {
      tooltip = t.steamPublish.toolbar.tooltips.publishSelected;
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

