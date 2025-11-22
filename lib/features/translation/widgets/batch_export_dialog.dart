import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Dialog for exporting selected units to various file formats
///
/// Supports:
/// - CSV (UTF-8 with BOM for Excel)
/// - Excel (.xlsx)
/// - JSON
/// - .loc format (Total War format)
///
/// Allows selection of:
/// - Which columns to include
/// - Export options (headers, translations only, validated only)
/// - Output file location
class BatchExportDialog extends ConsumerStatefulWidget {
  const BatchExportDialog({
    super.key,
    required this.selectedCount,
    required this.onExport,
  });

  final int selectedCount;
  final Function({
    required String format,
    required String filePath,
    required Set<String> selectedColumns,
    required bool includeHeaders,
    required bool translationsOnly,
    required bool validatedOnly,
    required bool openFolderAfterExport,
  }) onExport;

  @override
  ConsumerState<BatchExportDialog> createState() => _BatchExportDialogState();
}

class _BatchExportDialogState extends ConsumerState<BatchExportDialog> {
  String _selectedFormat = 'csv';
  String? _selectedFilePath;
  bool _includeHeaders = true;
  bool _translationsOnly = false;
  bool _validatedOnly = false;
  bool _openFolderAfterExport = true;

  final Set<String> _selectedColumns = {
    'key',
    'sourceText',
    'translatedText',
    'status',
  };

  final List<String> _availableColumns = [
    'key',
    'sourceText',
    'translatedText',
    'status',
    'notes',
    'confidence',
    'context',
    'createdAt',
    'updatedAt',
  ];

  final Map<String, String> _columnLabels = {
    'key': 'Key',
    'sourceText': 'Source Text',
    'translatedText': 'Translated Text',
    'status': 'Status',
    'notes': 'Notes',
    'confidence': 'Confidence Score',
    'context': 'Context',
    'createdAt': 'Created At',
    'updatedAt': 'Updated At',
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.arrow_export_24_regular,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Export ${widget.selectedCount} Units',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Format selection
                    _buildSection(
                      title: 'Export Format',
                      child: _buildFormatSelector(),
                    ),
                    const SizedBox(height: 20),

                    // Column selection
                    _buildSection(
                      title: 'Columns to Include',
                      child: _buildColumnSelector(),
                    ),
                    const SizedBox(height: 20),

                    // Options
                    _buildSection(
                      title: 'Options',
                      child: _buildOptions(),
                    ),
                    const SizedBox(height: 20),

                    // File picker
                    _buildSection(
                      title: 'Output File',
                      child: _buildFilePicker(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _buildButton(
                  label: 'Export',
                  icon: FluentIcons.arrow_export_24_regular,
                  isPrimary: true,
                  onPressed: _selectedFilePath != null ? _performExport : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildFormatSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _buildFormatChip('CSV', 'csv', FluentIcons.document_24_regular),
        _buildFormatChip('Excel', 'xlsx', FluentIcons.document_table_24_regular),
        _buildFormatChip('JSON', 'json', FluentIcons.braces_24_regular),
        _buildFormatChip('.loc', 'loc', FluentIcons.document_text_24_regular),
      ],
    );
  }

  Widget _buildFormatChip(String label, String value, IconData icon) {
    final isSelected = _selectedFormat == value;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _selectedFormat = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColumnSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableColumns.map((column) {
        return _buildColumnCheckbox(column);
      }).toList(),
    );
  }

  Widget _buildColumnCheckbox(String column) {
    final isSelected = _selectedColumns.contains(column);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedColumns.remove(column);
            } else {
              _selectedColumns.add(column);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected
                    ? FluentIcons.checkbox_checked_24_regular
                    : FluentIcons.checkbox_unchecked_24_regular,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                _columnLabels[column] ?? column,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions() {
    return Column(
      children: [
        if (_selectedFormat == 'csv' || _selectedFormat == 'xlsx')
          _buildCheckbox(
            label: 'Include header row',
            value: _includeHeaders,
            onChanged: (value) => setState(() => _includeHeaders = value!),
          ),
        const SizedBox(height: 8),
        _buildCheckbox(
          label: 'Translations only (exclude pending/empty)',
          value: _translationsOnly,
          onChanged: (value) => setState(() => _translationsOnly = value!),
        ),
        const SizedBox(height: 8),
        _buildCheckbox(
          label: 'Validated only (exclude draft/review)',
          value: _validatedOnly,
          onChanged: (value) => setState(() => _validatedOnly = value!),
        ),
        const SizedBox(height: 8),
        _buildCheckbox(
          label: 'Open folder after export',
          value: _openFolderAfterExport,
          onChanged: (value) => setState(() => _openFolderAfterExport = value!),
        ),
      ],
    );
  }

  Widget _buildFilePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: Text(
                  _selectedFilePath ?? 'No file selected',
                  style: TextStyle(
                    color: _selectedFilePath != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FluentButton(
              onPressed: _pickFile,
              icon: const Icon(FluentIcons.folder_open_24_regular),
              child: const Text('Browse'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    );
  }

  Widget _buildButton({
    required String label,
    IconData? icon,
    bool isPrimary = false,
    VoidCallback? onPressed,
  }) {
    if (isPrimary) {
      return FluentButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    } else {
      return FluentTextButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    }
  }

  Future<void> _pickFile() async {
    String? result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Translation Units',
      fileName: 'translation_export.$_selectedFormat',
      type: FileType.custom,
      allowedExtensions: [_selectedFormat],
    );

    if (result != null) {
      setState(() => _selectedFilePath = result);
    }
  }

  void _performExport() {
    if (_selectedFilePath == null) return;

    widget.onExport(
      format: _selectedFormat,
      filePath: _selectedFilePath!,
      selectedColumns: _selectedColumns,
      includeHeaders: _includeHeaders,
      translationsOnly: _translationsOnly,
      validatedOnly: _validatedOnly,
      openFolderAfterExport: _openFolderAfterExport,
    );

    Navigator.of(context).pop();
  }
}
