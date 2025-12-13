import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/import_export_settings.dart' as export_models;
import '../models/export_result.dart';
import '../../../providers/import_export/export_provider.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';

/// Dialog for exporting translations to file
class ExportTranslationsDialog extends ConsumerStatefulWidget {
  final String defaultProjectId;
  final String defaultTargetLanguageId;

  const ExportTranslationsDialog({
    super.key,
    required this.defaultProjectId,
    required this.defaultTargetLanguageId,
  });

  @override
  ConsumerState<ExportTranslationsDialog> createState() =>
      _ExportTranslationsDialogState();
}

class _ExportTranslationsDialogState
    extends ConsumerState<ExportTranslationsDialog> {
  export_models.ExportFormat _selectedFormat = export_models.ExportFormat.csv;
  String _projectId = '';
  String _targetLanguageId = '';
  final Set<export_models.ExportColumn> _selectedColumns = {
    export_models.ExportColumn.key,
    export_models.ExportColumn.sourceText,
    export_models.ExportColumn.targetText,
    export_models.ExportColumn.status,
  };
  String _encoding = 'utf-8';
  bool _includeHeader = true;
  bool _translationsOnly = false;
  bool _validatedOnly = false;
  bool _prettyPrint = true;
  String? _outputPath;

  @override
  void initState() {
    super.initState();
    _projectId = widget.defaultProjectId;
    _targetLanguageId = widget.defaultTargetLanguageId;
  }

  Future<void> _selectOutputPath() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Translations',
      fileName: 'translations.${_getFileExtension(_selectedFormat)}',
      type: FileType.custom,
      allowedExtensions: [_getFileExtension(_selectedFormat)],
    );

    if (result != null) {
      setState(() {
        _outputPath = result;
      });
    }
  }

  String _getFileExtension(export_models.ExportFormat format) {
    switch (format) {
      case export_models.ExportFormat.csv:
        return 'csv';
      case export_models.ExportFormat.json:
        return 'json';
      case export_models.ExportFormat.excel:
        return 'xlsx';
      case export_models.ExportFormat.loc:
        return 'loc';
    }
  }

  Future<void> _loadPreview() async {
    final settings = export_models.ExportSettings(
      format: _selectedFormat,
      projectId: _projectId,
      targetLanguageId: _targetLanguageId,
      columns: _selectedColumns.toList(),
      filterOptions: export_models.ExportFilterOptions(
        translationsOnly: _translationsOnly,
        validatedOnly: _validatedOnly,
      ),
      formatOptions: export_models.ExportFormatOptions(
        includeHeader: _includeHeader,
        prettyPrint: _prettyPrint,
        encoding: _encoding,
      ),
    );

    try {
      await ref.read(exportPreviewDataProvider.notifier).loadPreview(settings);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Failed to load preview: $e');
      }
    }
  }

  Future<void> _executeExport() async {
    if (_outputPath == null) {
      if (mounted) {
        FluentToast.error(context, 'Please select output path');
      }
      return;
    }

    final settings = export_models.ExportSettings(
      format: _selectedFormat,
      projectId: _projectId,
      targetLanguageId: _targetLanguageId,
      columns: _selectedColumns.toList(),
      filterOptions: export_models.ExportFilterOptions(
        translationsOnly: _translationsOnly,
        validatedOnly: _validatedOnly,
      ),
      formatOptions: export_models.ExportFormatOptions(
        includeHeader: _includeHeader,
        prettyPrint: _prettyPrint,
        encoding: _encoding,
      ),
    );

    try {
      await ref
          .read(exportResultDataProvider.notifier)
          .executeExport(settings, _outputPath!);

      if (mounted) {
        FluentToast.success(context, 'Export completed successfully');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Export failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(exportPreviewDataProvider);
    final result = ref.watch(exportResultDataProvider);
    final progress = ref.watch(exportProgressProvider);

    return AlertDialog(
      title: const Text('Export Translations'),
      content: SizedBox(
        width: 600,
        height: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Format selection
              _buildFormatSelection(),
              const SizedBox(height: 24),

              // Column selection
              _buildColumnSelection(),
              const SizedBox(height: 24),

              // Export options
              _buildExportOptions(),
              const SizedBox(height: 24),

              // Output path
              _buildOutputPathSelector(),
              const SizedBox(height: 24),

              // Preview
              if (preview != null) _buildPreview(preview),

              // Progress
              if (progress.isExporting) _buildProgress(progress),

              // Results
              if (result != null) _buildResults(result),
            ],
          ),
        ),
      ),
      actions: [
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FluentOutlinedButton(
          onPressed: _loadPreview,
          icon: const Icon(FluentIcons.eye_24_regular),
          child: const Text('Preview'),
        ),
        FluentButton(
          onPressed: _outputPath != null ? _executeExport : null,
          icon: const Icon(FluentIcons.arrow_export_24_regular),
          child: const Text('Export'),
        ),
      ],
    );
  }

  Widget _buildFormatSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Format',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: export_models.ExportFormat.values.map((format) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFormat = format;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: _selectedFormat == format
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: _selectedFormat == format
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _getFormatIcon(format),
                            size: 32,
                            color: _selectedFormat == format
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            format.name.toUpperCase(),
                            style: TextStyle(
                              fontWeight: _selectedFormat == format
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _getFormatIcon(export_models.ExportFormat format) {
    switch (format) {
      case export_models.ExportFormat.csv:
        return FluentIcons.document_table_24_regular;
      case export_models.ExportFormat.json:
        return FluentIcons.document_24_regular;
      case export_models.ExportFormat.excel:
        return FluentIcons.document_table_24_regular;
      case export_models.ExportFormat.loc:
        return FluentIcons.code_24_regular;
    }
  }

  Widget _buildColumnSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Columns to Export',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: export_models.ExportColumn.values.map((column) {
            final isSelected = _selectedColumns.contains(column);
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (column == export_models.ExportColumn.key) return; // Key is required
                    if (isSelected) {
                      _selectedColumns.remove(column);
                    } else {
                      _selectedColumns.add(column);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _getColumnDisplayName(column),
                    style: TextStyle(
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getColumnDisplayName(export_models.ExportColumn column) {
    switch (column) {
      case export_models.ExportColumn.key:
        return 'Key';
      case export_models.ExportColumn.sourceText:
        return 'Source Text';
      case export_models.ExportColumn.targetText:
        return 'Target Text';
      case export_models.ExportColumn.status:
        return 'Status';
      case export_models.ExportColumn.notes:
        return 'Notes';
      case export_models.ExportColumn.context:
        return 'Context';
      case export_models.ExportColumn.createdAt:
        return 'Created At';
      case export_models.ExportColumn.updatedAt:
        return 'Updated At';
      case export_models.ExportColumn.changedBy:
        return 'Changed By';
    }
  }

  Widget _buildExportOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Export Options',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          title: const Text('Include header row'),
          value: _includeHeader,
          onChanged: (value) {
            setState(() {
              _includeHeader = value ?? true;
            });
          },
        ),
        CheckboxListTile(
          title: const Text('Translations only (exclude untranslated)'),
          value: _translationsOnly,
          onChanged: (value) {
            setState(() {
              _translationsOnly = value ?? false;
            });
          },
        ),
        CheckboxListTile(
          title: const Text('Validated only'),
          value: _validatedOnly,
          onChanged: (value) {
            setState(() {
              _validatedOnly = value ?? false;
            });
          },
        ),
        if (_selectedFormat == export_models.ExportFormat.json)
          CheckboxListTile(
            title: const Text('Pretty print JSON'),
            value: _prettyPrint,
            onChanged: (value) {
              setState(() {
                _prettyPrint = value ?? true;
              });
            },
          ),
        if (_selectedFormat == export_models.ExportFormat.csv)
          DropdownButtonFormField<String>(
            initialValue: _encoding,
            decoration: const InputDecoration(
              labelText: 'Encoding',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
              DropdownMenuItem(value: 'utf-8-bom', child: Text('UTF-8 with BOM')),
              DropdownMenuItem(value: 'utf-16', child: Text('UTF-16')),
            ],
            onChanged: (value) {
              setState(() {
                _encoding = value ?? 'utf-8';
              });
            },
          ),
      ],
    );
  }

  Widget _buildOutputPathSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Output Path',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _selectOutputPath,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.folder_open_24_regular,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _outputPath ?? 'Click to select output path...',
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(ExportPreview preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total rows: ${preview.totalRows}'),
              Text('Estimated size: ${preview.estimatedSizeFormatted}'),
              const SizedBox(height: 12),
              if (preview.previewRows.isNotEmpty) ...[
                const Text('First few rows:'),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: preview.headers
                        .map((header) => DataColumn(label: Text(header)))
                        .toList(),
                    rows: preview.previewRows.take(5).map((row) {
                      return DataRow(
                        cells: preview.headers.map((header) {
                          return DataCell(Text(row[header] ?? ''));
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(ExportProgressState progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exporting...',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        FluentProgressBar(value: progress.progress),
        const SizedBox(height: 4),
        Text('${progress.percentage}% - ${progress.current} of ${progress.total}'),
      ],
    );
  }

  Widget _buildResults(ExportResult result) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: result.isSuccess
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.isSuccess
                    ? FluentIcons.checkmark_24_regular
                    : FluentIcons.dismiss_24_regular,
                color: result.isSuccess ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                result.isSuccess ? 'Export Successful' : 'Export Failed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (result.isSuccess) ...[
            Text('Exported ${result.rowCount} rows'),
            Text('File size: ${result.fileSizeFormatted}'),
            Text('Duration: ${result.durationFormatted}'),
            const SizedBox(height: 8),
            FluentButton(
              onPressed: () {
                final file = File(result.filePath);
                final directory = file.parent.path;
                Process.run('explorer.exe', [directory]);
              },
              icon: const Icon(FluentIcons.folder_open_24_regular),
              child: const Text('Open Folder'),
            ),
          ] else ...[
            Text(result.errorMessage ?? 'Unknown error'),
          ],
        ],
      ),
    );
  }
}
