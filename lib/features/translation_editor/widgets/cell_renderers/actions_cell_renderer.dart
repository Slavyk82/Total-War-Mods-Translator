import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Actions cell widget for DataGrid
///
/// Displays a more options icon to indicate row actions are available
class ActionsCellRenderer extends StatelessWidget {
  const ActionsCellRenderer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: const Icon(
        FluentIcons.more_horizontal_24_regular,
        size: 16,
        color: Colors.grey,
      ),
    );
  }
}
