import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../models/domain/language.dart';

/// DataGrid data source for language settings
class LanguageSettingsDataSource extends DataGridSource {
  final List<Language> languages;
  final String defaultLanguageCode;
  final BuildContext context;
  final void Function(Language) onSetDefault;
  final void Function(Language) onDelete;

  List<DataGridRow> _dataGridRows = [];

  LanguageSettingsDataSource({
    required this.languages,
    required this.defaultLanguageCode,
    required this.context,
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
              color: isDefault
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          code.toUpperCase(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
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
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Custom',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
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
        context: context,
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
  final BuildContext context;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.context,
    this.isDestructive = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isDestructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;

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
              color: _isHovered
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
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
