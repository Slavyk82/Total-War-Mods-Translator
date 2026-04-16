import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/status_pill.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';

/// Dense-list grid for browsing glossaries.
///
/// Migrated from the legacy card layout to the §7.1 dense-list archetype
/// backed by a tokenised [SfDataGrid]. A row tap delegates to
/// [onGlossaryTap] which the screen uses to switch to the inline entry
/// editor view. The delete trailing action calls [onDeleteGlossary]. All
/// chrome (grid theme, cell backgrounds, pills, delete action) reads from
/// [TwmtThemeTokens]; no `Theme.of(context).colorScheme` or hard-coded
/// hex values remain here.
class GlossaryList extends ConsumerStatefulWidget {
  final List<Glossary> glossaries;
  final Map<String, GameInstallation> gameInstallations;
  final void Function(Glossary glossary)? onGlossaryTap;
  final void Function(Glossary glossary)? onDeleteGlossary;

  const GlossaryList({
    super.key,
    required this.glossaries,
    this.gameInstallations = const {},
    this.onGlossaryTap,
    this.onDeleteGlossary,
  });

  @override
  ConsumerState<GlossaryList> createState() => _GlossaryListState();
}

class _GlossaryListState extends ConsumerState<GlossaryList> {
  late _GlossaryDataSource _dataSource;

  @override
  void initState() {
    super.initState();
    _dataSource = _buildDataSource();
  }

  @override
  void didUpdateWidget(covariant GlossaryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed the Syncfusion data source whenever the upstream list, the
    // game-installation map, or the delete callback identity changes.
    if (oldWidget.glossaries != widget.glossaries ||
        oldWidget.gameInstallations != widget.gameInstallations ||
        oldWidget.onDeleteGlossary != widget.onDeleteGlossary) {
      _dataSource = _buildDataSource();
    }
  }

  _GlossaryDataSource _buildDataSource() => _GlossaryDataSource(
        glossaries: widget.glossaries,
        gameInstallations: widget.gameInstallations,
        onDelete: widget.onDeleteGlossary,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (widget.glossaries.isEmpty) {
      return const SizedBox.shrink();
    }

    return SfDataGridTheme(
      data: buildTokenDataGridTheme(tokens),
      child: SfDataGrid(
        source: _dataSource,
        allowSorting: false,
        allowFiltering: false,
        columnWidthMode: ColumnWidthMode.fill,
        gridLinesVisibility: GridLinesVisibility.horizontal,
        headerGridLinesVisibility: GridLinesVisibility.horizontal,
        selectionMode: SelectionMode.single,
        navigationMode: GridNavigationMode.cell,
        rowHeight: 48,
        headerRowHeight: 32,
        onCellTap: (details) {
          // Header rows have rowIndex 0; body rows start at 1. The action
          // column handles its own taps via the embedded GestureDetector.
          if (details.rowColumnIndex.rowIndex <= 0) return;
          if (details.column.columnName == 'actions') return;
          // Resolve the row via the data source rather than indexing the
          // upstream list by `rowIndex - 1`. This insulates the callback
          // from any future header/frozen-row arithmetic drift.
          final glossary =
              _dataSource.glossaryAtRow(details.rowColumnIndex.rowIndex - 1);
          if (glossary == null) return;
          widget.onGlossaryTap?.call(glossary);
        },
        columns: [
          GridColumn(
            columnName: 'name',
            columnWidthMode: ColumnWidthMode.fill,
            label: _headerCell(tokens, 'NAME', Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'type',
            width: 180,
            label: _headerCell(tokens, 'TYPE', Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'entries',
            width: 100,
            label: _headerCell(tokens, 'ENTRIES', Alignment.centerRight),
          ),
          GridColumn(
            columnName: 'updated',
            width: 140,
            label: _headerCell(tokens, 'UPDATED', Alignment.centerLeft),
          ),
          GridColumn(
            columnName: 'actions',
            width: 72,
            label: _headerCell(tokens, '', Alignment.center),
          ),
        ],
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
}

// =============================================================================
// Data source
// =============================================================================

class _GlossaryDataSource extends DataGridSource {
  _GlossaryDataSource({
    required this.glossaries,
    required this.gameInstallations,
    required this.onDelete,
  }) {
    _rows = glossaries
        .map((g) => DataGridRow(cells: [
              DataGridCell<Glossary>(columnName: 'name', value: g),
              DataGridCell<Glossary>(columnName: 'type', value: g),
              DataGridCell<int>(columnName: 'entries', value: g.entryCount),
              DataGridCell<int>(columnName: 'updated', value: g.updatedAt),
              DataGridCell<Glossary>(columnName: 'actions', value: g),
            ]))
        .toList();
  }

  final List<Glossary> glossaries;
  final Map<String, GameInstallation> gameInstallations;
  final void Function(Glossary glossary)? onDelete;

  List<DataGridRow> _rows = const [];

  @override
  List<DataGridRow> get rows => _rows;

  /// Resolve the [Glossary] backing the row at [rowIndex] inside [rows]
  /// (NOT the grid's absolute row index — callers must already subtract
  /// the header row). Returns `null` when the index is out of range so
  /// grid callbacks can fail silently on stale taps.
  Glossary? glossaryAtRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return null;
    final value = _rows[rowIndex].getCells().first.value;
    return value is Glossary ? value : null;
  }

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    // O(1) lookup: the first cell of every row carries the [Glossary] as
    // its typed `value`, which avoids the O(n) `_rows.indexOf(row)` scan
    // that would otherwise run on every rebuild.
    final glossary = row.getCells().first.value as Glossary?;
    if (glossary == null) return null;
    final gameName = glossary.gameInstallationId == null
        ? null
        : gameInstallations[glossary.gameInstallationId]?.gameName;

    return DataGridRowAdapter(
      cells: [
        RepaintBoundary(child: _NameCell(glossary: glossary)),
        RepaintBoundary(
          child: _TypeCell(glossary: glossary, gameName: gameName),
        ),
        RepaintBoundary(child: _EntriesCell(count: glossary.entryCount)),
        RepaintBoundary(child: _UpdatedCell(updatedAt: glossary.updatedAt)),
        RepaintBoundary(
          child: _ActionsCell(
            glossary: glossary,
            onDelete: onDelete,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Cells
// =============================================================================

class _NameCell extends StatelessWidget {
  final Glossary glossary;
  const _NameCell({required this.glossary});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final description = glossary.description;
    final hasDescription = description != null && description.isNotEmpty;

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            glossary.isGlobal
                ? FluentIcons.globe_24_regular
                : FluentIcons.games_24_regular,
            size: 16,
            color: tokens.textMid,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  glossary.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasDescription) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.fontBody.copyWith(
                      fontSize: 11.5,
                      color: tokens.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeCell extends StatelessWidget {
  final Glossary glossary;
  final String? gameName;

  const _TypeCell({required this.glossary, required this.gameName});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isUniversal = glossary.isGlobal;
    final label =
        isUniversal ? 'UNIVERSAL' : (gameName ?? 'GAME-SPECIFIC').toUpperCase();

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: StatusPill(
          label: label,
          icon: isUniversal
              ? FluentIcons.globe_24_regular
              : FluentIcons.games_24_regular,
          foreground: isUniversal ? tokens.accent : tokens.textMid,
          // The game-specific pill uses `tokens.bg` (not `tokens.panel2`)
          // because the grid theme sets `rowHoverColor: tokens.panel2`.
          // Matching both values would make the pill disappear on hover
          // in the Forge palette.
          background: isUniversal ? tokens.accentBg : tokens.bg,
          tooltip:
              isUniversal ? 'Shared across every game' : 'Scoped to this game',
        ),
      ),
    );
  }
}

class _EntriesCell extends StatelessWidget {
  final int count;
  const _EntriesCell({required this.count});

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

class _UpdatedCell extends ConsumerWidget {
  final int updatedAt;
  const _UpdatedCell({required this.updatedAt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final now = ref.watch(clockProvider).call();
    final date = DateTime.fromMillisecondsSinceEpoch(updatedAt);
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
  final Glossary glossary;
  final void Function(Glossary glossary)? onDelete;

  const _ActionsCell({required this.glossary, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (onDelete == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: 'Delete glossary',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDelete!(glossary),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.errBg,
                border: Border.all(color: tokens.err.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              child: Icon(
                FluentIcons.delete_24_regular,
                size: 14,
                color: tokens.err,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
