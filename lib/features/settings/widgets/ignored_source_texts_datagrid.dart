import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
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
  late IgnoredSourceTextsDataSource _dataSource;
  final DataGridController _controller = DataGridController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textsAsync = ref.watch(ignoredSourceTextsProvider);

    return textsAsync.when(
      data: (texts) {
        _dataSource = IgnoredSourceTextsDataSource(
          texts: texts,
          context: context,
          onEdit: _editText,
          onDelete: _deleteText,
          onToggleEnabled: _toggleEnabled,
        );
        return _buildDataGrid(texts);
      },
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: FluentSpinner()),
      ),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildDataGrid(List<IgnoredSourceText> texts) {
    if (texts.isEmpty) {
      return _buildEmptyState();
    }

    return SizedBox(
      height: _calculateGridHeight(texts.length),
      child: SfDataGrid(
        source: _dataSource,
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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
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
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        ],
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

  Widget _buildEmptyState() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.text_bullet_list_ltr_24_regular,
              size: 32,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No ignored texts defined',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add source texts to skip during translation',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 32,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading ignored texts',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
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
              backgroundColor: Theme.of(context).colorScheme.error,
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
