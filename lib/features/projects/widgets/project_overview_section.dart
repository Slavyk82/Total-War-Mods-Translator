import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/domain/project.dart';

/// Project overview section showing basic project information.
///
/// Displays project name, Steam Workshop link, and delete button.
class ProjectOverviewSection extends StatelessWidget {
  final Project project;
  final VoidCallback? onDelete;

  const ProjectOverviewSection({
    super.key,
    required this.project,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: project.modSteamId != null
                ? _buildSteamInfo(context)
                : const SizedBox.shrink(),
          ),
          if (onDelete != null) _buildDeleteButton(context),
        ],
      ),
    );
  }

  Widget _buildSteamInfo(BuildContext context) {
    final theme = Theme.of(context);
    final modId = project.modSteamId!;

    return Row(
      children: [
        Icon(
          FluentIcons.cloud_24_regular,
          size: 16,
          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          'Steam Workshop ID: $modId',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 12),
        _buildSteamLinkButton(context, modId),
      ],
    );
  }

  Widget _buildSteamLinkButton(BuildContext context, String modId) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _launchSteamWorkshop(modId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.open_24_regular,
                size: 14,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Open in Steam',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onDelete,
        child: Tooltip(
          message: 'Delete Project',
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              FluentIcons.delete_24_regular,
              size: 18,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchSteamWorkshop(String modId) async {
    final url = Uri.parse('https://steamcommunity.com/sharedfiles/filedetails/?id=$modId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
