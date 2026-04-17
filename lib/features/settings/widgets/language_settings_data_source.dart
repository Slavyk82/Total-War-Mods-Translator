import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../models/domain/language.dart';

/// DataGrid data source for language settings
class LanguageSettingsDataSource extends DataGridSource {
  final List<Language> languages;
  final String defaultLanguageCode;
  final TwmtThemeTokens tokens;
  final void Function(Language) onSetDefault;
  final void Function(Language) onDelete;

  List<DataGridRow> _dataGridRows = [];

  LanguageSettingsDataSource({
    required this.languages,
    required this.defaultLanguageCode,
    required this.tokens,
    required this.onSetDefault,
    required this.onDelete,
  }) {
    _buildDataGridRows();
  }

  void _buildDataGridRows() {
    _dataGridRows = languages.map<DataGridRow>((language) {
      return DataGridRow(cells: [
        DataGridCell<Language>(columnName: 'default', value: language),
        DataGridCell<String>(columnName: 'code', value: language.code),
        DataGridCell<String>(columnName: 'name', value: language.displayName),
        DataGridCell<Language>(columnName: 'actions', value: language),
      ]);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final language = row.getCells()[0].value as Language;

    return DataGridRowAdapter(
      cells: row.getCells().map<Widget>((cell) {
        switch (cell.columnName) {
          case 'default':
            return _buildDefaultCell(language);
          case 'code':
            return _buildCodeCell(cell.value as String);
          case 'name':
            return _buildNameCell(cell.value as String, language.isCustom);
          case 'actions':
            return _buildActionsCell(cell.value as Language);
          default:
            return Container();
        }
      }).toList(),
    );
  }

  Widget _buildDefaultCell(Language language) {
    final isDefault = language.code == defaultLanguageCode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onSetDefault(language),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isDefault
                  ? FluentIcons.radio_button_24_filled
                  : FluentIcons.radio_button_24_regular,
              size: 20,
              color: isDefault ? tokens.accent : tokens.textFaint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeCell(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tokens.panel2,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          code.toUpperCase(),
          style: tokens.fontMono.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.text,
          ),
        ),
      ),
    );
  }

  Widget _buildNameCell(String name, bool isCustom) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Flexible(
            child: Text(
              name,
              style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.accentBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Custom',
                style: tokens.fontBody.copyWith(
                  fontSize: 11,
                  color: tokens.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsCell(Language language) {
    // Only show delete button for custom languages
    if (!language.isCustom) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      child: _ActionButton(
        icon: FluentIcons.delete_24_regular,
        tooltip: 'Delete language',
        onTap: () => onDelete(language),
        isDestructive: true,
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
