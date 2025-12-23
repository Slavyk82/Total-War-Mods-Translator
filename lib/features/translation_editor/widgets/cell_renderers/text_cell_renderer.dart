import 'package:flutter/material.dart';

/// Text cell widget for DataGrid
///
/// Displays text content with optional styling for key columns
/// Shows raw text with escape sequences visible (e.g., \n displayed literally)
class TextCellRenderer extends StatelessWidget {
  final String? text;
  final bool isKey;
  /// When true, uses regular Text widget to allow DataGrid double-click editing
  /// When false (default), uses SelectableText for copy support
  final bool isEditable;

  const TextCellRenderer({
    super.key,
    required this.text,
    this.isKey = false,
    this.isEditable = false,
  });

  /// Escape special characters to display them literally
  /// Converts actual newlines/tabs to their escape sequence representation
  String _escapeForDisplay(String text) {
    return text
        .replaceAll('\r\n', '\\r\\n')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  @override
  Widget build(BuildContext context) {
    final rawText = text ?? '';
    final displayText = _escapeForDisplay(rawText);

    final textStyle = TextStyle(
      fontSize: 13,
      fontWeight: isKey ? FontWeight.w500 : FontWeight.normal,
      color: rawText.isEmpty ? Colors.grey : null,
    );

    // Use regular Text for editable cells to allow DataGrid double-click editing
    // Use SelectableText for read-only cells to allow copy
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: isEditable
          ? Text(displayText, style: textStyle)
          : SelectableText(displayText, style: textStyle),
    );
  }
}
