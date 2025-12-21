import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';

/// Toolbar for mods screen with search, filters, and actions
class ModsToolbar extends StatefulWidget {
  final String searchQuery;
  final Function(String) onSearchChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final int totalMods;
  final int filteredMods;
  final ModsFilter currentFilter;
  final Function(ModsFilter) onFilterChanged;
  final int notImportedCount;
  final int needsUpdateCount;
  final bool showHidden;
  final Function(bool) onShowHiddenChanged;
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
  State<ModsToolbar> createState() => _ModsToolbarState();
}

class _ModsToolbarState extends State<ModsToolbar> {
  late TextEditingController _searchController;
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Search box
          Expanded(
            flex: 2,
            child: _buildSearchField(theme),
          ),
          const SizedBox(width: 16),

          // Filter chips
          _buildFilterChips(theme),
          const SizedBox(width: 16),

          // Hidden mods checkbox
          _buildHiddenCheckbox(theme),
          const SizedBox(width: 16),

          // Projects with pending changes badge
          if (widget.projectsWithPendingChanges > 0)
            _buildPendingProjectsBadge(theme),
          if (widget.projectsWithPendingChanges > 0)
            const SizedBox(width: 16),

          // Mod count
          _buildModCount(theme),
          const SizedBox(width: 16),

          // Import local pack button
          if (widget.onImportLocalPack != null) ...[
            _ToolbarButton(
              icon: FluentIcons.folder_add_24_regular,
              tooltip: TooltipStrings.modsImportLocalPack,
              onTap: widget.onImportLocalPack!,
            ),
            const SizedBox(width: 8),
          ],

          // Refresh button
          _ToolbarButton(
            icon: FluentIcons.arrow_sync_24_regular,
            tooltip: TooltipStrings.modsRefresh,
            onTap: widget.onRefresh,
            isLoading: widget.isRefreshing,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingProjectsBadge(ThemeData theme) {
    return Tooltip(
      message: 'Projects with pending translation changes. Click to view.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onNavigateToProjects,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.warning_24_filled,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.projectsWithPendingChanges} project${widget.projectsWithPendingChanges > 1 ? 's' : ''} pending',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.arrow_right_24_regular,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterChip(
          label: 'All',
          tooltip: TooltipStrings.modsFilterAll,
          isSelected: widget.currentFilter == ModsFilter.all,
          onTap: () => widget.onFilterChanged(ModsFilter.all),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Not imported',
          tooltip: TooltipStrings.modsFilterNotImported,
          count: widget.notImportedCount,
          isSelected: widget.currentFilter == ModsFilter.notImported,
          onTap: () => widget.onFilterChanged(ModsFilter.notImported),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: 'Needs update',
          tooltip: TooltipStrings.modsFilterNeedsUpdate,
          count: widget.needsUpdateCount,
          isSelected: widget.currentFilter == ModsFilter.needsUpdate,
          onTap: () => widget.onFilterChanged(ModsFilter.needsUpdate),
          highlightCount: widget.needsUpdateCount > 0,
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Focus(
      onFocusChange: (focused) {
        setState(() => _searchFocused = focused);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _searchFocused
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: _searchFocused ? 2 : 1,
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: widget.onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search mods by name, ID, or author...',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            prefixIcon: Icon(
              FluentIcons.search_24_regular,
              color: _searchFocused
                  ? theme.colorScheme.primary
                  : theme.textTheme.bodySmall?.color,
            ),
            suffixIcon: widget.searchQuery.isNotEmpty
                ? Tooltip(
                    message: TooltipStrings.clearSearch,
                    waitDuration: const Duration(milliseconds: 500),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          widget.onSearchChanged('');
                        },
                        child: Icon(
                          FluentIcons.dismiss_circle_24_filled,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildHiddenCheckbox(ThemeData theme) {
    return Tooltip(
      message: TooltipStrings.modsHiddenToggle,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onShowHiddenChanged(!widget.showHidden),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.showHidden
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.showHidden
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.showHidden
                    ? FluentIcons.eye_24_filled
                    : FluentIcons.eye_off_24_regular,
                size: 16,
                color: widget.showHidden
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Hidden',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.showHidden
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: widget.showHidden ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (widget.hiddenCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.showHidden
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.hiddenCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.showHidden
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
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

  Widget _buildModCount(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.cube_24_regular,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            widget.searchQuery.isNotEmpty
                ? '${widget.filteredMods} / ${widget.totalMods} mods'
                : '${widget.totalMods} mods',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Toolbar button with Fluent Design interactions
class _ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isLoading;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    // ignore: unused_element_parameter
    this.isPrimary = false,
    this.isLoading = false,
  });

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.isLoading ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isPrimary
                  ? (_isPressed
                      ? theme.colorScheme.primary.withValues(alpha: 0.8)
                      : _isHovered
                          ? theme.colorScheme.primary.withValues(alpha: 0.9)
                          : theme.colorScheme.primary)
                  : (_isPressed
                      ? theme.colorScheme.surfaceContainerHighest
                      : _isHovered
                          ? theme.colorScheme.surfaceContainerHigh
                          : theme.colorScheme.surfaceContainer),
              borderRadius: BorderRadius.circular(8),
              border: widget.isPrimary
                  ? null
                  : Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: widget.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: 20,
                    color: widget.isPrimary
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Filter chip with Fluent Design interactions
class _FilterChip extends StatefulWidget {
  final String label;
  final String? tooltip;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;
  final bool highlightCount;

  const _FilterChip({
    required this.label,
    this.tooltip,
    this.count,
    required this.isSelected,
    required this.onTap,
    this.highlightCount = false,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget chip = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.colorScheme.primary
                : _isHovered
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (widget.count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.2)
                        : widget.highlightCount && widget.count! > 0
                            ? theme.colorScheme.error.withValues(alpha: 0.15)
                            : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.isSelected
                          ? theme.colorScheme.onPrimary
                          : widget.highlightCount && widget.count! > 0
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: chip,
      );
    }

    return chip;
  }
}
