import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../models/compilation_conflict.dart';
import '../providers/compilation_conflict_providers.dart';

/// Token-themed popup showing detailed conflicts for a specific project.
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
    final tokens = context.tokens;
    final analysisAsync = ref.watch(compilationConflictAnalysisProvider);

    return TokenDialog(
      icon: FluentIcons.warning_24_regular,
      iconColor: tokens.warn,
      title: 'Conflicts for Project',
      subtitle: projectName,
      width: 900,
      body: SizedBox(
        height: 480,
        child: analysisAsync.when(
          data: (analysis) {
            if (analysis == null) {
              return Center(
                child: Text(
                  'No analysis data',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.textDim,
                  ),
                ),
              );
            }

            final conflicts = analysis.conflicts.where((conflict) {
              if (conflict.canAutoResolve) return false;
              return conflict.firstEntry.projectId == projectId ||
                  conflict.secondEntry.projectId == projectId;
            }).toList();

            if (conflicts.isEmpty) {
              return Center(
                child: Text(
                  'No conflicts found',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.textDim,
                  ),
                ),
              );
            }

            return _buildConflictTable(tokens, conflicts);
          },
          loading: () => Center(
            child: CircularProgressIndicator(color: tokens.accent),
          ),
          error: (error, _) => Center(
            child: Text(
              'Error: $error',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.err,
              ),
            ),
          ),
        ),
      ),
      actions: [
        SmallTextButton(
          label: 'Close',
          filled: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildConflictTable(
    TwmtThemeTokens tokens,
    List<CompilationConflict> conflicts,
  ) {
    return SingleChildScrollView(
      child: Table(
        border: TableBorder.all(
          color: tokens.border,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: tokens.panel2,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.radiusSm),
              ),
            ),
            children: [
              _buildHeaderCell(tokens, 'Conflicting Key'),
              _buildHeaderCell(tokens, 'Source Text (This Project)'),
              _buildHeaderCell(tokens, 'Source Text (Conflicting)'),
            ],
          ),
          ...conflicts.map((conflict) {
            final isFirst = conflict.firstEntry.projectId == projectId;
            final thisEntry =
                isFirst ? conflict.firstEntry : conflict.secondEntry;
            final otherEntry =
                isFirst ? conflict.secondEntry : conflict.firstEntry;

            return TableRow(
              children: [
                _buildKeyCell(tokens, conflict.key),
                _buildSourceTextCell(
                  tokens,
                  thisEntry.projectName,
                  thisEntry.sourceText,
                  tokens.accent,
                ),
                _buildSourceTextCell(
                  tokens,
                  otherEntry.projectName,
                  otherEntry.sourceText,
                  tokens.err,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(TwmtThemeTokens tokens, String text) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: tokens.fontBody.copyWith(
            fontSize: 12.5,
            color: tokens.text,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildKeyCell(TwmtThemeTokens tokens, String key) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.top,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          key,
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceTextCell(
    TwmtThemeTokens tokens,
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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                modName,
                style: tokens.fontBody.copyWith(
                  fontSize: 11.5,
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tokens.panel2,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: SelectableText(
                sourceText,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
