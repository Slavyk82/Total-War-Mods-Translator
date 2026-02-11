import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../services/pack_import_service.dart';

/// Dialog for importing translations from a .pack file
class PackImportDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final PackImportService importService;
  final VoidCallback? onImportComplete;

  const PackImportDialog({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.importService,
    this.onImportComplete,
  });

  @override
  ConsumerState<PackImportDialog> createState() => _PackImportDialogState();
}

class _PackImportDialogState extends ConsumerState<PackImportDialog> {
  PackImportPreview? _preview;
  bool _isLoading = false;
  bool _isImporting = false;
  String? _errorMessage;
  String? _selectedFilePath;
  bool _overwriteExisting = true;
  Set<String> _selectedKeys = {};
  _PackImportDataSource? _dataSource;

  // Progress tracking
  int _importCurrent = 0;
  int _importTotal = 0;
  String _importMessage = '';
  bool _isCancelled = false;

  Future<void> _selectFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pack'],
      dialogTitle: 'Select a .pack file',
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _preview = null;
        _errorMessage = null;
        _dataSource = null;
      });
      await _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await widget.importService.previewImport(
      packFilePath: _selectedFilePath!,
      projectId: widget.projectId,
      languageId: widget.languageId,
    );

    setState(() {
      _isLoading = false;
      if (result.isOk) {
        _preview = result.unwrap();
        // Select all matching entries by default
        _selectedKeys = _preview!.matchingEntries.map((e) => e.key).toSet();
        // Create data source for the grid
        _dataSource = _PackImportDataSource(
          entries: _preview!.matchingEntries,
          selectedKeys: _selectedKeys,
          onSelectionChanged: (key, selected) {
            setState(() {
              if (selected) {
                _selectedKeys.add(key);
              } else {
                _selectedKeys.remove(key);
              }
            });
          },
        );
      } else {
        _errorMessage = result.unwrapErr();
      }
    });
  }

  Future<void> _executeImport() async {
    if (_preview == null || _selectedKeys.isEmpty) return;

    setState(() {
      _isImporting = true;
      _isCancelled = false;
      _errorMessage = null;
      _importCurrent = 0;
      _importTotal = _selectedKeys.length;
      _importMessage = 'Starting import...';
    });

    final entriesToImport = _preview!.matchingEntries
        .where((e) => _selectedKeys.contains(e.key))
        .toList();

    final result = await widget.importService.executeImport(
      entriesToImport: entriesToImport,
      projectId: widget.projectId,
      languageId: widget.languageId,
      overwriteExisting: _overwriteExisting,
      onProgress: (current, total, message) {
        if (mounted) {
          setState(() {
            _importCurrent = current;
            _importTotal = total;
            _importMessage = message;
          });
        }
      },
      isCancelled: () => _isCancelled,
    );

    setState(() {
      _isImporting = false;
    });

    if (result.isOk) {
      final importResult = result.unwrap();
      if (mounted) {
        // Capture ScaffoldMessenger before closing dialog
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        // If cancelled, don't close automatically
        if (_isCancelled) {
          _showResultSnackBar(scaffoldMessenger, importResult);
          widget.onImportComplete?.call();
        } else {
          Navigator.of(context).pop();
          widget.onImportComplete?.call();
          _showResultSnackBar(scaffoldMessenger, importResult);
        }
      }
    } else {
      setState(() {
        _errorMessage = result.unwrapErr();
      });
    }
  }

  void _cancelImport() {
    setState(() {
      _isCancelled = true;
      _importMessage = 'Cancelling...';
    });
  }

  void _showResultSnackBar(ScaffoldMessengerState scaffoldMessenger, PackImportResult result) {
    final message = StringBuffer();
    message.write('Import complete: ${result.importedCount} translation(s) imported');
    if (result.skippedCount > 0) {
      message.write(', ${result.skippedCount} skipped');
    }
    if (result.errorCount > 0) {
      message.write(', ${result.errorCount} error(s)');
    }

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message.toString()),
        backgroundColor: result.hasErrors ? Colors.orange : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedKeys.length == _preview!.matchingEntries.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys = _preview!.matchingEntries.map((e) => e.key).toSet();
      }
      _dataSource?.updateSelection(_selectedKeys);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _preview != null &&
        _selectedKeys.length == _preview!.matchingEntries.length;

    return Dialog(
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(FluentIcons.arrow_import_24_regular, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Import translations from a .pack file',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FluentIconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // File selection
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _selectedFilePath ?? 'No file selected',
                      style: TextStyle(
                        color: _selectedFilePath == null
                            ? Theme.of(context).hintColor
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading || _isImporting ? null : _selectFile,
                  icon: const Icon(FluentIcons.folder_open_24_regular, size: 18),
                  label: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.warning_24_regular,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Loading indicator
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Analyzing pack file...'),
                    ],
                  ),
                ),
              ),

            // Preview content
            if (!_isLoading && _preview != null) ...[
              // Summary
              _buildSummary(),
              const SizedBox(height: 16),

              // Options
              Row(
                children: [
                  Checkbox(
                    value: _overwriteExisting,
                    onChanged: (value) {
                      setState(() {
                        _overwriteExisting = value ?? true;
                      });
                    },
                  ),
                  const Text('Overwrite existing translations'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _toggleSelectAll,
                    icon: Icon(
                      allSelected
                          ? FluentIcons.checkbox_unchecked_24_regular
                          : FluentIcons.checkbox_checked_24_regular,
                      size: 18,
                    ),
                    label: Text(allSelected ? 'Deselect all' : 'Select all'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Entries grid using Syncfusion DataGrid
              Expanded(child: _buildEntriesGrid()),
            ],

            // No file selected placeholder
            if (!_isLoading && _preview == null && _errorMessage == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.document_add_24_regular,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Select a .pack file containing translations',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Progress indicator during import
            if (_isImporting) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _importMessage,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _importTotal > 0 ? _importCurrent / _importTotal : 0,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_importCurrent / $_importTotal entries processed',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isImporting
                      ? (_isCancelled ? null : _cancelImport)
                      : () => Navigator.of(context).pop(),
                  child: Text(_isImporting
                      ? (_isCancelled ? 'Cancelling...' : 'Cancel Import')
                      : 'Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _preview != null &&
                          _selectedKeys.isNotEmpty &&
                          !_isImporting
                      ? _executeImport
                      : null,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.arrow_import_24_regular, size: 18),
                  label: Text(_isImporting
                      ? 'Importing...'
                      : 'Import (${_selectedKeys.length})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final preview = _preview!;
    final conflictCount = preview.entriesWithConflicts.length;
    final newCount = preview.entriesWithoutConflicts.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analysis Summary',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard(
                'Total in pack',
                preview.totalEntriesInPack.toString(),
                FluentIcons.document_24_regular,
                Colors.blue,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                'Matches',
                preview.matchingCount.toString(),
                FluentIcons.checkmark_circle_24_regular,
                Colors.green,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                'New',
                newCount.toString(),
                FluentIcons.add_circle_24_regular,
                Colors.teal,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                'Conflicts',
                conflictCount.toString(),
                FluentIcons.warning_24_regular,
                Colors.orange,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                'Not found',
                preview.unmatchedCount.toString(),
                FluentIcons.dismiss_circle_24_regular,
                Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesGrid() {
    final preview = _preview!;
    if (preview.matchingEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.document_dismiss_24_regular,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'No matching translations found',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SfDataGrid(
          source: _dataSource!,
          columnWidthMode: ColumnWidthMode.fill,
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.horizontal,
          rowHeight: 52,
          headerRowHeight: 40,
          columns: [
            GridColumn(
              columnName: 'selected',
              width: 50,
              label: Container(
                alignment: Alignment.center,
                child: const Text(''),
              ),
            ),
            GridColumn(
              columnName: 'key',
              minimumWidth: 200,
              label: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Key',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            GridColumn(
              columnName: 'value',
              minimumWidth: 300,
              label: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Value to import',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            GridColumn(
              columnName: 'status',
              width: 90,
              label: Container(
                alignment: Alignment.center,
                child: const Text(
                  'Status',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// DataSource for the pack import grid
class _PackImportDataSource extends DataGridSource {
  final List<PackImportEntry> entries;
  Set<String> selectedKeys;
  final void Function(String key, bool selected) onSelectionChanged;

  _PackImportDataSource({
    required this.entries,
    required this.selectedKeys,
    required this.onSelectionChanged,
  }) {
    _buildRows();
  }

  List<DataGridRow> _rows = [];

  void _buildRows() {
    _rows = entries.map((entry) {
      return DataGridRow(cells: [
        DataGridCell<String>(columnName: 'selected', value: entry.key),
        DataGridCell<String>(columnName: 'key', value: entry.key),
        DataGridCell<String>(columnName: 'value', value: entry.importedValue),
        DataGridCell<bool>(columnName: 'status', value: entry.hasExistingTranslation),
      ]);
    }).toList();
  }

  void updateSelection(Set<String> newSelection) {
    selectedKeys = newSelection;
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final key = row.getCells()[0].value as String;
    final value = row.getCells()[2].value as String;
    final hasConflict = row.getCells()[3].value as bool;
    final isSelected = selectedKeys.contains(key);

    return DataGridRowAdapter(
      color: isSelected
          ? Colors.blue.withValues(alpha: 0.1)
          : null,
      cells: [
        // Checkbox
        Center(
          child: Checkbox(
            value: isSelected,
            onChanged: (value) {
              onSelectionChanged(key, value ?? false);
            },
          ),
        ),
        // Key
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            key,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        // Value
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: value,
            waitDuration: const Duration(milliseconds: 500),
            child: Text(
              value.replaceAll('\n', ' '),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        // Status
        Center(
          child: hasConflict
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text(
                    'Conflict',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange,
                    ),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text(
                    'New',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
