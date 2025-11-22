import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/language.dart';

/// Card displaying language-specific translation progress.
///
/// Shows language name, progress bar, percentage, status badge,
/// and button to open the translation editor.
class LanguageCard extends StatefulWidget {
  final ProjectLanguage projectLanguage;
  final Language language;
  final int totalUnits;
  final int translatedUnits;
  final VoidCallback? onOpenEditor;

  const LanguageCard({
    super.key,
    required this.projectLanguage,
    required this.language,
    required this.totalUnits,
    required this.translatedUnits,
    this.onOpenEditor,
  });

  @override
  State<LanguageCard> createState() => _LanguageCardState();
}

class _LanguageCardState extends State<LanguageCard> {
  bool _isHovered = false;
  bool _buttonHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = widget.projectLanguage.progressPercent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
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
                        widget.language.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${widget.language.code.toUpperCase()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(context),
              ],
            ),
            const SizedBox(height: 16),
            _buildProgressSection(context, progress),
            const SizedBox(height: 16),
            _buildUnitCounts(context),
            const SizedBox(height: 16),
            _buildOpenEditorButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection(BuildContext context, double progress) {
    final theme = Theme.of(context);
    final progressPercent = progress.clamp(0.0, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Translation Progress',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${progressPercent.toInt()}%',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _getProgressColor(theme, progressPercent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: LinearProgressIndicator(
              value: progressPercent / 100,
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(theme, progressPercent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnitCounts(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          FluentIcons.text_number_list_ltr_24_regular,
          size: 16,
          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          '${widget.translatedUnits} / ${widget.totalUnits} units translated',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildOpenEditorButton(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _buttonHovered = true),
      onExit: (_) => setState(() => _buttonHovered = false),
      child: GestureDetector(
        onTap: widget.onOpenEditor,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _buttonHovered
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.edit_24_regular,
                size: 16,
                color: _buttonHovered
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                'Open Editor',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _buttonHovered
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

  Widget _buildStatusBadge(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.projectLanguage.status;
    final (icon, label, bgColor, fgColor) = _getStatusInfo(theme, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color, Color) _getStatusInfo(
    ThemeData theme,
    ProjectLanguageStatus status,
  ) {
    switch (status) {
      case ProjectLanguageStatus.pending:
        return (
          FluentIcons.clock_24_regular,
          'Pending',
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        );
      case ProjectLanguageStatus.translating:
        return (
          FluentIcons.translate_24_regular,
          'Translating',
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        );
      case ProjectLanguageStatus.completed:
        return (
          FluentIcons.checkmark_circle_24_regular,
          'Completed',
          Colors.green.withValues(alpha: 0.2),
          Colors.green.shade700,
        );
      case ProjectLanguageStatus.error:
        return (
          FluentIcons.error_circle_24_regular,
          'Error',
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        );
    }
  }

  Color _getProgressColor(ThemeData theme, double progress) {
    if (progress >= 100) {
      return Colors.green;
    } else if (progress >= 75) {
      return Colors.lightGreen;
    } else if (progress >= 50) {
      return theme.colorScheme.primary;
    } else if (progress >= 25) {
      return Colors.orange;
    } else if (progress > 0) {
      return Colors.deepOrange;
    } else {
      return theme.colorScheme.outline;
    }
  }
}
