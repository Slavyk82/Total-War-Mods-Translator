import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/help_section.dart';

/// Sidebar widget displaying the table of contents for help documentation.
///
/// Shows all main sections and allows selection to display that section's content.
class HelpTocSidebar extends StatelessWidget {
  const HelpTocSidebar({
    super.key,
    required this.sections,
    required this.selectedIndex,
    required this.onSectionSelected,
  });

  /// List of all help sections.
  final List<HelpSection> sections;

  /// Index of the currently selected section.
  final int selectedIndex;

  /// Callback when a section is selected.
  final ValueChanged<int> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 280,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  FluentIcons.list_24_regular,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Table of Contents',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Section list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return _TocItem(
                  title: section.title,
                  isActive: index == selectedIndex,
                  onTap: () => onSectionSelected(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual TOC item with Fluent Design hover effects.
class _TocItem extends StatefulWidget {
  const _TocItem({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_TocItem> createState() => _TocItemState();
}

class _TocItemState extends State<_TocItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    if (widget.isActive) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.1);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.05);
    } else {
      backgroundColor = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: widget.isActive
                ? Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Text(
            widget.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: widget.isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
