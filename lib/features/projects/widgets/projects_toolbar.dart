import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/models/domain/language.dart';
import '../providers/projects_screen_providers.dart';

/// Toolbar for Projects screen with search, filter, sort, and view mode controls.
///
/// Follows Fluent Design principles with hover states and smooth animations.
class ProjectsToolbar extends ConsumerStatefulWidget {
  final List<Language> languages;
  final List<String> allProjectIds;
  final VoidCallback? onExportSelected;

  const ProjectsToolbar({
    super.key,
    this.languages = const [],
    this.allProjectIds = const [],
    this.onExportSelected,
  });

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
    final selectionState = ref.watch(batchProjectSelectionProvider);

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
            // Selection mode toggle button
            _buildSelectionModeButton(theme, selectionState),
            const SizedBox(width: 12),
            // Sort dropdown
            _buildSortDropdown(theme),
          ],
        ),
        const SizedBox(height: 12),
        // Selection mode controls or quick filters
        if (selectionState.isSelectionMode)
          _buildSelectionModeControls(theme, selectionState)
        else
          _buildQuickFilters(theme),
      ],
    );
  }

  Widget _buildSelectionModeButton(ThemeData theme, BatchProjectSelectionState selectionState) {
    return Tooltip(
      message: selectionState.isSelectionMode
          ? 'Exit selection mode'
          : 'Select multiple projects for batch export',
      waitDuration: const Duration(milliseconds: 500),
      child: _FluentButton(
        icon: selectionState.isSelectionMode
            ? FluentIcons.checkbox_indeterminate_24_regular
            : FluentIcons.checkbox_unchecked_24_regular,
        label: 'Selection',
        isActive: selectionState.isSelectionMode,
        onTap: () {
          final notifier = ref.read(batchProjectSelectionProvider.notifier);
          if (selectionState.isSelectionMode) {
            notifier.exitSelectionMode();
          } else {
            notifier.enterSelectionMode();
          }
        },
      ),
    );
  }

  Widget _buildSelectionModeControls(ThemeData theme, BatchProjectSelectionState selectionState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Selection count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${selectionState.selectedCount} selected',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Select all button
          _SmallActionButton(
            icon: FluentIcons.checkbox_checked_24_regular,
            label: 'All',
            tooltip: 'Select all projects',
            onTap: () {
              ref.read(batchProjectSelectionProvider.notifier).selectAll(widget.allProjectIds);
            },
          ),
          const SizedBox(width: 8),
          // Deselect all button
          _SmallActionButton(
            icon: FluentIcons.checkbox_unchecked_24_regular,
            label: 'None',
            tooltip: 'Deselect all projects',
            onTap: () {
              ref.read(batchProjectSelectionProvider.notifier).deselectAll();
            },
          ),
          const Spacer(),
          // Language dropdown
          _buildLanguageDropdown(theme, selectionState),
          const SizedBox(width: 12),
          // Export button
          _buildExportButton(theme, selectionState),
          const SizedBox(width: 8),
          // Cancel button
          _SmallActionButton(
            icon: FluentIcons.dismiss_24_regular,
            label: 'Cancel',
            tooltip: 'Exit selection mode',
            onTap: () {
              ref.read(batchProjectSelectionProvider.notifier).exitSelectionMode();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageDropdown(ThemeData theme, BatchProjectSelectionState selectionState) {
    final selectedLanguage = widget.languages.cast<Language?>().firstWhere(
      (l) => l?.id == selectionState.selectedLanguageId,
      orElse: () => null,
    );

    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      enabled: widget.languages.isNotEmpty,
      itemBuilder: (context) => widget.languages
          .map((lang) => PopupMenuItem(
                value: lang.id,
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.translate_24_regular,
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 12),
                    Text(lang.name),
                  ],
                ),
              ))
          .toList(),
      onSelected: (languageId) {
        ref.read(batchProjectSelectionProvider.notifier).setLanguage(languageId);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selectionState.selectedLanguageId != null
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selectionState.selectedLanguageId != null
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.translate_24_regular,
              size: 16,
              color: selectionState.selectedLanguageId != null
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Text(
              selectedLanguage?.name ?? 'Select language',
              style: theme.textTheme.bodySmall?.copyWith(
                color: selectionState.selectedLanguageId != null
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              FluentIcons.chevron_down_24_regular,
              size: 14,
              color: selectionState.selectedLanguageId != null
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton(ThemeData theme, BatchProjectSelectionState selectionState) {
    final canExport = selectionState.canExport;

    return Tooltip(
      message: !canExport
          ? selectionState.selectedProjectIds.isEmpty
              ? 'Select at least one project'
              : 'Select a target language'
          : 'Export selected projects as .pack files',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: canExport ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: canExport ? widget.onExportSelected : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: canExport
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.arrow_export_24_regular,
                  size: 16,
                  color: canExport
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Text(
                  'Export',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: canExport
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        const SizedBox(width: 8),
        _QuickFilterButton(
          icon: FluentIcons.arrow_export_24_regular,
          label: 'Exported',
          tooltip: 'Show only projects that have been exported',
          isSelected: currentFilter == ProjectQuickFilter.exported,
          onTap: () => _setQuickFilter(
            currentFilter == ProjectQuickFilter.exported
                ? ProjectQuickFilter.none
                : ProjectQuickFilter.exported,
          ),
        ),
        const SizedBox(width: 8),
        _QuickFilterButton(
          icon: FluentIcons.arrow_export_ltr_24_regular,
          label: 'Not Exported',
          tooltip: 'Show only projects that have never been exported',
          isSelected: currentFilter == ProjectQuickFilter.notExported,
          onTap: () => _setQuickFilter(
            currentFilter == ProjectQuickFilter.notExported
                ? ProjectQuickFilter.none
                : ProjectQuickFilter.notExported,
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
      case ProjectSortOption.dateExported:
        return FluentIcons.arrow_export_24_regular;
      case ProjectSortOption.progress:
        return FluentIcons.chart_multiple_24_regular;
    }
  }
}

/// Reusable Fluent Design button widget
class _FluentButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool showDropdownIcon;
  final bool isActive;
  final VoidCallback? onTap;

  const _FluentButton({
    required this.icon,
    required this.label,
    this.showDropdownIcon = false,
    this.isActive = false,
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

    Color backgroundColor;
    Color borderColor;
    Color contentColor;

    if (widget.isActive) {
      backgroundColor = theme.colorScheme.primary;
      borderColor = theme.colorScheme.primary;
      contentColor = theme.colorScheme.onPrimary;
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);
      borderColor = theme.colorScheme.outline.withValues(alpha: 0.3);
      contentColor = theme.colorScheme.onSurface;
    } else {
      backgroundColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      borderColor = theme.colorScheme.outline.withValues(alpha: 0.2);
      contentColor = theme.colorScheme.onSurface;
    }

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
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: contentColor,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: contentColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.showDropdownIcon) ...[
                const SizedBox(width: 4),
                Icon(
                  FluentIcons.chevron_down_24_regular,
                  size: 16,
                  color: contentColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small action button for selection mode controls
class _SmallActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_SmallActionButton> createState() => _SmallActionButtonState();
}

class _SmallActionButtonState extends State<_SmallActionButton> {
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isHovered
                  ? theme.colorScheme.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovered
                    ? theme.colorScheme.outline.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 14,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
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
