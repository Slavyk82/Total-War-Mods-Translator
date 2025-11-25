import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    
    return GestureDetector(
      // Allow double-click to select and copy text
      onDoubleTap: () {
        if (displayText.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: displayText));
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          displayText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isKey ? FontWeight.w500 : FontWeight.normal,
            color: displayText.isEmpty ? Colors.grey : null,
          ),
        ),
      ),
    );
  }
}
