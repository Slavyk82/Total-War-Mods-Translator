import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:file_picker/file_picker.dart';
import '../../../providers/batch/batch_operations_provider.dart';

/// Dialog showing validation results for selected units
///
/// Displays:
/// - Summary (total validated, issues found, passed count)
/// - List of validation issues with severity, source text, and translation
/// - Filter options (errors only, warnings only)
/// - Accept/Reject buttons for each issue
/// - Export validation report
class BatchValidationDialog extends StatefulWidget {
  const BatchValidationDialog({
    super.key,
    required this.issues,
    required this.totalValidated,
    required this.passedCount,
    required this.onExportReport,
    required this.onRejectTranslation,
    required this.onAcceptTranslation,
  });

  final List<ValidationIssue> issues;
  final int totalValidated;
  final int passedCount;
  final Function(String filePath) onExportReport;
  /// Called when user rejects a translation (clears the translation)
  final Future<void> Function(ValidationIssue issue) onRejectTranslation;
  /// Called when user accepts a translation despite the issue
  final Future<void> Function(ValidationIssue issue) onAcceptTranslation;

  @override
  State<BatchValidationDialog> createState() => _BatchValidationDialogState();
}

class _BatchValidationDialogState extends State<BatchValidationDialog> {
  bool _showOnlyErrors = false;
  bool _showOnlyWarnings = false;
  final Set<String> _processedVersionIds = {};
  final Set<String> _processingVersionIds = {};
  int? _expandedIndex;

  List<ValidationIssue> get _activeIssues {
    return widget.issues
        .where((issue) => !_processedVersionIds.contains(issue.versionId))
        .toList();
  }

  BatchValidationState get _validationState {
    return BatchValidationState(
      issues: _activeIssues,
      totalValidated: widget.totalValidated,
      passedCount: widget.passedCount + _processedVersionIds.length,
      showOnlyErrors: _showOnlyErrors,
      showOnlyWarnings: _showOnlyWarnings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final validationState = _validationState;

    return Dialog(
      child: Container(
        width: 900,
        height: 700,
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Export and Close buttons
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
              _processedVersionIds.isNotEmpty
                  ? 'All issues have been reviewed!'
                  : 'No validation issues found!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.green[700],
              ),
            ),
            if (_processedVersionIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_processedVersionIds.length} unit(s) reviewed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
          final isExpanded = _expandedIndex == index;
          return _buildIssueItem(issue, index, isExpanded);
        },
      ),
    );
  }

  Widget _buildIssueItem(ValidationIssue issue, int index, bool isExpanded) {
    final isError = issue.severity == ValidationSeverity.error;
    final color = isError ? Colors.red[700]! : Colors.orange[700]!;
    final icon = isError
        ? FluentIcons.error_circle_24_regular
        : FluentIcons.warning_24_regular;
    final isProcessing = _processingVersionIds.contains(issue.versionId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row - clickable to expand/collapse
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _expandedIndex = isExpanded ? null : index;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              color: isExpanded
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    isExpanded
                        ? FluentIcons.chevron_down_24_regular
                        : FluentIcons.chevron_right_24_regular,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                issue.unitKey,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
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
                        const SizedBox(height: 2),
                        Text(
                          issue.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Expanded content - source, translation, and action buttons
        if (isExpanded)
          Container(
            padding: const EdgeInsets.fromLTRB(48, 0, 12, 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source text
                _buildTextSection(
                  label: 'Source',
                  text: issue.sourceText,
                  icon: FluentIcons.document_text_24_regular,
                ),
                const SizedBox(height: 12),
                // Translation text
                _buildTextSection(
                  label: 'Translation',
                  text: issue.translatedText,
                  icon: FluentIcons.translate_24_regular,
                  highlightColor: color.withValues(alpha: 0.05),
                ),
                const SizedBox(height: 16),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Reject button - clears translation
                    _buildActionButton(
                      label: 'Reject & Clear',
                      icon: FluentIcons.dismiss_24_regular,
                      color: Colors.red[700]!,
                      isLoading: isProcessing,
                      onPressed: isProcessing
                          ? null
                          : () => _handleReject(issue),
                    ),
                    const SizedBox(width: 8),
                    // Accept button - keeps translation
                    _buildActionButton(
                      label: 'Accept',
                      icon: FluentIcons.checkmark_24_regular,
                      color: Colors.green[700]!,
                      isLoading: isProcessing,
                      onPressed: isProcessing
                          ? null
                          : () => _handleAccept(issue),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTextSection({
    required String label,
    required String text,
    required IconData icon,
    Color? highlightColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlightColor ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isLoading,
    VoidCallback? onPressed,
  }) {
    return MouseRegion(
      cursor: onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: onPressed != null
                ? color.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: onPressed != null ? color : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 16, color: onPressed != null ? color : Theme.of(context).disabledColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: onPressed != null ? color : Theme.of(context).disabledColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleReject(ValidationIssue issue) async {
    setState(() {
      _processingVersionIds.add(issue.versionId);
    });

    try {
      await widget.onRejectTranslation(issue);
      setState(() {
        _processedVersionIds.add(issue.versionId);
        _expandedIndex = null;
      });
    } finally {
      setState(() {
        _processingVersionIds.remove(issue.versionId);
      });
    }
  }

  Future<void> _handleAccept(ValidationIssue issue) async {
    setState(() {
      _processingVersionIds.add(issue.versionId);
    });

    try {
      await widget.onAcceptTranslation(issue);
      setState(() {
        _processedVersionIds.add(issue.versionId);
        _expandedIndex = null;
      });
    } finally {
      setState(() {
        _processingVersionIds.remove(issue.versionId);
      });
    }
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
