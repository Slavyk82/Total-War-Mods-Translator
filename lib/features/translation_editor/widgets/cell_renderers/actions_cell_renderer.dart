import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Actions cell widget for DataGrid.
///
/// Renders a faint chevron `›` indicating additional row actions are
/// available via the context menu (right-click). Colour and size match the
/// editor mockup spec (`tokens.textFaint`, fontSize 14).
class ActionsCellRenderer extends StatelessWidget {
  const ActionsCellRenderer({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: Text(
        '\u203A',
        style: TextStyle(
          fontSize: 14,
          color: tokens.textFaint,
        ),
      ),
    );
  }
}
