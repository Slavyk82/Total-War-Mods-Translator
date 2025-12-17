import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/domain/project.dart';
import '../../../services/game/game_localization_service.dart';

/// Project overview section showing basic project information.
///
/// Displays project name, Steam Workshop link (for mods), source language (for game translations),
/// and delete button.
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
          _buildProjectTypeBadge(context),
          const SizedBox(width: 16),
          Expanded(
            child: _buildProjectInfo(context),
          ),
          if (onDelete != null) _buildDeleteButton(context),
        ],
      ),
    );
  }

  Widget _buildProjectTypeBadge(BuildContext context) {
    final theme = Theme.of(context);
    final isGame = project.isGameTranslation;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isGame
            ? theme.colorScheme.tertiary.withValues(alpha: 0.15)
            : theme.colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isGame
              ? theme.colorScheme.tertiary.withValues(alpha: 0.3)
              : theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGame ? FluentIcons.globe_24_regular : FluentIcons.cube_24_regular,
            size: 16,
            color: isGame ? theme.colorScheme.tertiary : theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            isGame ? 'Game' : 'Mod',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isGame ? theme.colorScheme.tertiary : theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectInfo(BuildContext context) {
    if (project.isGameTranslation) {
      return _buildGameInfo(context);
    } else if (project.modSteamId != null) {
      return _buildSteamInfo(context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildGameInfo(BuildContext context) {
    final theme = Theme.of(context);
    final sourceCode = project.sourceLanguageCode;

    if (sourceCode == null) return const SizedBox.shrink();

    final languageName = GameLocalizationService.languageCodeNames[sourceCode] ??
        sourceCode.toUpperCase();

    return Row(
      children: [
        Icon(
          FluentIcons.local_language_24_regular,
          size: 16,
          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          'Source Language: $languageName',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          ),
        ),
      ],
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
