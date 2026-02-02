import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../models/compilation_conflict.dart';
import '../providers/compilation_conflict_providers.dart';

/// Dialog showing detailed conflicts for a specific project.
class ProjectConflictsDetailDialog extends ConsumerWidget {
  const ProjectConflictsDetailDialog({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final analysisAsync = ref.watch(compilationConflictAnalysisProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 900,
          maxHeight: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.warning_24_regular,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conflicts for Project',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          projectName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: analysisAsync.when(
                data: (analysis) {
                  if (analysis == null) {
                    return const Center(
                      child: Text('No analysis data'),
                    );
                  }

                  // Get conflicts involving this project (excluding auto-resolvable)
                  final conflicts = analysis.conflicts.where((conflict) {
                    if (conflict.canAutoResolve) return false;
                    return conflict.firstEntry.projectId == projectId ||
                        conflict.secondEntry.projectId == projectId;
                  }).toList();

                  if (conflicts.isEmpty) {
                    return const Center(
                      child: Text('No conflicts found'),
                    );
                  }

                  return _buildConflictTable(context, theme, conflicts);
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Center(
                  child: Text('Error: $error'),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictTable(
    BuildContext context,
    ThemeData theme,
    List<CompilationConflict> conflicts,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        border: TableBorder.all(
          color: theme.dividerColor,
          borderRadius: BorderRadius.circular(8),
        ),
        columnWidths: const {
          0: FlexColumnWidth(1.5), // Key
          1: FlexColumnWidth(2), // This project's source
          2: FlexColumnWidth(2), // Conflicting project's source
        },
        children: [
          // Header row
          TableRow(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            children: [
              _buildHeaderCell(theme, 'Conflicting Key'),
              _buildHeaderCell(theme, 'Source Text (This Project)'),
              _buildHeaderCell(theme, 'Source Text (Conflicting)'),
            ],
          ),
          // Data rows
          ...conflicts.map((conflict) {
            // Determine which entry belongs to this project
            final isFirst = conflict.firstEntry.projectId == projectId;
            final thisEntry =
                isFirst ? conflict.firstEntry : conflict.secondEntry;
            final otherEntry =
                isFirst ? conflict.secondEntry : conflict.firstEntry;

            return TableRow(
              children: [
                _buildKeyCell(theme, conflict.key),
                _buildSourceTextCell(
                  theme,
                  thisEntry.projectName,
                  thisEntry.sourceText,
                  theme.colorScheme.primary,
                ),
                _buildSourceTextCell(
                  theme,
                  otherEntry.projectName,
                  otherEntry.sourceText,
                  theme.colorScheme.error,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(ThemeData theme, String text) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildKeyCell(ThemeData theme, String key) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.top,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          key,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceTextCell(
    ThemeData theme,
    String modName,
    String sourceText,
    Color accentColor,
  ) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.top,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mod name badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                modName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            // Source text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                sourceText,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
