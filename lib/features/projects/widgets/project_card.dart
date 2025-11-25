import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/projects_screen_providers.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/game_installation.dart';

/// A card displaying project information in Fluent Design style.
///
/// Shows project name, game, mod ID, progress bars per language,
/// status badge, last modified time, and actions menu.
class ProjectCard extends StatefulWidget {
  final ProjectWithDetails projectWithDetails;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  const ProjectCard({
    super.key,
    required this.projectWithDetails,
    this.onTap,
    this.onEdit,
    this.onExport,
    this.onDelete,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _isHovered = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.projectWithDetails.project;
    final gameInstallation = widget.projectWithDetails.gameInstallation;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.surface.withValues(alpha: 0.8)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: theme.shadowColor.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, project, gameInstallation),
                const SizedBox(height: 10),
                _buildLanguageProgress(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Project project,
    GameInstallation? gameInstallation,
  ) {
    final theme = Theme.of(context);
    final lastModified = DateTime.fromMillisecondsSinceEpoch(
      project.updatedAt * 1000,
    );
    final mutedColor = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    return Row(
      children: [
        // Game icon
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            _getGameIcon(gameInstallation?.gameCode),
            size: 18,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        // Project name
        Expanded(
          child: Text(
            project.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Update badge
        if (widget.projectWithDetails.hasUpdates) ...[
          _buildUpdateBadge(context),
          const SizedBox(width: 8),
        ],
        // Steam ID
        if (project.modSteamId != null) ...[
          const SizedBox(width: 8),
          Icon(
            FluentIcons.cloud_24_regular,
            size: 14,
            color: mutedColor,
          ),
          const SizedBox(width: 4),
          Text(
            project.modSteamId!,
            style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
          ),
        ],
        // Timestamp
        const SizedBox(width: 12),
        Icon(
          FluentIcons.clock_24_regular,
          size: 14,
          color: mutedColor,
        ),
        const SizedBox(width: 4),
        Text(
          timeago.format(lastModified),
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        // Status badge
        const SizedBox(width: 12),
        _buildStatusBadge(context, project.status),
        const SizedBox(width: 8),
        // Actions menu
        _buildActionsMenu(context),
      ],
    );
  }

  Widget _buildLanguageProgress(BuildContext context) {
    final languages = widget.projectWithDetails.languages;
    final theme = Theme.of(context);

    if (languages.isEmpty) {
      return Text(
        'No target languages configured',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Show max 3 languages, rest indicated by count
    final displayLanguages = languages.take(3).toList();
    final remainingCount = languages.length - displayLanguages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayLanguages.map((langInfo) => Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: _buildProgressBar(
                context,
                langInfo.language?.name ?? 'Unknown',
                langInfo.progressPercent,
              ),
            )),
        if (remainingCount > 0)
          Text(
            '+$remainingCount more language${remainingCount > 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    String languageName,
    double progress,
  ) {
    final theme = Theme.of(context);
    final progressPercent = progress.clamp(0.0, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              languageName,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${progressPercent.toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              value: progressPercent / 100,
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(theme, progressPercent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateBadge(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.arrow_sync_circle_24_regular,
            size: 12,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Update Available',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, ProjectStatus status) {
    final theme = Theme.of(context);
    final (icon, label, bgColor, fgColor) = _getStatusInfo(theme, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsMenu(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        if (widget.onEdit != null)
          MenuItemButton(
            leadingIcon: const Icon(FluentIcons.edit_24_regular, size: 16),
            onPressed: widget.onEdit,
            child: const Text('Edit'),
          ),
        if (widget.onExport != null)
          MenuItemButton(
            leadingIcon: const Icon(FluentIcons.arrow_export_24_regular, size: 16),
            onPressed: widget.onExport,
            child: const Text('Export'),
          ),
        if (widget.onDelete != null) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(FluentIcons.delete_24_regular, size: 16),
            onPressed: widget.onDelete,
            child: const Text('Delete'),
          ),
        ],
      ],
      builder: (context, controller, child) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
              setState(() => _isMenuOpen = controller.isOpen);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _isMenuOpen || _isHovered
                    ? Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                FluentIcons.more_vertical_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getGameIcon(String? gameCode) {
    // Map game codes to icons
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
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        );
    }
  }

  Color _getProgressColor(ThemeData theme, double progress) {
    if (progress >= 100) {
      return Colors.green;
    } else if (progress >= 50) {
      return theme.colorScheme.primary;
    } else if (progress > 0) {
      return Colors.orange;
    } else {
      return theme.colorScheme.outline;
    }
  }
}
