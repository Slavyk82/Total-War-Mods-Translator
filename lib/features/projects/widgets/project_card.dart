import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

  const ProjectCard({
    super.key,
    required this.projectWithDetails,
    this.onTap,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _isHovered = false;

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
    final mutedColor = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    return Row(
      children: [
        // Mod image or game icon fallback
        _buildModImage(context, project, gameInstallation),
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
        // Changes badge (same as Mods screen) or mod update impact indicator
        if (widget.projectWithDetails.updateAnalysis != null ||
            widget.projectWithDetails.project.hasModUpdateImpact) ...[
          _buildChangesBadge(context),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...languages.map((langInfo) => Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: _buildProgressBar(
                context,
                langInfo.language?.name ?? 'Unknown',
                langInfo.progressPercent,
              ),
            )),
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
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressPercent / 100,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(theme, progressPercent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build changes badge with same labels as Mods screen
  Widget _buildChangesBadge(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = widget.projectWithDetails.updateAnalysis;
    final hasModUpdateImpact = widget.projectWithDetails.project.hasModUpdateImpact;

    // Show mod update impact badge if flag is set (even without pending analysis)
    if (hasModUpdateImpact) {
      return Tooltip(
        message: 'This project was modified by a mod update.\nSome translations may need review.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_24_regular,
                size: 12,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                'Mod updated',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade700,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // No analysis available
    if (analysis == null) {
      return const SizedBox.shrink();
    }

    // No pending changes - show "Up to date" with green checkmark
    if (!analysis.hasPendingChanges) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 12,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              'Up to date',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    // Has changes - build tooltip with details and show summary badge
    final tooltipLines = <String>[];
    if (analysis.hasNewUnits) {
      tooltipLines.add('+${analysis.newUnitsCount} new translations to add');
    }
    if (analysis.hasRemovedUnits) {
      tooltipLines.add('-${analysis.removedUnitsCount} translations removed');
    }
    if (analysis.hasModifiedUnits) {
      tooltipLines.add('~${analysis.modifiedUnitsCount} source texts changed');
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.warning_24_filled,
              size: 12,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 4),
            Text(
              analysis.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModImage(
    BuildContext context,
    Project project,
    GameInstallation? gameInstallation,
  ) {
    final theme = Theme.of(context);
    final imagePath = project.imageUrl;

    Widget fallbackIcon() => Icon(
      _getGameIcon(gameInstallation?.gameCode),
      size: 36,
      color: theme.colorScheme.onPrimaryContainer,
    );

    return Container(
      width: 75,
      height: 75,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: imagePath != null && imagePath.isNotEmpty
          ? Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              width: 75,
              height: 75,
              errorBuilder: (context, error, stackTrace) => fallbackIcon(),
            )
          : fallbackIcon(),
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
