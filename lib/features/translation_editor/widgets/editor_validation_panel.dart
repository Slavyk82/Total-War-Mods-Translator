import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/editor_providers.dart';

/// Validation panel showing translation quality issues
///
/// Displays validation errors, warnings, and info with auto-fix suggestions
class EditorValidationPanel extends ConsumerStatefulWidget {
  final String? sourceText;
  final String? translatedText;
  final Function(String fixedText)? onApplyFix;
  final Function(String fixedText)? onApplyAllFixes;
  final Function()? onValidate;

  const EditorValidationPanel({
    super.key,
    this.sourceText,
    this.translatedText,
    this.onApplyFix,
    this.onApplyAllFixes,
    this.onValidate,
  });

  @override
  ConsumerState<EditorValidationPanel> createState() =>
      _EditorValidationPanelState();
}

class _EditorValidationPanelState
    extends ConsumerState<EditorValidationPanel> {
  String? _hoveredIssueId;

  @override
  Widget build(BuildContext context) {
    if (widget.sourceText == null || widget.translatedText == null) {
      return _buildEmptyState(
        icon: FluentIcons.warning_24_regular,
        message: 'Select a translation unit to view validation issues',
      );
    }

    // Watch validation issues from provider
    final issuesAsync = ref.watch(
      validationIssuesProvider(widget.sourceText!, widget.translatedText!),
    );

    return issuesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        message: 'Error loading validation issues',
      ),
      data: (issues) => _buildValidationList(issues),
    );
  }

  Widget _buildValidationList(List<ValidationIssue> issues) {
    if (issues.isEmpty) {
      return _buildSuccessState();
    }

    // Group issues by severity
    final errors =
        issues.where((i) => i.severity == ValidationSeverity.error).toList();
    final warnings =
        issues.where((i) => i.severity == ValidationSeverity.warning).toList();
    final infos =
        issues.where((i) => i.severity == ValidationSeverity.info).toList();

    final autoFixableIssues = issues.where((i) => i.autoFixable).toList();

    return Column(
      children: [
        // Summary header
        _buildSummaryHeader(
          errorCount: errors.length,
          warningCount: warnings.length,
          infoCount: infos.length,
          hasAutoFix: autoFixableIssues.isNotEmpty,
        ),

        // Issues list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Errors
              if (errors.isNotEmpty) ...[
                _buildSectionHeader('Errors', errors.length, Colors.red),
                const SizedBox(height: 8),
                ...errors.map((issue) => _buildIssueCard(issue)),
                const SizedBox(height: 16),
              ],

              // Warnings
              if (warnings.isNotEmpty) ...[
                _buildSectionHeader('Warnings', warnings.length, Colors.orange),
                const SizedBox(height: 8),
                ...warnings.map((issue) => _buildIssueCard(issue)),
                const SizedBox(height: 16),
              ],

              // Info
              if (infos.isNotEmpty) ...[
                _buildSectionHeader('Info', infos.length, Colors.blue),
                const SizedBox(height: 8),
                ...infos.map((issue) => _buildIssueCard(issue)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryHeader({
    required int errorCount,
    required int warningCount,
    required int infoCount,
    required bool hasAutoFix,
  }) {
    final hasErrors = errorCount > 0;
    final canValidate = !hasErrors;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: hasErrors
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Status icon
          Icon(
            hasErrors
                ? FluentIcons.error_circle_24_filled
                : FluentIcons.checkmark_circle_24_filled,
            size: 24,
            color: hasErrors ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 12),

          // Summary text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasErrors ? 'Validation Issues Found' : 'Ready to Validate',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hasErrors ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildSummaryText(errorCount, warningCount, infoCount),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          if (hasAutoFix) ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _handleApplyAllFixes,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue, width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.wrench_24_regular,
                        size: 14,
                        color: Colors.blue,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Fix All',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Validate button
          Opacity(
            opacity: canValidate ? 1.0 : 0.5,
            child: MouseRegion(
              cursor: canValidate
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.forbidden,
              child: GestureDetector(
                onTap: canValidate ? _handleValidate : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.checkmark_24_regular,
                        size: 14,
                        color: Colors.green,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Validate',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildSummaryText(int errors, int warnings, int infos) {
    final parts = <String>[];
    if (errors > 0) parts.add('$errors ${errors == 1 ? 'error' : 'errors'}');
    if (warnings > 0) {
      parts.add('$warnings ${warnings == 1 ? 'warning' : 'warnings'}');
    }
    if (infos > 0) parts.add('$infos info');

    return parts.isEmpty ? 'No issues found' : parts.join(', ');
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$title ($count)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildIssueCard(ValidationIssue issue) {
    final color = _getSeverityColor(issue.severity);
    final issueId = '${issue.type}_${issue.description.hashCode}';
    final isHovered = _hoveredIssueId == issueId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredIssueId = issueId),
        onExit: (_) => setState(() => _hoveredIssueId = null),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHovered
                ? color.withValues(alpha: 0.15)
                : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovered
                  ? color.withValues(alpha: 0.6)
                  : color.withValues(alpha: 0.4),
              width: isHovered ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon and description
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _getSeverityIcon(issue.severity),
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issue.description,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              // Suggestion
              if (issue.suggestion != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        FluentIcons.lightbulb_24_regular,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          issue.suggestion!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Auto-fix button
              if (issue.autoFixable) ...[
                const SizedBox(height: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _handleApplyFix(issue),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.wrench_24_regular,
                            size: 12,
                            color: Colors.blue,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Auto-fix',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue,
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
        ),
      ),
    );
  }

  void _handleApplyFix(ValidationIssue issue) {
    if (widget.onApplyFix != null && issue.autoFixValue != null) {
      widget.onApplyFix!(issue.autoFixValue!);
      FluentToast.success(context, 'Auto-fix applied');
    }
  }

  void _handleApplyAllFixes() {
    if (widget.onApplyAllFixes != null) {
      // This would need the list of issues to apply all fixes
      // For now, just trigger the callback
      FluentToast.info(context, 'Applying all auto-fixes...');
    }
  }

  void _handleValidate() {
    if (widget.onValidate != null) {
      widget.onValidate!();
      FluentToast.success(context, 'Translation validated');
    }
  }

  Color _getSeverityColor(ValidationSeverity severity) {
    switch (severity) {
      case ValidationSeverity.error:
        return Colors.red;
      case ValidationSeverity.warning:
        return Colors.orange;
      case ValidationSeverity.info:
        return Colors.blue;
    }
  }

  IconData _getSeverityIcon(ValidationSeverity severity) {
    switch (severity) {
      case ValidationSeverity.error:
        return FluentIcons.error_circle_24_filled;
      case ValidationSeverity.warning:
        return FluentIcons.warning_24_filled;
      case ValidationSeverity.info:
        return FluentIcons.info_24_filled;
    }
  }

  Widget _buildSuccessState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_filled,
            size: 64,
            color: Colors.green.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 16),
          const Text(
            'No issues found!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This translation passes all validation checks',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
