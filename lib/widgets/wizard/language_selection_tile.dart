import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../../models/domain/language.dart';

/// Grid cell for language selection in wizard dialogs (Plan 5d §7.5).
///
/// Renders a toggle-able language card with panel2/accentBg state, accent
/// border + checkmark when selected, and hover feedback via MouseRegion.
/// Shared between Game Translation and New Project target-language steps.
class LanguageSelectionTile extends StatefulWidget {
  final Language language;
  final bool isSelected;
  final VoidCallback onTap;

  const LanguageSelectionTile({
    super.key,
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<LanguageSelectionTile> createState() => _LanguageSelectionTileState();
}

class _LanguageSelectionTileState extends State<LanguageSelectionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = tokens.accentBg;
    } else if (_isHovered) {
      backgroundColor = tokens.panel;
    } else {
      backgroundColor = tokens.panel2;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: widget.isSelected ? tokens.accent : tokens.border,
              width: widget.isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    FluentIcons.checkmark_24_regular,
                    size: 14,
                    color: tokens.accent,
                  ),
                ),
              Text(
                widget.language.displayName,
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: widget.isSelected ? tokens.accent : tokens.text,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
