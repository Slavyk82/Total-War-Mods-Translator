import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/game_installation.dart';

/// Project overview section showing basic project information.
///
/// Displays project name, game, Steam Workshop link, description,
/// status badge, timestamps, and edit button.
class ProjectOverviewSection extends StatefulWidget {
  final Project project;
  final GameInstallation? gameInstallation;
  final VoidCallback? onEdit;

  const ProjectOverviewSection({
    super.key,
    required this.project,
    this.gameInstallation,
    this.onEdit,
  });

  @override
  State<ProjectOverviewSection> createState() => _ProjectOverviewSectionState();
}

class _ProjectOverviewSectionState extends State<ProjectOverviewSection> {
  bool _editButtonHovered = false;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.project.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildGameInfo(context),
                  ],
                ),
              ),
              _buildStatusBadge(context),
              if (widget.onEdit != null) ...[
                const SizedBox(width: 12),
                _buildEditButton(context),
              ],
            ],
          ),
          if (widget.project.modSteamId != null) ...[
            const SizedBox(height: 16),
            _buildSteamInfo(context),
          ],
          const SizedBox(height: 16),
          _buildTimestamps(context),
        ],
      ),
    );
  }

  Widget _buildGameInfo(BuildContext context) {
    final theme = Theme.of(context);
    final gameInstallation = widget.gameInstallation;

    return Row(
      children: [
        Icon(
          _getGameIcon(gameInstallation?.gameCode),
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          gameInstallation?.gameName ?? 'Unknown Game',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildSteamInfo(BuildContext context) {
    final theme = Theme.of(context);
    final modId = widget.project.modSteamId!;

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

  Widget _buildTimestamps(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a');

    final created = DateTime.fromMillisecondsSinceEpoch(
      widget.project.createdAt * 1000,
    );
    final modified = DateTime.fromMillisecondsSinceEpoch(
      widget.project.updatedAt * 1000,
    );

    return Row(
      children: [
        Icon(
          FluentIcons.calendar_24_regular,
          size: 14,
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          'Created: ${dateFormat.format(created)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 24),
        Icon(
          FluentIcons.clock_24_regular,
          size: 14,
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          'Modified: ${dateFormat.format(modified)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, bgColor, fgColor) = _getStatusInfo(theme, widget.project.status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fgColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditButton(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _editButtonHovered = true),
      onExit: (_) => setState(() => _editButtonHovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _editButtonHovered
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.edit_24_regular,
                size: 16,
                color: _editButtonHovered
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'Edit Project',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _editButtonHovered
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getGameIcon(String? gameCode) {
    switch (gameCode?.toLowerCase()) {
      case 'wh3':
      case 'wh2':
      case 'wh1':
        return FluentIcons.shield_24_regular;
      case 'troy':
        return FluentIcons.crown_24_regular;
      case 'threekingdoms':
      case '3k':
        return FluentIcons.people_24_regular;
      default:
        return FluentIcons.games_24_regular;
    }
  }

  (IconData, String, Color, Color) _getStatusInfo(
    ThemeData theme,
    ProjectStatus status,
  ) {
    switch (status) {
      case ProjectStatus.draft:
        return (
          FluentIcons.document_24_regular,
          'Draft',
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        );
      case ProjectStatus.translating:
        return (
          FluentIcons.translate_24_regular,
          'Translating',
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        );
      case ProjectStatus.reviewing:
        return (
          FluentIcons.document_search_24_regular,
          'Reviewing',
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        );
      case ProjectStatus.completed:
        return (
          FluentIcons.checkmark_circle_24_regular,
          'Completed',
          Colors.green.withValues(alpha: 0.2),
          Colors.green.shade700,
        );
    }
  }

  Future<void> _launchSteamWorkshop(String modId) async {
    final url = Uri.parse('https://steamcommunity.com/sharedfiles/filedetails/?id=$modId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
