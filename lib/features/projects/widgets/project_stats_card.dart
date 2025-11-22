import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/project_detail_providers.dart';

/// Card displaying project translation statistics.
///
/// Shows total units, status breakdown, TM reuse rate,
/// and tokens used.
class ProjectStatsCard extends StatelessWidget {
  final TranslationStats stats;

  const ProjectStatsCard({
    super.key,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20.0),
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
              Icon(
                FluentIcons.data_bar_vertical_24_regular,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Translation Statistics',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildStatRow(
            context,
            FluentIcons.text_number_list_ltr_24_regular,
            'Total Units',
            stats.totalUnits.toString(),
            theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          _buildDivider(context),
          const SizedBox(height: 12),
          _buildStatRow(
            context,
            FluentIcons.checkmark_circle_24_regular,
            'Translated',
            stats.translatedUnits.toString(),
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            context,
            FluentIcons.clock_24_regular,
            'Pending',
            stats.pendingUnits.toString(),
            Colors.orange,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            context,
            FluentIcons.checkmark_starburst_24_regular,
            'Validated',
            stats.validatedUnits.toString(),
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            context,
            FluentIcons.error_circle_24_regular,
            'Errors',
            stats.errorUnits.toString(),
            theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          _buildDivider(context),
          const SizedBox(height: 16),
          _buildStatRow(
            context,
            FluentIcons.archive_24_regular,
            'TM Reuse Rate',
            '${(stats.tmReuseRate * 100).toStringAsFixed(1)}%',
            theme.colorScheme.tertiary,
          ),
          const SizedBox(height: 12),
          _buildStatRow(
            context,
            FluentIcons.textbox_24_regular,
            'Tokens Used',
            _formatNumber(stats.tokensUsed),
            theme.colorScheme.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    } else {
      return number.toString();
    }
  }
}

/// Card displaying action buttons for the project.
///
/// Shows export and delete project buttons.
class ProjectActionsCard extends StatefulWidget {
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  const ProjectActionsCard({
    super.key,
    this.onExport,
    this.onDelete,
  });

  @override
  State<ProjectActionsCard> createState() => _ProjectActionsCardState();
}

class _ProjectActionsCardState extends State<ProjectActionsCard> {
  bool _exportHovered = false;
  bool _deleteHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20.0),
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
              Icon(
                FluentIcons.options_24_regular,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Actions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.onExport != null) ...[
            _buildExportButton(context),
            const SizedBox(height: 12),
          ],
          if (widget.onDelete != null) _buildDeleteButton(context),
        ],
      ),
    );
  }

  Widget _buildExportButton(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _exportHovered = true),
      onExit: (_) => setState(() => _exportHovered = false),
      child: GestureDetector(
        onTap: widget.onExport,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _exportHovered
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.arrow_export_24_regular,
                size: 18,
                color: _exportHovered
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Export All Languages',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _exportHovered
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
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
      onEnter: (_) => setState(() => _deleteHovered = true),
      onExit: (_) => setState(() => _deleteHovered = false),
      child: GestureDetector(
        onTap: widget.onDelete,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _deleteHovered
                ? theme.colorScheme.error
                : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.error.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.delete_24_regular,
                size: 18,
                color: _deleteHovered
                    ? theme.colorScheme.onError
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Delete Project',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _deleteHovered
                      ? theme.colorScheme.onError
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
