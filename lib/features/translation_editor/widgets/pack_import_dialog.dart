import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../services/pack_import_service.dart';

/// Token-themed popup for importing translations from a `.pack` file.
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

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isOk) {
        _preview = result.unwrap();
        _selectedKeys = _preview!.matchingEntries.map((e) => e.key).toSet();
        _dataSource = _PackImportDataSource(
          entries: _preview!.matchingEntries,
          selectedKeys: _selectedKeys,
          tokens: context.tokens,
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

    if (!mounted) return;
    setState(() {
      _isImporting = false;
    });

    if (result.isOk) {
      final importResult = result.unwrap();
      final navigatorContext = Navigator.of(context).context;
      if (_isCancelled) {
        if (navigatorContext.mounted) {
          _showResultToast(navigatorContext, importResult);
        }
        widget.onImportComplete?.call();
      } else {
        Navigator.of(context).pop();
        widget.onImportComplete?.call();
        if (navigatorContext.mounted) {
          _showResultToast(navigatorContext, importResult);
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

  void _showResultToast(BuildContext toastContext, PackImportResult result) {
    final message = StringBuffer();
    message.write(
      'Import complete: ${result.importedCount} translation(s) imported',
    );
    if (result.skippedCount > 0) {
      message.write(', ${result.skippedCount} skipped');
    }
    if (result.errorCount > 0) {
      message.write(', ${result.errorCount} error(s)');
    }

    if (result.hasErrors) {
      FluentToast.warning(toastContext, message.toString());
    } else {
      FluentToast.success(toastContext, message.toString());
    }
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
    final tokens = context.tokens;
    final allSelected = _preview != null &&
        _selectedKeys.length == _preview!.matchingEntries.length;

    return TokenDialog(
      icon: FluentIcons.arrow_import_24_regular,
      title: 'Import translations from a .pack file',
      width: 900,
      body: SizedBox(
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFileSelector(tokens),
            const SizedBox(height: 14),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: tokens.errBg,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(
                    color: tokens.err.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.warning_24_regular,
                      size: 18,
                      color: tokens.err,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: tokens.fontBody.copyWith(
                          fontSize: 12.5,
                          color: tokens.err,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: tokens.accent),
                      const SizedBox(height: 16),
                      Text(
                        'Analyzing pack file...',
                        style: tokens.fontBody.copyWith(
                          fontSize: 13,
                          color: tokens.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_isLoading && _preview != null) ...[
              _buildSummary(tokens),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TokenCheckbox(
                    value: _overwriteExisting,
                    onChanged: (v) =>
                        setState(() => _overwriteExisting = v ?? true),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Overwrite existing translations',
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.text,
                    ),
                  ),
                  const Spacer(),
                  SmallTextButton(
                    label: allSelected ? 'Deselect all' : 'Select all',
                    icon: allSelected
                        ? FluentIcons.checkbox_unchecked_24_regular
                        : FluentIcons.checkbox_checked_24_regular,
                    onTap: _toggleSelectAll,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildEntriesGrid(tokens)),
            ],
            if (!_isLoading && _preview == null && _errorMessage == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.document_add_24_regular,
                        size: 56,
                        color: tokens.textFaint,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Select a .pack file containing translations',
                        style: tokens.fontBody.copyWith(
                          fontSize: 13,
                          color: tokens.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isImporting) ...[
              const SizedBox(height: 12),
              _buildProgress(tokens),
            ],
          ],
        ),
      ),
      actions: [
        SmallTextButton(
          label: _isImporting
              ? (_isCancelled ? 'Cancelling...' : 'Cancel Import')
              : 'Cancel',
          onTap: _isImporting
              ? (_isCancelled ? null : _cancelImport)
              : () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: _isImporting
              ? 'Importing...'
              : 'Import (${_selectedKeys.length})',
          icon: FluentIcons.arrow_import_24_regular,
          filled: true,
          onTap: _preview != null &&
                  _selectedKeys.isNotEmpty &&
                  !_isImporting
              ? _executeImport
              : null,
        ),
      ],
    );
  }

  Widget _buildFileSelector(TwmtThemeTokens tokens) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Text(
              _selectedFilePath ?? 'No file selected',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: _selectedFilePath == null
                    ? tokens.textFaint
                    : tokens.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SmallTextButton(
          label: 'Browse',
          icon: FluentIcons.folder_open_24_regular,
          onTap: _isLoading || _isImporting ? null : _selectFile,
        ),
      ],
    );
  }

  Widget _buildProgress(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _importMessage,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: tokens.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: LinearProgressIndicator(
              value: _importTotal > 0 ? _importCurrent / _importTotal : 0,
              minHeight: 8,
              backgroundColor: tokens.panel,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_importCurrent / $_importTotal entries processed',
            style: tokens.fontBody.copyWith(
              fontSize: 11.5,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(TwmtThemeTokens tokens) {
    final preview = _preview!;
    final conflictCount = preview.entriesWithConflicts.length;
    final newCount = preview.entriesWithoutConflicts.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analysis Summary',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatCard(
                tokens,
                'Total in pack',
                preview.totalEntriesInPack.toString(),
                FluentIcons.document_24_regular,
                tokens.info,
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                tokens,
                'Matches',
                preview.matchingCount.toString(),
                FluentIcons.checkmark_circle_24_regular,
                tokens.ok,
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                tokens,
                'New',
                newCount.toString(),
                FluentIcons.add_circle_24_regular,
                tokens.accent,
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                tokens,
                'Conflicts',
                conflictCount.toString(),
                FluentIcons.warning_24_regular,
                tokens.warn,
              ),
              const SizedBox(width: 10),
              _buildStatCard(
                tokens,
                'Not found',
                preview.unmatchedCount.toString(),
                FluentIcons.dismiss_circle_24_regular,
                tokens.textFaint,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    TwmtThemeTokens tokens,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: tokens.fontDisplay.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesGrid(TwmtThemeTokens tokens) {
    final preview = _preview!;
    if (preview.matchingEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.document_dismiss_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              'No matching translations found',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
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
                child: Text(
                  'Key',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            GridColumn(
              columnName: 'value',
              minimumWidth: 300,
              label: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: Text(
                  'Value to import',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            GridColumn(
              columnName: 'status',
              width: 90,
              label: Container(
                alignment: Alignment.center,
                child: Text(
                  'Status',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _TokenCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Icon(
          value
              ? FluentIcons.checkbox_checked_24_filled
              : FluentIcons.checkbox_unchecked_24_regular,
          size: 18,
          color: value ? tokens.accent : tokens.textFaint,
        ),
      ),
    );
  }
}

class _PackImportDataSource extends DataGridSource {
  final List<PackImportEntry> entries;
  Set<String> selectedKeys;
  final TwmtThemeTokens tokens;
  final void Function(String key, bool selected) onSelectionChanged;

  _PackImportDataSource({
    required this.entries,
    required this.selectedKeys,
    required this.tokens,
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
        DataGridCell<bool>(
          columnName: 'status',
          value: entry.hasExistingTranslation,
        ),
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
      color: isSelected ? tokens.rowSelected : null,
      cells: [
        Center(
          child: _TokenCheckbox(
            value: isSelected,
            onChanged: (v) => onSelectionChanged(key, v ?? false),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            key,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontMono.copyWith(
              fontSize: 12,
              color: tokens.text,
            ),
          ),
        ),
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
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.text,
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasConflict
                  ? tokens.warn.withValues(alpha: 0.1)
                  : tokens.ok.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: (hasConflict ? tokens.warn : tokens.ok)
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              hasConflict ? 'Conflict' : 'New',
              style: tokens.fontBody.copyWith(
                fontSize: 11,
                color: hasConflict ? tokens.warn : tokens.ok,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
