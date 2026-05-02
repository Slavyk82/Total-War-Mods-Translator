import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import '../providers/tm_providers.dart';
import '../providers/tm_selection_notifier.dart';
import 'tm_edit_dialog.dart';

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
      onEditEntry: _handleEditEntry,
      onSortChanged: _handleSortChanged,
      onCheckboxTap: _handleCheckboxTap,
      isSelected: _isSelected,
    );
  }

  bool _isSelected(String entryId) {
    return ref.read(tmSelectionProvider).contains(entryId);
  }

  void _handleCheckboxTap(String entryId) {
    ref.read(tmSelectionProvider.notifier).toggle(entryId);
  }

  void _handleSortChanged(String column, bool ascending) {
    // Re-entry guard. Syncfusion re-applies the configured sort on every
    // `notifyListeners()` from the data source: when our refetch lands and
    // `updateEntries` notifies, the grid calls `performSorting` again, which
    // schedules another microtask through this callback with the SAME
    // (column, ascending). Without this guard each call would build a fresh
    // `TmSort` instance — `TmSort` has no value equality — and Riverpod
    // would re-fire `tmEntriesProvider`, looping forever and flickering the
    // grid between loading and data.
    final current = ref.read(tmSortStateProvider);
    if (current.column == column && current.ascending == ascending) return;
    ref.read(tmSortStateProvider.notifier).setSort(column, ascending);
    // Reset to first page when sort changes
    ref.read(tmPageStateProvider.notifier).setPage(1);
  }

  @override
  Widget build(BuildContext context) {
    final filtersState = ref.watch(tmFilterStateProvider);
    final pageState = ref.watch(tmPageStateProvider);
    // sortState is watched inside tmEntriesProvider, no need to watch here

    // Re-render rows whenever the selection set changes so the row checkbox
    // ticks track the provider state.
    ref.listen<Set<String>>(tmSelectionProvider, (_, _) {
      _dataSource.refresh();
      if (mounted) setState(() {});
    });

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
        // Drop any stale ids from a previous page/filter so the selection
        // can't outlive the entries it points to.
        _retainSelectionToVisible(entries);
        return _buildDataGrid(context, entries);
      },
      loading: () => const Center(
        child: FluentSpinner(),
      ),
      error: (error, stack) => _buildError(context, error),
    );
  }

  /// Schedule a post-frame retain so the selection set never references
  /// entry ids that are no longer in the displayed list. Done in a
  /// post-frame callback so we never mutate provider state during a build.
  void _retainSelectionToVisible(List<TranslationMemoryEntry> entries) {
    final ids = entries.map((e) => e.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(tmSelectionProvider.notifier).retain(ids);
    });
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
            t.translationMemory.messages.failedToLoadEntries,
            style: tokens.fontDisplay.copyWith(
              fontSize: 16,
              color: tokens.err,
              fontStyle: tokens.fontDisplayStyle,
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
            columnName: 'checkbox',
            width: 50,
            allowSorting: false,
            label: _buildSelectAllHeader(tokens, entries),
          ),
          GridColumn(
            columnName: 'source',
            label: _headerCell(tokens, t.translationMemory.columns.sourceText, Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'target',
            label: _headerCell(tokens, t.translationMemory.columns.targetText, Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'usage',
            width: 90,
            label: _headerCell(tokens, t.translationMemory.columns.usage, Alignment.centerRight),
          ),
          GridColumn(
            columnName: 'lastUsed',
            width: 120,
            label: _headerCell(tokens, t.translationMemory.columns.lastUsed, Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'actions',
            width: 100,
            allowSorting: false,
            label: _headerCell(tokens, '', Alignment.center),
          ),
        ],
        onCellTap: (details) {
          // Header rows have rowIndex 0; body rows start at 1. The actions
          // and checkbox columns handle their own taps via embedded
          // GestureDetectors.
          if (details.rowColumnIndex.rowIndex <= 0) return;
          if (details.column.columnName == 'actions') return;
          if (details.column.columnName == 'checkbox') return;
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
          if (details.column.columnName == 'checkbox') return;
          final entry =
              _dataSource.rowAt(details.rowColumnIndex.rowIndex - 1);
          if (entry == null) return;
          _handleEditEntry(entry);
        },
      ),
    );
  }

  Widget _buildSelectAllHeader(
    TwmtThemeTokens tokens,
    List<TranslationMemoryEntry> entries,
  ) {
    final selected = ref.watch(tmSelectionProvider);
    final visibleIds = entries.map((e) => e.id).toSet();
    final selectedVisibleCount =
        selected.where(visibleIds.contains).length;
    final bool? value;
    if (selectedVisibleCount == 0) {
      value = false;
    } else if (selectedVisibleCount == visibleIds.length &&
        visibleIds.isNotEmpty) {
      value = true;
    } else {
      value = null;
    }

    void toggle() {
      final notifier = ref.read(tmSelectionProvider.notifier);
      if (value == true) {
        notifier.clear();
      } else {
        notifier.selectAll(visibleIds);
      }
    }

    return Container(
      padding: const EdgeInsets.all(8.0),
      alignment: Alignment.center,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: toggle,
          child: Checkbox(
            value: value,
            tristate: true,
            onChanged: (_) => toggle(),
            activeColor: tokens.accent,
            checkColor: tokens.accentFg,
            side: BorderSide(color: tokens.border, width: 1),
          ),
        ),
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
            t.translationMemory.messages.noEntries,
            style: tokens.fontDisplay.copyWith(
              fontSize: 16,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.translationMemory.messages.importHint,
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

  Future<void> _handleEditEntry(TranslationMemoryEntry entry) async {
    final newTargetText = await showDialog<String>(
      context: context,
      builder: (_) => TmEditDialog(entry: entry),
    );
    if (newTargetText == null || !mounted) return;
    // Optimistic patch: the provider invalidation triggered by the save is
    // racing with the next frame; updating the data source in place avoids
    // a flash of stale data and guarantees the new translation shows up
    // immediately.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _dataSource.patchEntry(
      entry.copyWith(translatedText: newTargetText, updatedAt: now),
    );
  }

  Future<void> _handleDeleteEntry(TranslationMemoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TokenConfirmDialog(
        title: t.translationMemory.dialogs.deleteTmTitle,
        message: t.translationMemory.dialogs.deleteTmMessage,
        warningMessage: t.translationMemory.dialogs.deleteTmWarning,
        confirmLabel: t.common.actions.delete,
        confirmIcon: FluentIcons.delete_24_regular,
        destructive: true,
      ),
    );

    if (confirmed == true && mounted) {
      // Delete the entry using the provider
      final deleteState = ref.read(tmDeleteStateProvider.notifier);
      final success = await deleteState.deleteEntry(entry.id);

      if (mounted) {
        if (success) {
          FluentToast.success(context, t.translationMemory.messages.tmEntryDeletedSuccess);
        } else {
          FluentToast.error(context, t.translationMemory.messages.failedToDeleteTmEntry);
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
    required this.onEditEntry,
    required this.onSortChanged,
    required this.onCheckboxTap,
    required this.isSelected,
  }) {
    _entries = entries;
    _rows = _buildRowsFrom(entries);
  }

  List<TranslationMemoryEntry> _entries = const [];
  List<DataGridRow> _rows = const [];
  final void Function(TranslationMemoryEntry) onDeleteEntry;
  final void Function(TranslationMemoryEntry) onEditEntry;
  final void Function(String column, bool ascending) onSortChanged;
  final void Function(String entryId) onCheckboxTap;
  final bool Function(String entryId) isSelected;

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

  /// Force the grid to re-query [buildRow] without rebuilding the cell list.
  /// Used when only the selection changes — the cells themselves are stable
  /// but their checkbox tick must redraw.
  void refresh() {
    notifyListeners();
  }

  /// Replace a single entry in place and rebuild only the affected row.
  ///
  /// Called as an optimistic update right after the edit dialog confirms a
  /// successful save: the provider invalidation is already in flight, but
  /// patching locally guarantees the grid reflects the change on the very
  /// next frame instead of waiting for the DB roundtrip + refetch. The
  /// upstream refetch will eventually overwrite [_entries] with a new list
  /// that carries the same value, so the patch is idempotent.
  void patchEntry(TranslationMemoryEntry updated) {
    final index = _entries.indexWhere((e) => e.id == updated.id);
    if (index < 0) return;
    final newEntries = List<TranslationMemoryEntry>.from(_entries);
    newEntries[index] = updated;
    _entries = newEntries;
    _rows = _buildRowsFrom(newEntries);
    notifyListeners();
  }

  static List<DataGridRow> _buildRowsFrom(
    List<TranslationMemoryEntry> entries,
  ) {
    return entries
        .map((entry) => DataGridRow(cells: [
              DataGridCell<TranslationMemoryEntry>(
                  columnName: 'checkbox', value: entry),
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
        RepaintBoundary(
          child: _CheckboxCell(
            isSelected: isSelected(entry.id),
            onTap: () => onCheckboxTap(entry.id),
          ),
        ),
        RepaintBoundary(child: _TextCell(text: entry.sourceText)),
        RepaintBoundary(child: _TextCell(text: entry.translatedText)),
        RepaintBoundary(child: _UsageCell(count: entry.usageCount)),
        RepaintBoundary(child: _LastUsedCell(lastUsedAt: entry.lastUsedAt)),
        RepaintBoundary(
          child: _ActionsCell(
            entry: entry,
            onEdit: onEditEntry,
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

class _CheckboxCell extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _CheckboxCell({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Checkbox(
            value: isSelected,
            onChanged: (_) => onTap(),
            activeColor: tokens.accent,
            checkColor: tokens.accentFg,
            side: BorderSide(color: tokens.border, width: 1),
          ),
        ),
      ),
    );
  }
}

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
    final now = ref.watch(clockProvider)();
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
  final void Function(TranslationMemoryEntry) onEdit;
  final void Function(TranslationMemoryEntry) onDelete;

  const _ActionsCell({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmallIconButton(
            icon: FluentIcons.edit_24_regular,
            tooltip: t.translationMemory.messages.editEntry,
            onTap: () => onEdit(entry),
          ),
          const SizedBox(width: 6),
          SmallIconButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: t.translationMemory.messages.deleteEntry,
            foreground: tokens.err,
            background: tokens.errBg,
            borderColor: tokens.err.withValues(alpha: 0.4),
            onTap: () => onDelete(entry),
          ),
        ],
      ),
    );
  }
}
