import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import '../providers/glossary_providers.dart';
import 'glossary_entry_editor.dart';
import 'glossary_datagrid_cells.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';

/// DataGrid for displaying and managing glossary entries
class GlossaryDataGrid extends ConsumerStatefulWidget {
  final String glossaryId;

  const GlossaryDataGrid({
    super.key,
    required this.glossaryId,
  });

  @override
  ConsumerState<GlossaryDataGrid> createState() => _GlossaryDataGridState();
}

class _GlossaryDataGridState extends ConsumerState<GlossaryDataGrid> {
  late GlossaryEntryDataSource _dataSource;
  final DataGridController _controller = DataGridController();

  /// Cached list for glossaryIds to avoid recreating on each build
  /// (List comparison is by reference, not content)
  late final List<String> _glossaryIdsList;

  @override
  void initState() {
    super.initState();
    _glossaryIdsList = [widget.glossaryId];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(glossaryFilterStateProvider);
    final entriesAsync = ref.watch(
      filterState.searchText.isEmpty
          ? glossaryEntriesProvider(
              glossaryId: widget.glossaryId,
              targetLanguageCode: filterState.targetLanguage,
            )
          : glossarySearchResultsProvider(
              query: filterState.searchText,
              glossaryIds: _glossaryIdsList,
              targetLanguageCode: filterState.targetLanguage,
            ),
    );

    return entriesAsync.when(
      data: (entries) {
        _dataSource = GlossaryEntryDataSource(
          entries: entries,
          context: context,
          onEdit: _editEntry,
          onDelete: _deleteEntry,
        );
        return _buildDataGrid(entries);
      },
      loading: () => const Center(child: FluentSpinner()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              t.glossary.errors.loadingEntries,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataGrid(List<GlossaryEntry> entries) {
    if (entries.isEmpty) {
      return _buildEmptyState();
    }

    return SfDataGrid(
      source: _dataSource,
      controller: _controller,
      allowSorting: true,
      allowFiltering: false,
      columnWidthMode: ColumnWidthMode.fill,
      gridLinesVisibility: GridLinesVisibility.both,
      headerGridLinesVisibility: GridLinesVisibility.both,
      selectionMode: SelectionMode.single,
      navigationMode: GridNavigationMode.cell,
      columns: [
        GridColumn(
          columnName: 'sourceTerm',
          label: Container(
            padding: const EdgeInsets.all(8.0),
            alignment: Alignment.centerLeft,
            child: Text(
              t.glossary.labels.sourceTerm,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
        GridColumn(
          columnName: 'targetTerm',
          label: Container(
            padding: const EdgeInsets.all(8.0),
            alignment: Alignment.centerLeft,
            child: Text(
              t.glossary.labels.targetTerm,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
        GridColumn(
          columnName: 'caseSensitive',
          width: 140,
          label: Container(
            padding: const EdgeInsets.all(8.0),
            alignment: Alignment.center,
            child: Text(
              t.glossary.labels.caseSensitive,
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
              t.glossary.labels.actions,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final filterState = ref.watch(glossaryFilterStateProvider);
    final hasFilters = filterState.searchText.isNotEmpty ||
        filterState.targetLanguage != null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilters
                ? FluentIcons.search_24_regular
                : FluentIcons.document_text_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters ? t.glossary.empty.noMatchingEntries : t.glossary.empty.noEntriesYet,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters
                ? t.glossary.empty.adjustSearchOrFilters
                : t.glossary.empty.addEntriesToStart,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  void _editEntry(GlossaryEntry entry) {
    showDialog(
      context: context,
      builder: (context) => GlossaryEntryEditorDialog(
        glossaryId: widget.glossaryId,
        entry: entry,
      ),
    );
  }

  Future<void> _deleteEntry(GlossaryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TokenConfirmDialog(
        title: t.glossary.dialogs.deleteEntryTitle,
        message: t.glossary.dialogs.deleteEntryMessage(source: entry.sourceTerm, target: entry.targetTerm),
        confirmLabel: t.common.actions.delete,
        confirmIcon: FluentIcons.delete_24_regular,
        destructive: true,
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(glossaryEntryEditorProvider.notifier).delete(entry.id);

        if (mounted) {
          FluentToast.success(context, t.glossary.messages.entryDeletedSuccess);
        }
      } catch (e) {
        if (mounted) {
          FluentToast.error(context, t.glossary.messages.errorDeletingEntry(error: e));
        }
      }
    }
  }
}

/// Data source for the glossary entries DataGrid
class GlossaryEntryDataSource extends DataGridSource {
  final List<GlossaryEntry> entries;
  final BuildContext context;
  final void Function(GlossaryEntry) onEdit;
  final void Function(GlossaryEntry) onDelete;

  GlossaryEntryDataSource({
    required this.entries,
    required this.context,
    required this.onEdit,
    required this.onDelete,
  }) {
    _buildDataGridRows();
  }

  List<DataGridRow> _dataGridRows = [];

  @override
  List<DataGridRow> get rows => _dataGridRows;

  void _buildDataGridRows() {
    _dataGridRows = entries.map<DataGridRow>((entry) {
      return DataGridRow(cells: [
        DataGridCell<String>(columnName: 'sourceTerm', value: entry.sourceTerm),
        DataGridCell<String>(columnName: 'targetTerm', value: entry.targetTerm),
        DataGridCell<bool>(columnName: 'caseSensitive', value: entry.caseSensitive),
        DataGridCell<GlossaryEntry>(columnName: 'actions', value: entry),
      ]);
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final entry = entries[_dataGridRows.indexOf(row)];
    final cells = row.getCells();

    // Performance: Wrap each cell in RepaintBoundary to isolate repaints
    return DataGridRowAdapter(
      cells: [
        // Source term
        RepaintBoundary(
          child: GlossaryTextCell(text: cells[0].value?.toString() ?? ''),
        ),
        // Target term
        RepaintBoundary(
          child: GlossaryTextCell(text: cells[1].value?.toString() ?? ''),
        ),
        // Case sensitive
        RepaintBoundary(
          child: CaseSensitiveCell(isCaseSensitive: cells[2].value as bool),
        ),
        // Actions
        RepaintBoundary(
          child: GlossaryActionsCell(
            entry: entry,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      ],
    );
  }
}
