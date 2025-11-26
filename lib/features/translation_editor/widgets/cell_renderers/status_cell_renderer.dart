import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../../models/domain/translation_version.dart';

/// Status cell widget for DataGrid
///
/// Displays a status icon with color coding to indicate the translation version status
class StatusCellRenderer extends StatelessWidget {
  final TranslationVersionStatus status;

  const StatusCellRenderer({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: StatusIcon(status: status),
    );
  }
}

/// Status icon widget for DataGrid
///
/// Renders the appropriate icon and color based on translation version status
class StatusIcon extends StatelessWidget {
  final TranslationVersionStatus status;

  const StatusIcon({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _getStatusIcon();
    final color = _getStatusColor();

    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }

  IconData _getStatusIcon() {
    switch (status) {
      case TranslationVersionStatus.pending:
        return FluentIcons.circle_24_regular;
      case TranslationVersionStatus.translated:
        return FluentIcons.checkmark_circle_24_regular;
      case TranslationVersionStatus.needsReview:
        return FluentIcons.warning_24_regular;
    }
  }

  Color _getStatusColor() {
    switch (status) {
      case TranslationVersionStatus.pending:
        return Colors.grey;
      case TranslationVersionStatus.translated:
        return Colors.green;
      case TranslationVersionStatus.needsReview:
        return Colors.orange;
    }
  }
}
