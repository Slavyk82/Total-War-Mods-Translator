import 'package:flutter/material.dart';

/// Checkbox cell widget for DataGrid row selection
///
/// Displays a checkbox that allows users to select rows in the translation editor
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
          ),
        ),
      ),
    );
  }
}
