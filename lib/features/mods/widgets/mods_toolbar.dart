import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Toolbar for mods screen with search, filters, and actions
class ModsToolbar extends StatefulWidget {
  final String searchQuery;
  final Function(String) onSearchChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final int totalMods;
  final int filteredMods;

  const ModsToolbar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onRefresh,
    this.isRefreshing = false,
    required this.totalMods,
    required this.filteredMods,
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

          // Mod count
          _buildModCount(theme),
          const SizedBox(width: 16),

          // Refresh button
          _ToolbarButton(
            icon: FluentIcons.arrow_sync_24_regular,
            tooltip: 'Refresh mod list',
            onTap: widget.onRefresh,
            isLoading: widget.isRefreshing,
          ),
        ],
      ),
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
                ? MouseRegion(
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
