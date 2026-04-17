import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../models/help_section.dart';

/// Sidebar widget displaying the table of contents for help documentation.
///
/// Shows all main sections and allows selection to display that section's
/// content. Styled via `context.tokens` so colours follow the active TWMT
/// theme (Atelier / Forge).
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
    final tokens = context.tokens;

    return Container(
      width: 280,
      color: tokens.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header.
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(
                  FluentIcons.list_24_regular,
                  size: 18,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Table of Contents',
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.accent,
                      fontStyle: tokens.fontDisplayItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: tokens.border),
          // Section list.
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

/// Individual TOC item with token-themed hover / selected states.
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
    final tokens = context.tokens;

    Color backgroundColor;
    if (widget.isActive) {
      backgroundColor = tokens.accentBg;
    } else if (_isHovered) {
      backgroundColor = tokens.panel2;
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: widget.isActive
                ? Border(
                    left: BorderSide(
                      color: tokens.accent,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Text(
            widget.title,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: widget.isActive ? tokens.accent : tokens.text,
              fontWeight:
                  widget.isActive ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
