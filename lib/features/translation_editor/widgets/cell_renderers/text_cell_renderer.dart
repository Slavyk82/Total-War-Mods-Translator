import 'package:flutter/material.dart';

/// Text cell widget for DataGrid
///
/// Displays text content with optional styling for key columns
/// Shows raw text with escape sequences visible (e.g., \n displayed literally)
class TextCellRenderer extends StatelessWidget {
  final String? text;
  final bool isKey;

  const TextCellRenderer({
    super.key,
    required this.text,
    this.isKey = false,
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

    // No GestureDetector - let DataGrid handle double-tap for editing
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isKey ? FontWeight.w500 : FontWeight.normal,
          color: rawText.isEmpty ? Colors.grey : null,
        ),
      ),
    );
  }
}
