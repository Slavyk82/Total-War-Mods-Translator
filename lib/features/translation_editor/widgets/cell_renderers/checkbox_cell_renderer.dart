import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Checkbox cell widget for DataGrid row selection.
///
/// Displays a checkbox tinted with the active theme tokens (accent for the
/// checked fill, border for the resting outline) so it stays consistent with
/// the rest of the editor surface across Atelier / Forge.
class CheckboxCellRenderer extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const CheckboxCellRenderer({
    super.key,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Checkbox(
            value: isSelected,
            onChanged: (_) => onTap(),
            activeColor: tokens.accent,
            checkColor: tokens.accentFg,
            side: BorderSide(color: tokens.border, width: 1),
          ),
        ),
      ),
    );
  }
}
