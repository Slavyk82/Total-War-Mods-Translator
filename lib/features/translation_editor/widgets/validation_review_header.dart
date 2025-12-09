import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Header section for validation review screen.
/// Shows title, back button, export button, and summary statistics.
class ValidationReviewHeader extends StatelessWidget {
  const ValidationReviewHeader({
    super.key,
    required this.totalValidated,
    required this.activeIssuesCount,
    required this.errorCount,
    required this.warningCount,
    required this.passedCount,
    required this.reviewedCount,
    required this.onExport,
    required this.onClose,
  });

  final int totalValidated;
  final int activeIssuesCount;
  final int errorCount;
  final int warningCount;
  final int passedCount;
  final int reviewedCount;
  final VoidCallback onExport;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with back button
          Row(
            children: [
              _BackButton(
                onTap: () {
                  if (onClose != null) {
                    onClose!();
                  } else {
                    context.pop();
                  }
                },
              ),
              const SizedBox(width: 16),
              Icon(
                FluentIcons.shield_checkmark_24_regular,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Validation Review',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FluentTextButton(
                onPressed: onExport,
                icon: const Icon(FluentIcons.document_arrow_down_24_regular),
                child: const Text('Export Report'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Summary cards
          Row(
            children: [
              _SummaryCard(
                label: 'Total Validated',
                value: '$totalValidated',
                icon: FluentIcons.checkmark_circle_24_regular,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              _SummaryCard(
                label: 'Issues Found',
                value: '$activeIssuesCount',
                icon: FluentIcons.info_24_regular,
                color: Colors.blue[700]!,
              ),
              const SizedBox(width: 16),
              _SummaryCard(
                label: 'Errors',
                value: '$errorCount',
                icon: FluentIcons.error_circle_24_regular,
                color: Colors.red[700]!,
              ),
              const SizedBox(width: 16),
              _SummaryCard(
                label: 'Warnings',
                value: '$warningCount',
                icon: FluentIcons.warning_24_regular,
                color: Colors.orange[700]!,
              ),
              const SizedBox(width: 16),
              _SummaryCard(
                label: 'Passed',
                value: '$passedCount',
                icon: FluentIcons.checkmark_24_regular,
                color: Colors.green[700]!,
              ),
              const SizedBox(width: 16),
              _SummaryCard(
                label: 'Reviewed',
                value: '$reviewedCount',
                icon: FluentIcons.clipboard_checkmark_24_regular,
                color: Colors.purple[700]!,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Icon(
            FluentIcons.arrow_left_24_regular,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
