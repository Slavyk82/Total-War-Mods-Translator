import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import '../../../models/domain/ignored_source_text.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';
import '../providers/ignored_source_texts_providers.dart';
import 'ignored_source_texts_data_source.dart';
import 'ignored_source_text_editor_dialog.dart';

/// DataGrid widget for displaying and managing ignored source texts
class IgnoredSourceTextsDataGrid extends ConsumerStatefulWidget {
  const IgnoredSourceTextsDataGrid({super.key});

  @override
  ConsumerState<IgnoredSourceTextsDataGrid> createState() =>
      _IgnoredSourceTextsDataGridState();
}

class _IgnoredSourceTextsDataGridState
    extends ConsumerState<IgnoredSourceTextsDataGrid> {
  IgnoredSourceTextsDataSource? _dataSource;
  final DataGridController _controller = DataGridController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textsAsync = ref.watch(ignoredSourceTextsProvider);
    final tokens = context.tokens;

    return textsAsync.when(
      data: (texts) {
        // Settings datagrids have small N (<100 rows), and the data source needs
        // `tokens` baked in at construction time. Re-creating on every build is
        // cheap and naturally picks up theme switches without manual invalidation.
        // For larger grids, see `tm_browser_datagrid.dart`'s updateEntries pattern.
        _dataSource = IgnoredSourceTextsDataSource(
          texts: texts,
          tokens: tokens,
          onEdit: _editText,
          onDelete: _deleteText,
          onToggleEnabled: _toggleEnabled,
        );
        return _buildDataGrid(texts, tokens);
      },
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: FluentSpinner()),
      ),
      error: (error, stack) => _buildErrorState(error.toString(), tokens),
    );
  }

  Widget _buildDataGrid(List<IgnoredSourceText> texts, TwmtThemeTokens tokens) {
    if (texts.isEmpty) {
      return _buildEmptyState(tokens);
    }

    return SizedBox(
      height: _calculateGridHeight(texts.length),
      child: SfDataGridTheme(
        data: buildTokenDataGridTheme(tokens),
        child: SfDataGrid(
          source: _dataSource!,
          controller: _controller,
          allowSorting: false,
          columnWidthMode: ColumnWidthMode.fill,
          gridLinesVisibility: GridLinesVisibility.both,
          headerGridLinesVisibility: GridLinesVisibility.both,
          selectionMode: SelectionMode.single,
          rowHeight: 44,
          headerRowHeight: 40,
          columns: [
            GridColumn(
              columnName: 'enabled',
              width: 80,
              label: Container(
                padding: const EdgeInsets.all(8.0),
                alignment: Alignment.center,
                child: Text(
                  'Active',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
              ),
            ),
            GridColumn(
              columnName: 'sourceText',
              label: Container(
                padding: const EdgeInsets.all(8.0),
                alignment: Alignment.centerLeft,
                child: Text(
                  'Source Text',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
              ),
            ),
            GridColumn(
              columnName: 'actions',
              width: 100,
              label: Container(
                padding: const EdgeInsets.all(8.0),
                alignment: Alignment.center,
                child: Text(
                  'Actions',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: tokens.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateGridHeight(int rowCount) {
    // Header height + (row height * row count) + some padding
    const headerHeight = 40.0;
    const rowHeight = 44.0;
    const maxRows = 6;
    const padding = 2.0;

    final displayRows = rowCount > maxRows ? maxRows : rowCount;
    return headerHeight + (rowHeight * displayRows) + padding;
  }

  Widget _buildEmptyState(TwmtThemeTokens tokens) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.text_bullet_list_ltr_24_regular,
              size: 32,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 8),
            Text(
              'No ignored texts defined',
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.textMid,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add source texts to skip during translation',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error, TwmtThemeTokens tokens) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.err),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 32,
              color: tokens.err,
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading ignored texts',
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.err,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editText(IgnoredSourceText text) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => IgnoredSourceTextEditorDialog(existingText: text),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final (success, error) =
          await ref.read(ignoredSourceTextsProvider.notifier).updateText(
                text.id,
                result,
              );

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Text updated successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to update text');
        }
      }
    }
  }

  Future<void> _deleteText(IgnoredSourceText text) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ignored Text'),
        content: Text(
          'Are you sure you want to delete "${text.sourceText}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.tokens.err,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final (success, error) =
          await ref.read(ignoredSourceTextsProvider.notifier).deleteText(text.id);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Text deleted successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to delete text');
        }
      }
    }
  }

  Future<void> _toggleEnabled(IgnoredSourceText text) async {
    final (success, error) =
        await ref.read(ignoredSourceTextsProvider.notifier).toggleEnabled(text.id);

    if (mounted && !success) {
      FluentToast.error(context, error ?? 'Failed to toggle text');
    }
  }
}
