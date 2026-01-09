import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Imported status badge widget.
///
/// Displays a visual badge indicating whether a mod has been imported
/// into the current project:
/// - "Imported" badge with checkmark icon when imported
/// - "Not Imported" badge when not imported
class ImportedBadge extends StatelessWidget {
  /// Whether the mod has been imported.
  final bool isImported;

  const ImportedBadge({super.key, required this.isImported});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isImported) {
      return _buildNotImportedBadge(theme);
    }

    return _buildImportedBadge(theme);
  }

  Widget _buildNotImportedBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Not Imported',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildImportedBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            size: 14,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Imported',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
