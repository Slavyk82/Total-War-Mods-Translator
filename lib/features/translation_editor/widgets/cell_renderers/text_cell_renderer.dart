import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Text cell widget for DataGrid
///
/// Displays text content with optional styling for key columns
/// Shows raw text with escape sequences visible (e.g., \n displayed literally)
/// Supports text selection (copy via Ctrl+C) while allowing DataGrid context menu
class TextCellRenderer extends StatelessWidget {
  final String? text;
  final bool isKey;
  /// When true, indicates this is an editable cell (for styling purposes)
  final bool isEditable;
  /// Callback for secondary tap (right-click) to show context menu
  final void Function(Offset globalPosition)? onSecondaryTap;

  const TextCellRenderer({
    super.key,
    required this.text,
    this.isKey = false,
    this.isEditable = false,
    this.onSecondaryTap,
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

    // Use Listener to intercept right-click and show context menu immediately
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            // Immediately show context menu on right-click
            onSecondaryTap?.call(event.position);
          }
        },
        // translucent allows events to pass through for DataGrid interactions
        behavior: HitTestBehavior.translucent,
        // For editable cells, use regular Text to allow double-click to pass
        // through to DataGrid for edit mode. For non-editable cells, use
        // SelectableText for copy functionality.
        child: isEditable
            ? Text(
                displayText,
                style: textStyle,
              )
            : SelectableText(
                displayText,
                style: textStyle,
                // Disable SelectableText context menu - we handle it via Listener
                contextMenuBuilder: (context, editableTextState) {
                  return const SizedBox.shrink();
                },
              ),
      ),
    );
  }
}
