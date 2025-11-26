import 'package:flutter/material.dart';

/// Text cell widget for DataGrid
///
/// Displays text content with optional styling for key columns
/// Supports text selection for copying content
class TextCellRenderer extends StatelessWidget {
  final String? text;
  final bool isKey;

  const TextCellRenderer({
    super.key,
    required this.text,
    this.isKey = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = text ?? '';

    // No GestureDetector - let DataGrid handle double-tap for editing
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isKey ? FontWeight.w500 : FontWeight.normal,
          color: displayText.isEmpty ? Colors.grey : null,
        ),
      ),
    );
  }
}
