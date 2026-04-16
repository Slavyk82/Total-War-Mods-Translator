import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import '../providers/tm_providers.dart';

/// Tokenised [SfDataGrid] for browsing Translation Memory entries.
///
/// Part of the §7.1 dense-list archetype (Plan 5a · Task 6). Mirrors the
/// Glossary dense-list pattern hardened in commit d1d4e89:
///  - Syncfusion theme sourced from [buildTokenDataGridTheme] so row hover,
///    selection and grid-line colours track [TwmtThemeTokens].
///  - Row-value lookup is O(1) (`row.getCells().first.value`), not
///    `_rows.indexOf(row)`.
///  - `onCellTap`/`onCellDoubleTap` resolve the entry via the data source's
///    [_TmDataSource.rowAt] helper so screen-side list arithmetic cannot
///    drift from the grid's header offset.
class TmBrowserDataGrid extends ConsumerStatefulWidget {
  const TmBrowserDataGrid({super.key});

  @override
  ConsumerState<TmBrowserDataGrid> createState() => _TmBrowserDataGridState();
}

class _TmBrowserDataGridState extends ConsumerState<TmBrowserDataGrid> {
  late final _TmDataSource _dataSource;

  @override
  void initState() {
    super.initState();
    _dataSource = _TmDataSource(
      entries: const [],
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
        // Reuse the single [_TmDataSource] allocated in [initState] — a
        // fresh instance per build would re-allocate the entire `_rows`
        // list on every hover/tick rebuild, which is O(N) in entries and
        // noticeable at TM scale (thousands of rows). `updateEntries` is
        // a no-op when the upstream list reference hasn't changed.
        _dataSource.updateEntries(entries);
        return _buildDataGrid(context, entries);
      },
      loading: () => const Center(
        child: FluentSpinner(),
      ),
      error: (error, stack) => _buildError(context, error),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: tokens.err,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load entries',
            style: tokens.fontDisplay.copyWith(
              fontSize: 16,
              color: tokens.err,
              fontStyle:
                  tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDataGrid(
      BuildContext context, List<TranslationMemoryEntry> entries) {
    if (entries.isEmpty) {
      return _buildEmptyState(context);
    }

    final tokens = context.tokens;
    return SfDataGridTheme(
      data: buildTokenDataGridTheme(tokens),
      child: SfDataGrid(
        source: _dataSource,
        columnWidthMode: ColumnWidthMode.fill,
        gridLinesVisibility: GridLinesVisibility.horizontal,
        headerGridLinesVisibility: GridLinesVisibility.horizontal,
        selectionMode: SelectionMode.single,
        navigationMode: GridNavigationMode.cell,
        allowSorting: true,
        rowHeight: 48,
        headerRowHeight: 32,
        columns: [
          GridColumn(
            columnName: 'source',
            label: _headerCell(tokens, 'SOURCE TEXT', Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'target',
            label: _headerCell(tokens, 'TARGET TEXT', Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'usage',
            width: 90,
            label: _headerCell(tokens, 'USAGE', Alignment.centerRight),
          ),
          GridColumn(
            columnName: 'lastUsed',
            width: 120,
            label: _headerCell(tokens, 'LAST USED', Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'actions',
            width: 88,
            allowSorting: false,
            label: _headerCell(tokens, '', Alignment.center),
          ),
        ],
        onCellTap: (details) {
          // Header rows have rowIndex 0; body rows start at 1. The actions
          // column handles its own taps via embedded GestureDetectors.
          if (details.rowColumnIndex.rowIndex <= 0) return;
          if (details.column.columnName == 'actions') return;
          // Resolve the row via the data source rather than subtracting
          // header offsets from the upstream entries list. This keeps
          // callbacks insulated from any future frozen-row arithmetic
          // drift (mirrors the Glossary Task 5 hardening).
          final entry =
              _dataSource.rowAt(details.rowColumnIndex.rowIndex - 1);
          if (entry == null) return;
          ref.read(selectedTmEntryProvider.notifier).select(entry);
        },
        onCellDoubleTap: (details) {
          if (details.rowColumnIndex.rowIndex <= 0) return;
          if (details.column.columnName == 'actions') return;
          final entry =
              _dataSource.rowAt(details.rowColumnIndex.rowIndex - 1);
          if (entry == null) return;
          _showDetailsDialog(context, entry);
        },
      ),
    );
  }

  Widget _headerCell(TwmtThemeTokens tokens, String label, Alignment align) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: align,
      child: Text(
        label,
        style: tokens.fontMono.copyWith(
          fontSize: 11,
          color: tokens.textDim,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.database_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'No translation memory entries',
            style: tokens.fontDisplay.copyWith(
              fontSize: 16,
              color: tokens.text,
              fontStyle:
                  tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Import a TMX file or start translating to build your memory',
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
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
                _buildDetailRow(context, 'Source Text', entry.sourceText),
                const Divider(),
                _buildDetailRow(context, 'Target Text', entry.translatedText),
                const Divider(),
                _buildDetailRow(
                    context, 'Usage Count', entry.usageCount.toString()),
                const Divider(),
                _buildDetailRow(
                  context,
                  'Last Used',
                  _formatTimestamp(entry.lastUsedAt),
                ),
                const Divider(),
                _buildDetailRow(
                  context,
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

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tokens.fontMono.copyWith(
              fontSize: 11,
              color: tokens.textDim,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return formatAbsoluteDate(date) ?? '';
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

// =============================================================================
// Data source
// =============================================================================

/// Syncfusion data source for the Translation Memory grid.
///
/// Stores the [TranslationMemoryEntry] as the typed value of the first cell so
/// both [buildRow] and the [rowAt] helper can resolve it in O(1) — avoiding
/// the O(n) `_rows.indexOf(row)` scan on every rebuild.
class _TmDataSource extends DataGridSource {
  _TmDataSource({
    required List<TranslationMemoryEntry> entries,
    required this.onDeleteEntry,
    required this.onSortChanged,
  }) {
    _entries = entries;
    _rows = _buildRowsFrom(entries);
  }

  List<TranslationMemoryEntry> _entries = const [];
  List<DataGridRow> _rows = const [];
  final void Function(TranslationMemoryEntry) onDeleteEntry;
  final void Function(String column, bool ascending) onSortChanged;

  @override
  List<DataGridRow> get rows => _rows;

  /// Reseed the data source when the upstream entries list has changed.
  ///
  /// Uses [identical] rather than `==` so the common hover/tick rebuilds
  /// (which hand us the same list instance) are a true no-op. Callers can
  /// invoke this every [build] without fear of O(N) churn.
  void updateEntries(List<TranslationMemoryEntry> entries) {
    if (identical(_entries, entries)) return;
    _entries = entries;
    _rows = _buildRowsFrom(entries);
    notifyListeners();
  }

  static List<DataGridRow> _buildRowsFrom(
    List<TranslationMemoryEntry> entries,
  ) {
    return entries
        .map((entry) => DataGridRow(cells: [
              DataGridCell<TranslationMemoryEntry>(
                  columnName: 'source', value: entry),
              DataGridCell<TranslationMemoryEntry>(
                  columnName: 'target', value: entry),
              DataGridCell<int>(columnName: 'usage', value: entry.usageCount),
              DataGridCell<int>(
                  columnName: 'lastUsed', value: entry.lastUsedAt),
              DataGridCell<TranslationMemoryEntry>(
                  columnName: 'actions', value: entry),
            ]))
        .toList();
  }

  /// Resolve the [TranslationMemoryEntry] backing the row at [rowIndex]
  /// inside [rows] (NOT the grid's absolute row index — callers must already
  /// subtract the header row). Returns `null` when the index is out of
  /// range so stale taps fail silently.
  TranslationMemoryEntry? rowAt(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return null;
    final value = _rows[rowIndex].getCells().first.value;
    return value is TranslationMemoryEntry ? value : null;
  }

  @override
  Future<void> performSorting(List<DataGridRow> rows) async {
    // Server-side sorting: trigger provider update instead of local sort
    if (sortedColumns.isNotEmpty) {
      final sortColumn = sortedColumns.first;
      final ascending =
          sortColumn.sortDirection == DataGridSortDirection.ascending;
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
  DataGridRowAdapter? buildRow(DataGridRow row) {
    // O(1) lookup: the first cell carries the entry as its typed value.
    final entry = row.getCells().first.value as TranslationMemoryEntry?;
    if (entry == null) return null;

    return DataGridRowAdapter(
      cells: [
        RepaintBoundary(child: _TextCell(text: entry.sourceText)),
        RepaintBoundary(child: _TextCell(text: entry.translatedText)),
        RepaintBoundary(child: _UsageCell(count: entry.usageCount)),
        RepaintBoundary(child: _LastUsedCell(lastUsedAt: entry.lastUsedAt)),
        RepaintBoundary(
          child: _ActionsCell(
            entry: entry,
            onDelete: onDeleteEntry,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Cells
// =============================================================================

class _TextCell extends StatelessWidget {
  final String text;
  const _TextCell({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
      ),
    );
  }
}

class _UsageCell extends StatelessWidget {
  final int count;
  const _UsageCell({required this.count});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        count.toString(),
        style: tokens.fontMono.copyWith(fontSize: 12.5, color: tokens.textMid),
      ),
    );
  }
}

class _LastUsedCell extends ConsumerWidget {
  final int lastUsedAt;
  const _LastUsedCell({required this.lastUsedAt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    // [TranslationMemoryEntry.lastUsedAt] is a Unix seconds timestamp.
    final date = DateTime.fromMillisecondsSinceEpoch(lastUsedAt * 1000);
    final now = ref.watch(clockProvider).call();
    final relative = formatRelativeSince(date, now: now) ?? '—';
    final absolute = formatAbsoluteDate(date);

    final label = Text(
      relative,
      style: tokens.fontMono.copyWith(fontSize: 12, color: tokens.textDim),
    );

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: absolute == null
          ? label
          : Tooltip(
              message: absolute,
              waitDuration: const Duration(milliseconds: 400),
              child: label,
            ),
    );
  }
}

class _ActionsCell extends StatelessWidget {
  final TranslationMemoryEntry entry;
  final void Function(TranslationMemoryEntry) onDelete;

  const _ActionsCell({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconAction(
            icon: FluentIcons.copy_24_regular,
            tooltip: 'Copy',
            foreground: tokens.textMid,
            background: tokens.panel2,
            borderColor: tokens.border,
            onTap: () => _copyEntry(entry),
          ),
          const SizedBox(width: 6),
          _IconAction(
            icon: FluentIcons.delete_24_regular,
            tooltip: 'Delete entry',
            foreground: tokens.err,
            background: tokens.errBg,
            borderColor: tokens.err.withValues(alpha: 0.4),
            onTap: () => onDelete(entry),
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
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    required this.background,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(icon, size: 14, color: foreground),
          ),
        ),
      ),
    );
  }
}
