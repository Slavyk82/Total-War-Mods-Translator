import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/projects_screen_providers.dart';
import '../../../models/domain/project.dart';

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
            // Filter button
            _buildFilterButton(theme),
            const SizedBox(width: 8),
            // Sort dropdown
            _buildSortDropdown(theme),
            const SizedBox(width: 8),
            // View mode toggle
            _buildViewModeToggle(theme),
          ],
        ),
        const SizedBox(height: 12),
        // Active filters chips
        _buildActiveFilters(theme),
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
            ? MouseRegion(
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

  Widget _buildFilterButton(ThemeData theme) {
    final filter = ref.watch(projectsFilterProvider);
    final hasActiveFilters = filter.statusFilters.isNotEmpty ||
        filter.gameFilters.isNotEmpty ||
        filter.languageFilters.isNotEmpty ||
        filter.showOnlyWithUpdates;

    return _FluentButton(
      icon: FluentIcons.filter_24_regular,
      label: 'Filter',
      badge: hasActiveFilters ? _getActiveFilterCount(filter) : null,
      onTap: () => _showFilterDialog(),
    );
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

  Widget _buildViewModeToggle(ThemeData theme) {
    final viewMode = ref.watch(
      projectsFilterProvider.select((state) => state.viewMode),
    );

    return Row(
      children: [
        _ViewModeButton(
          icon: FluentIcons.grid_24_regular,
          isSelected: viewMode == ProjectViewMode.grid,
          onTap: () {
            ref.read(projectsFilterProvider.notifier).updateViewMode(ProjectViewMode.grid);
          },
        ),
        const SizedBox(width: 4),
        _ViewModeButton(
          icon: FluentIcons.list_24_regular,
          isSelected: viewMode == ProjectViewMode.list,
          onTap: () {
            ref.read(projectsFilterProvider.notifier).updateViewMode(ProjectViewMode.list);
          },
        ),
      ],
    );
  }

  Widget _buildActiveFilters(ThemeData theme) {
    final filter = ref.watch(projectsFilterProvider);
    final chips = <Widget>[];

    // Status filters
    for (final status in filter.statusFilters) {
      chips.add(_buildFilterChip(
        theme,
        status.name.toUpperCase(),
        () => _removeStatusFilter(status),
      ));
    }

    // Updates filter
    if (filter.showOnlyWithUpdates) {
      chips.add(_buildFilterChip(
        theme,
        'HAS UPDATES',
        () => _toggleUpdatesFilter(false),
      ));
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...chips,
        _buildClearAllButton(theme),
      ],
    );
  }

  Widget _buildFilterChip(ThemeData theme, String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onRemove,
              child: Icon(
                FluentIcons.dismiss_24_regular,
                size: 14,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClearAllButton(ThemeData theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _clearAllFilters,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Clear all',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  void _updateSearch(String query) {
    ref.read(projectsFilterProvider.notifier).updateSearchQuery(query);
  }

  void _removeStatusFilter(ProjectStatus status) {
    final current = ref.read(projectsFilterProvider);
    final newFilters = Set<ProjectStatus>.from(current.statusFilters)
      ..remove(status);
    ref.read(projectsFilterProvider.notifier).updateFilters(
      statusFilters: newFilters,
    );
  }

  void _toggleUpdatesFilter(bool value) {
    ref.read(projectsFilterProvider.notifier).updateFilters(
      showOnlyWithUpdates: value,
    );
  }

  void _clearAllFilters() {
    ref.read(projectsFilterProvider.notifier).clearFilters();
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => const _FilterDialog(),
    );
  }

  int _getActiveFilterCount(ProjectsFilterState filter) {
    return filter.statusFilters.length +
        filter.gameFilters.length +
        filter.languageFilters.length +
        (filter.showOnlyWithUpdates ? 1 : 0);
  }

  IconData _getSortIcon(ProjectSortOption option) {
    switch (option) {
      case ProjectSortOption.name:
        return FluentIcons.text_sort_ascending_24_regular;
      case ProjectSortOption.dateModified:
        return FluentIcons.calendar_24_regular;
      case ProjectSortOption.progress:
        return FluentIcons.chart_multiple_24_regular;
      case ProjectSortOption.status:
        return FluentIcons.tag_24_regular;
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

/// View mode toggle button
class _ViewModeButton extends StatefulWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ViewModeButton> createState() => _ViewModeButtonState();
}

class _ViewModeButtonState extends State<_ViewModeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.colorScheme.primaryContainer
                : (_isHovered
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: widget.isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Filter dialog for advanced filtering options
class _FilterDialog extends ConsumerWidget {
  const _FilterDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(projectsFilterProvider);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    FluentIcons.filter_24_regular,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Filter Projects',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        FluentIcons.dismiss_24_regular,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Status filters
              Text(
                'Status',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ProjectStatus.values.map((status) {
                  final isSelected = filter.statusFilters.contains(status);
                  return _FilterCheckbox(
                    label: status.name.toUpperCase(),
                    isSelected: isSelected,
                    onChanged: (value) => _toggleStatusFilter(ref, status),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              // Updates filter
              _FilterCheckbox(
                label: 'Show only projects with updates',
                isSelected: filter.showOnlyWithUpdates,
                onChanged: (value) {
                  ref.read(projectsFilterProvider.notifier).updateFilters(
                    showOnlyWithUpdates: value,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleStatusFilter(WidgetRef ref, ProjectStatus status) {
    final current = ref.read(projectsFilterProvider);
    final newFilters = Set<ProjectStatus>.from(current.statusFilters);

    if (newFilters.contains(status)) {
      newFilters.remove(status);
    } else {
      newFilters.add(status);
    }

    ref.read(projectsFilterProvider.notifier).updateFilters(
      statusFilters: newFilters,
    );
  }
}

/// Custom checkbox for filters
class _FilterCheckbox extends StatefulWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool> onChanged;

  const _FilterCheckbox({
    required this.label,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  State<_FilterCheckbox> createState() => _FilterCheckboxState();
}

class _FilterCheckboxState extends State<_FilterCheckbox> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.isSelected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.colorScheme.primaryContainer
                : (_isHovered
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isSelected
                    ? FluentIcons.checkmark_square_24_filled
                    : FluentIcons.square_24_regular,
                size: 18,
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
