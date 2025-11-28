import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import '../providers/tm_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// DataGrid for browsing and managing TM entries
class TmBrowserDataGrid extends ConsumerStatefulWidget {
  const TmBrowserDataGrid({super.key});

  @override
  ConsumerState<TmBrowserDataGrid> createState() => _TmBrowserDataGridState();
}

class _TmBrowserDataGridState extends ConsumerState<TmBrowserDataGrid> {
  late TmDataSource _dataSource;

  @override
  void initState() {
    super.initState();
    _dataSource = TmDataSource(
      entries: const [],
      ref: null,
      onDeleteEntry: _handleDeleteEntry,
      onSortChanged: _handleSortChanged,
    );
  }

  void _handleSortChanged(String column, bool ascending) {
    ref.read(tmSortStateProvider.notifier).setSort(column, ascending);
    // Reset to first page when sort changes
    ref.read(tmPageStateProvider.notifier).setPage(1);
  }

  @override
  Widget build(BuildContext context) {
    final filtersState = ref.watch(tmFilterStateProvider);
    final pageState = ref.watch(tmPageStateProvider);
    // sortState is watched inside tmEntriesProvider, no need to watch here

    // Use search provider when there's search text, otherwise use entries provider
    final entriesAsync = filtersState.searchText.isEmpty
        ? ref.watch(tmEntriesProvider(
            targetLang: filtersState.targetLanguage,
            minQuality: filtersState.effectiveMinQuality,
            page: pageState,
            pageSize: 1000,
          ))
        : ref.watch(tmSearchResultsProvider(
            searchText: filtersState.searchText,
            targetLang: filtersState.targetLanguage,
            limit: 1000,
          ));

    return entriesAsync.when(
      data: (entries) {
        _dataSource = TmDataSource(
          entries: entries,
          ref: ref,
          onDeleteEntry: _handleDeleteEntry,
          onSortChanged: _handleSortChanged,
        );
        return _buildDataGrid(context, entries);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load entries',
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

  Widget _buildDataGrid(BuildContext context, List<TranslationMemoryEntry> entries) {
    if (entries.isEmpty) {
      return _buildEmptyState(context);
    }

    return SfDataGrid(
      source: _dataSource,
      columnWidthMode: ColumnWidthMode.fill,
      gridLinesVisibility: GridLinesVisibility.horizontal,
      headerGridLinesVisibility: GridLinesVisibility.horizontal,
      selectionMode: SelectionMode.single,
      navigationMode: GridNavigationMode.cell,
      allowSorting: true,
      rowHeight: 72,
      headerRowHeight: 56,
      columns: [
        GridColumn(
          columnName: 'quality',
          width: 110,
          label: Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            child: Text(
              'Quality',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        GridColumn(
          columnName: 'source',
          label: Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            child: Text(
              'Source Text',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        GridColumn(
          columnName: 'target',
          label: Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            child: Text(
              'Target Text',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        GridColumn(
          columnName: 'usage',
          width: 100,
          label: Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Text(
              'Usage',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        GridColumn(
          columnName: 'actions',
          width: 100,
          allowSorting: false,
          label: Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Text(
              'Actions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ],
      onCellTap: (details) {
        if (details.rowColumnIndex.rowIndex > 0) {
          final entry = entries[details.rowColumnIndex.rowIndex - 1];
          ref.read(selectedTmEntryProvider.notifier).select(entry);
        }
      },
      onCellDoubleTap: (details) {
        if (details.rowColumnIndex.rowIndex > 0) {
          final entry = entries[details.rowColumnIndex.rowIndex - 1];
          _showDetailsDialog(context, entry);
        }
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.database_24_regular,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No translation memory entries',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Import a TMX file or start translating to build your memory',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(BuildContext context, TranslationMemoryEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Translation Memory Entry Details'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Quality Score', '${entry.qualityPercentage}%'),
                const Divider(),
                _buildDetailRow('Source Text', entry.sourceText),
                const Divider(),
                _buildDetailRow('Target Text', entry.translatedText),
                const Divider(),
                _buildDetailRow('Usage Count', entry.usageCount.toString()),
                const Divider(),
                _buildDetailRow(
                  'Last Used',
                  _formatTimestamp(entry.lastUsedAt),
                ),
                const Divider(),
                _buildDetailRow(
                  'Created',
                  _formatTimestamp(entry.createdAt),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()} years ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()} months ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} days ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hours ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _handleDeleteEntry(TranslationMemoryEntry entry) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete TM Entry'),
        content: const Text(
          'Are you sure you want to delete this translation memory entry? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Delete the entry using the provider
      final deleteState = ref.read(tmDeleteStateProvider.notifier);
      final success = await deleteState.deleteEntry(entry.id);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'TM entry deleted successfully');
        } else {
          FluentToast.error(context, 'Failed to delete TM entry');
        }
      }
    }
  }
}

/// Data source for the TM DataGrid
class TmDataSource extends DataGridSource {
  TmDataSource({
    required List<TranslationMemoryEntry> entries,
    required this.ref,
    required this.onDeleteEntry,
    required this.onSortChanged,
  }) {
    _entries = entries;
    _buildDataGridRows();
  }

  List<TranslationMemoryEntry> _entries = [];
  List<DataGridRow> _dataGridRows = [];
  final WidgetRef? ref;
  final void Function(TranslationMemoryEntry) onDeleteEntry;
  final void Function(String column, bool ascending) onSortChanged;

  void _buildDataGridRows() {
    _dataGridRows = _entries.map<DataGridRow>((entry) {
      return DataGridRow(cells: [
        DataGridCell<TranslationMemoryEntry>(columnName: 'quality', value: entry),
        DataGridCell<TranslationMemoryEntry>(columnName: 'source', value: entry),
        DataGridCell<TranslationMemoryEntry>(columnName: 'target', value: entry),
        DataGridCell<TranslationMemoryEntry>(columnName: 'usage', value: entry),
        DataGridCell<TranslationMemoryEntry>(columnName: 'actions', value: entry),
      ]);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  Future<void> performSorting(List<DataGridRow> rows) async {
    // Server-side sorting: trigger provider update instead of local sort
    if (sortedColumns.isNotEmpty) {
      final sortColumn = sortedColumns.first;
      final ascending = sortColumn.sortDirection == DataGridSortDirection.ascending;
      // Defer state change to avoid modifying provider during build
      Future.microtask(() => onSortChanged(sortColumn.name, ascending));
    }
    // Don't sort locally - data comes pre-sorted from server
  }

  @override
  int compare(DataGridRow? a, DataGridRow? b, SortColumnDetails sortColumn) {
    // Not used since performSorting doesn't call super
    return 0;
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final entry = row.getCells().first.value as TranslationMemoryEntry;

    return DataGridRowAdapter(
      cells: [
        _buildQualityCell(entry),
        _buildTextCell(entry.sourceText, maxLines: 2),
        _buildTextCell(entry.translatedText, maxLines: 2),
        _buildUsageCell(entry),
        _buildActionsCell(entry),
      ],
    );
  }

  Widget _buildQualityCell(TranslationMemoryEntry entry) {
    final quality = entry.qualityScore ?? 0.0;
    final percentage = (quality * 100).toInt();
    final color = _getQualityColor(quality);

    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: quality,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCell(String text, {int maxLines = 2}) {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildUsageCell(TranslationMemoryEntry entry) {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            entry.usageCount.toString(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.usageCount == 1 ? 'time' : 'times',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCell(TranslationMemoryEntry entry) {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: FluentIcons.copy_24_regular,
            tooltip: 'Copy',
            onPressed: () => _copyEntry(entry),
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: 'Delete',
            onPressed: () => _deleteEntry(entry),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  void _copyEntry(TranslationMemoryEntry entry) {
    Clipboard.setData(ClipboardData(
      text: 'Source: ${entry.sourceText}\nTarget: ${entry.translatedText}',
    ));
  }

  void _deleteEntry(TranslationMemoryEntry entry) {
    onDeleteEntry(entry);
  }

  Color _getQualityColor(double quality) {
    if (quality >= 0.9) {
      return Colors.green;
    } else if (quality >= 0.7) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}

/// Action button widget for the actions column
class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDestructive;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isDestructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isHovered ? color.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
