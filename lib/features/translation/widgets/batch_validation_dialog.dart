import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:file_picker/file_picker.dart';
import '../../../providers/batch/batch_operations_provider.dart';

/// Dialog showing validation results for selected units
///
/// Displays:
/// - Summary (total validated, issues found, passed count)
/// - List of validation issues with severity
/// - Filter options (errors only, warnings only)
/// - Auto-fix capability for common issues
/// - Export validation report
class BatchValidationDialog extends StatefulWidget {
  const BatchValidationDialog({
    super.key,
    required this.issues,
    required this.totalValidated,
    required this.passedCount,
    required this.onAutoFix,
    required this.onExportReport,
  });

  final List<ValidationIssue> issues;
  final int totalValidated;
  final int passedCount;
  final VoidCallback onAutoFix;
  final Function(String filePath) onExportReport;

  @override
  State<BatchValidationDialog> createState() => _BatchValidationDialogState();
}

class _BatchValidationDialogState extends State<BatchValidationDialog> {
  bool _showOnlyErrors = false;
  bool _showOnlyWarnings = false;

  BatchValidationState get _validationState {
    return BatchValidationState(
      issues: widget.issues,
      totalValidated: widget.totalValidated,
      passedCount: widget.passedCount,
      showOnlyErrors: _showOnlyErrors,
      showOnlyWarnings: _showOnlyWarnings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final validationState = _validationState;

    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.shield_checkmark_24_regular,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Validation Results (${validationState.totalValidated} Units)',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Summary
            _buildSummary(validationState),
            const SizedBox(height: 20),

            // Filters
            Row(
              children: [
                _buildFilterChip(
                  label: 'Show Errors Only',
                  icon: FluentIcons.error_circle_24_regular,
                  isActive: _showOnlyErrors,
                  onTap: () => setState(() {
                    _showOnlyErrors = !_showOnlyErrors;
                    _showOnlyWarnings = false;
                  }),
                  color: Colors.red[700]!,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Show Warnings Only',
                  icon: FluentIcons.warning_24_regular,
                  isActive: _showOnlyWarnings,
                  onTap: () => setState(() {
                    _showOnlyWarnings = !_showOnlyWarnings;
                    _showOnlyErrors = false;
                  }),
                  color: Colors.orange[700]!,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Results list
            Expanded(
              child: _buildResultsList(validationState),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Auto-fix button (left side)
                if (validationState.issues.any((i) => i.canAutoFix))
                  _buildButton(
                    label: 'Auto-Fix All',
                    icon: FluentIcons.wrench_24_regular,
                    onPressed: widget.onAutoFix,
                  ),
                const Spacer(),

                // Export and Close buttons (right side)
                _buildButton(
                  label: 'Export Report',
                  icon: FluentIcons.document_24_regular,
                  onPressed: _exportReport,
                ),
                const SizedBox(width: 8),
                _buildButton(
                  label: 'Close',
                  isPrimary: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BatchValidationState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSummaryItem(
            label: 'Total Validated',
            value: '${state.totalValidated}',
            icon: FluentIcons.checkmark_circle_24_regular,
            color: Theme.of(context).colorScheme.primary,
          ),
          _buildDivider(),
          _buildSummaryItem(
            label: 'Issues Found',
            value: '${state.issuesFoundCount}',
            icon: FluentIcons.info_24_regular,
            color: Colors.blue[700]!,
          ),
          _buildDivider(),
          _buildSummaryItem(
            label: 'Errors',
            value: '${state.errorCount}',
            icon: FluentIcons.error_circle_24_regular,
            color: Colors.red[700]!,
          ),
          _buildDivider(),
          _buildSummaryItem(
            label: 'Warnings',
            value: '${state.warningCount}',
            icon: FluentIcons.warning_24_regular,
            color: Colors.orange[700]!,
          ),
          _buildDivider(),
          _buildSummaryItem(
            label: 'Passed',
            value: '${state.passedCount}',
            icon: FluentIcons.checkmark_24_regular,
            color: Colors.green[700]!,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 50,
      color: Theme.of(context).dividerColor,
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required Color color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : Theme.of(context).dividerColor,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isActive ? color : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(BatchValidationState state) {
    final issues = state.filteredIssues;

    if (issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 64,
              color: Colors.green[700],
            ),
            const SizedBox(height: 16),
            Text(
              'No validation issues found!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.green[700],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        itemCount: issues.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: Theme.of(context).dividerColor,
        ),
        itemBuilder: (context, index) {
          final issue = issues[index];
          return _buildIssueItem(issue);
        },
      ),
    );
  }

  Widget _buildIssueItem(ValidationIssue issue) {
    final isError = issue.severity == ValidationSeverity.error;
    final color = isError ? Colors.red[700]! : Colors.orange[700]!;
    final icon = isError
        ? FluentIcons.error_circle_24_regular
        : FluentIcons.warning_24_regular;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      issue.unitKey,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        issue.issueType,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  issue.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (issue.canAutoFix) ...[
            const SizedBox(width: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  // TODO: Fix individual issue
                },
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
                        FluentIcons.wrench_24_regular,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Fix',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    IconData? icon,
    bool isPrimary = false,
    required VoidCallback onPressed,
  }) {
    if (isPrimary) {
      return FluentButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    } else {
      return FluentTextButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    }
  }

  Future<void> _exportReport() async {
    String? result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Validation Report',
      fileName: 'validation_report.txt',
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv'],
    );

    if (result != null) {
      widget.onExportReport(result);
      if (mounted) {
        FluentToast.success(context, 'Validation report exported successfully');
      }
    }
  }
}
