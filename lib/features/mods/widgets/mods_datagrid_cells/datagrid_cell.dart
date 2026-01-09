import 'package:flutter/material.dart';

/// Performance-optimized DataGrid cell widget for displaying text content.
///
/// This is a reusable base cell widget that provides consistent styling
/// and layout for text-based cells in the mods DataGrid.
class TextDataGridCell extends StatelessWidget {
  /// The text to display in the cell.
  final String text;

  /// Optional font weight for the text.
  final FontWeight? fontWeight;

  /// Optional font family for the text (e.g., 'monospace' for IDs).
  final String? fontFamily;

  const TextDataGridCell({
    super.key,
    required this.text,
    this.fontWeight,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: fontWeight,
              fontFamily: fontFamily,
            ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
