import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../models/domain/llm_custom_rule.dart';

/// DataGrid data source for LLM custom rules
class LlmCustomRulesDataSource extends DataGridSource {
  final List<LlmCustomRule> rules;
  final TwmtThemeTokens tokens;
  final void Function(LlmCustomRule) onEdit;
  final void Function(LlmCustomRule) onDelete;
  final void Function(LlmCustomRule) onToggleEnabled;

  List<DataGridRow> _dataGridRows = [];

  LlmCustomRulesDataSource({
    required this.rules,
    required this.tokens,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  }) {
    _buildDataGridRows();
  }

  void _buildDataGridRows() {
    _dataGridRows = rules.map<DataGridRow>((rule) {
      return DataGridRow(cells: [
        DataGridCell<bool>(columnName: 'enabled', value: rule.isEnabled),
        DataGridCell<String>(columnName: 'ruleText', value: rule.ruleText),
        DataGridCell<LlmCustomRule>(columnName: 'actions', value: rule),
      ]);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final rule = rules.firstWhere(
      (r) => r.ruleText == row.getCells()[1].value,
      orElse: () => rules.first,
    );

    return DataGridRowAdapter(
      cells: row.getCells().map<Widget>((cell) {
        switch (cell.columnName) {
          case 'enabled':
            return _buildEnabledCell(rule);
          case 'ruleText':
            return _buildRuleTextCell(cell.value as String);
          case 'actions':
            return _buildActionsCell(cell.value as LlmCustomRule);
          default:
            return Container();
        }
      }).toList(),
    );
  }

  Widget _buildEnabledCell(LlmCustomRule rule) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onToggleEnabled(rule),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              rule.isEnabled
                  ? FluentIcons.checkbox_checked_24_filled
                  : FluentIcons.checkbox_unchecked_24_regular,
              size: 20,
              color: rule.isEnabled ? tokens.accent : tokens.textFaint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuleTextCell(String text) {
    // Truncate long text and show full text in tooltip
    final displayText = text.length > 100 ? '${text.substring(0, 100)}...' : text;
    final isMultiLine = text.contains('\n');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 500),
        child: Text(
          isMultiLine ? displayText.replaceAll('\n', ' ') : displayText,
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }

  Widget _buildActionsCell(LlmCustomRule rule) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: FluentIcons.edit_24_regular,
            tooltip: 'Edit rule',
            onTap: () => onEdit(rule),
          ),
          const SizedBox(width: 4),
          _ActionButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: 'Delete rule',
            onTap: () => onDelete(rule),
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
