import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Text cell widget for DataGrid.
///
/// Rows are a fixed 44px: overflow is truncated with an ellipsis and the full
/// text — escape sequences included (e.g. `\n` shown literally) — is surfaced
/// in the right-hand inspector. Using plain [Text] here keeps Syncfusion's
/// gesture detector unblocked so `onCellTap` / `onCellSecondaryTap` fire
/// reliably; the inspector is the single source of truth for copy.
class TextCellRenderer extends StatelessWidget {
  final String? text;
  final bool isKey;

  const TextCellRenderer({
    super.key,
    required this.text,
    this.isKey = false,
  });

  /// Escape special characters to display them literally.
  String _escapeForDisplay(String text) {
    return text
        .replaceAll('\r\n', '\\r\\n')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final rawText = text ?? '';
    final displayText = _escapeForDisplay(rawText);

    final textStyle = TextStyle(
      fontSize: 13,
      fontWeight: isKey ? FontWeight.w500 : FontWeight.normal,
      color: rawText.isEmpty ? tokens.textFaint : tokens.text,
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        displayText,
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
