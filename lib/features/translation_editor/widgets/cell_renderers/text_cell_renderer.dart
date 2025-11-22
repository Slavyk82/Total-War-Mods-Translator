import 'package:flutter/material.dart';

/// Text cell widget for DataGrid
///
/// Displays text content with optional styling for key columns
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
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Text(
        text ?? '',
        style: TextStyle(
          fontSize: 13,
          fontWeight: isKey ? FontWeight.w500 : FontWeight.normal,
          color: text == null ? Colors.grey : null,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
