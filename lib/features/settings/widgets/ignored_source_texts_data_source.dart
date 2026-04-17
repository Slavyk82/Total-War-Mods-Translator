import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../models/domain/ignored_source_text.dart';

/// DataGrid data source for ignored source texts
class IgnoredSourceTextsDataSource extends DataGridSource {
  final List<IgnoredSourceText> texts;
  final TwmtThemeTokens tokens;
  final void Function(IgnoredSourceText) onEdit;
  final void Function(IgnoredSourceText) onDelete;
  final void Function(IgnoredSourceText) onToggleEnabled;

  List<DataGridRow> _dataGridRows = [];

  IgnoredSourceTextsDataSource({
    required this.texts,
    required this.tokens,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  }) {
    _buildDataGridRows();
  }

  void _buildDataGridRows() {
    _dataGridRows = texts.map<DataGridRow>((text) {
      return DataGridRow(cells: [
        DataGridCell<bool>(columnName: 'enabled', value: text.isEnabled),
        DataGridCell<String>(columnName: 'sourceText', value: text.sourceText),
        DataGridCell<IgnoredSourceText>(columnName: 'actions', value: text),
      ]);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final text = texts.firstWhere(
      (t) => t.sourceText == row.getCells()[1].value,
      orElse: () => texts.first,
    );

    return DataGridRowAdapter(
      cells: row.getCells().map<Widget>((cell) {
        switch (cell.columnName) {
          case 'enabled':
            return _buildEnabledCell(text);
          case 'sourceText':
            return _buildSourceTextCell(cell.value as String);
          case 'actions':
            return _buildActionsCell(cell.value as IgnoredSourceText);
          default:
            return Container();
        }
      }).toList(),
    );
  }

  Widget _buildEnabledCell(IgnoredSourceText text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onToggleEnabled(text),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              text.isEnabled
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
              size: 20,
              color: text.isEnabled ? tokens.accent : tokens.textFaint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceTextCell(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: tokens.fontMono.copyWith(
              fontSize: 13,
              color: tokens.text,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildActionsCell(IgnoredSourceText text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: FluentIcons.edit_24_regular,
            tooltip: 'Edit',
            onTap: () => onEdit(text),
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: 'Delete',
            onTap: () => onDelete(text),
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

/// Action button with hover effect following Fluent Design
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = widget.isDestructive ? tokens.err : tokens.text;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isHovered ? tokens.accentBg : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: _isHovered ? color : color.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
