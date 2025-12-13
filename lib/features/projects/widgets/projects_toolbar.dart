import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../providers/projects_screen_providers.dart';

/// Toolbar for Projects screen with search, filter, sort, and view mode controls.
///
/// Follows Fluent Design principles with hover states and smooth animations.
class ProjectsToolbar extends ConsumerStatefulWidget {
  const ProjectsToolbar({super.key});

  @override
  ConsumerState<ProjectsToolbar> createState() => _ProjectsToolbarState();
}

class _ProjectsToolbarState extends ConsumerState<ProjectsToolbar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Row(
          children: [
            // Search field
            Expanded(
              flex: 2,
              child: _buildSearchField(theme),
            ),
            const SizedBox(width: 12),
            // Sort dropdown
            _buildSortDropdown(theme),
          ],
        ),
        const SizedBox(height: 12),
        // Quick filter buttons
        _buildQuickFilters(theme),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search projects by name or mod ID...',
        prefixIcon: Icon(
          FluentIcons.search_24_regular,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        suffixIcon: _searchController.text.isNotEmpty
            ? Tooltip(
                message: TooltipStrings.clearSearch,
                waitDuration: const Duration(milliseconds: 500),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _updateSearch('');
                    },
                    child: Icon(
                      FluentIcons.dismiss_circle_24_regular,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: theme.colorScheme.primary,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        filled: true,
        fillColor: theme.colorScheme.surface,
      ),
      onChanged: _updateSearch,
    );
  }

  Widget _buildQuickFilters(ThemeData theme) {
    final currentFilter = ref.watch(
      projectsFilterProvider.select((s) => s.quickFilter),
    );

    return Row(
      children: [
        _QuickFilterButton(
          icon: FluentIcons.arrow_sync_24_regular,
          label: 'Needs Update',
          tooltip: TooltipStrings.projectsFilterNeedsUpdate,
          isSelected: currentFilter == ProjectQuickFilter.needsUpdate,
          onTap: () => _setQuickFilter(
            currentFilter == ProjectQuickFilter.needsUpdate
                ? ProjectQuickFilter.none
                : ProjectQuickFilter.needsUpdate,
          ),
        ),
        const SizedBox(width: 8),
        _QuickFilterButton(
          icon: FluentIcons.document_error_24_regular,
          label: 'Incomplete',
          tooltip: TooltipStrings.projectsFilterIncomplete,
          isSelected: currentFilter == ProjectQuickFilter.incomplete,
          onTap: () => _setQuickFilter(
            currentFilter == ProjectQuickFilter.incomplete
                ? ProjectQuickFilter.none
                : ProjectQuickFilter.incomplete,
          ),
        ),
        const SizedBox(width: 8),
        _QuickFilterButton(
          icon: FluentIcons.checkmark_circle_24_regular,
          label: 'Has Complete',
          tooltip: TooltipStrings.projectsFilterHasComplete,
          isSelected: currentFilter == ProjectQuickFilter.hasCompleteLanguage,
          onTap: () => _setQuickFilter(
            currentFilter == ProjectQuickFilter.hasCompleteLanguage
                ? ProjectQuickFilter.none
                : ProjectQuickFilter.hasCompleteLanguage,
          ),
        ),
        if (currentFilter != ProjectQuickFilter.none) ...[
          const SizedBox(width: 12),
          _buildClearFilterButton(theme),
        ],
      ],
    );
  }

  Widget _buildClearFilterButton(ThemeData theme) {
    return Tooltip(
      message: TooltipStrings.editorClearFilters,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _setQuickFilter(ProjectQuickFilter.none),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.dismiss_24_regular,
                  size: 14,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  'Clear',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setQuickFilter(ProjectQuickFilter filter) {
    ref.read(projectsFilterProvider.notifier).setQuickFilter(filter);
  }

  Widget _buildSortDropdown(ThemeData theme) {
    final sortBy = ref.watch(
      projectsFilterProvider.select((state) => state.sortBy),
    );

    return PopupMenuButton<ProjectSortOption>(
      offset: const Offset(0, 40),
      itemBuilder: (context) => ProjectSortOption.values
          .map((option) => PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    Icon(
                      _getSortIcon(option),
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 12),
                    Text(option.displayName),
                  ],
                ),
              ))
          .toList(),
      onSelected: (option) {
        ref.read(projectsFilterProvider.notifier).updateSort(option);
      },
      child: _FluentButton(
        icon: _getSortIcon(sortBy),
        label: sortBy.displayName,
        showDropdownIcon: true,
        onTap: null, // Handled by PopupMenuButton
      ),
    );
  }

  void _updateSearch(String query) {
    ref.read(projectsFilterProvider.notifier).updateSearchQuery(query);
  }

  IconData _getSortIcon(ProjectSortOption option) {
    switch (option) {
      case ProjectSortOption.name:
        return FluentIcons.text_sort_ascending_24_regular;
      case ProjectSortOption.dateModified:
        return FluentIcons.calendar_24_regular;
      case ProjectSortOption.progress:
        return FluentIcons.chart_multiple_24_regular;
    }
  }
}

/// Reusable Fluent Design button widget
class _FluentButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool showDropdownIcon;
  final int? badge;
  final VoidCallback? onTap;

  const _FluentButton({
    required this.icon,
    required this.label,
    // ignore: unused_element_parameter
    this.isPrimary = false,
    this.showDropdownIcon = false,
    this.badge,
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
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? (_isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : theme.colorScheme.primary)
                : (_isHovered
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(6),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isPrimary
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.isPrimary
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.badge}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              if (widget.showDropdownIcon) ...[
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.chevron_down_24_regular,
                  size: 16,
                  color: widget.isPrimary
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick filter toggle button with Fluent Design
class _QuickFilterButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickFilterButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_QuickFilterButton> createState() => _QuickFilterButtonState();
}

class _QuickFilterButtonState extends State<_QuickFilterButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? theme.colorScheme.primary
                  : (_isHovered
                      ? theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.7)
                      : theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.w500,
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
