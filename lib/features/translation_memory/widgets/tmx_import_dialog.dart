import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/tm_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';

/// Dialog for importing TMX files
class TmxImportDialog extends ConsumerStatefulWidget {
  const TmxImportDialog({super.key});

  @override
  ConsumerState<TmxImportDialog> createState() => _TmxImportDialogState();
}

class _TmxImportDialogState extends ConsumerState<TmxImportDialog> {
  String? _selectedFilePath;
  bool _overwriteExisting = false;
  bool _validateEntries = true;
  int _processedEntries = 0;
  int _totalEntries = 0;

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(tmImportStateProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.arrow_import_24_regular,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Import Translation Memory (TMX)'),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File picker
            _buildFilePicker(context),

            const SizedBox(height: 24),

            // File preview
            if (_selectedFilePath != null) ...[
              _buildFilePreview(context),
              const SizedBox(height: 24),
            ],

            // Options
            _buildOptions(context),

            const SizedBox(height: 24),

            // Progress or result
            importState.when(
              data: (result) {
                if (result != null) {
                  return _buildImportResult(context, result);
                }
                return const SizedBox.shrink();
              },
              loading: () => _buildProgress(context),
              error: (error, stack) => _buildError(context, error.toString()),
            ),
          ],
        ),
      ),
      actions: [
        // Cancel button
        FluentTextButton(
          onPressed: importState.isLoading
              ? null
              : () {
                  ref.read(tmImportStateProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),

        // Import button
        FluentButton(
          onPressed: _selectedFilePath == null || importState.isLoading
              ? null
              : () => _startImport(),
          icon: const Icon(FluentIcons.arrow_import_24_regular),
          child: const Text('Import'),
        ),
      ],
    );
  }

  Widget _buildFilePicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select TMX File',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _pickFile,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.document_24_regular,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFilePath ?? 'Click to select a .tmx file',
                      style: TextStyle(
                        color: _selectedFilePath != null
                            ? Theme.of(context).textTheme.bodyMedium?.color
                            : Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    FluentIcons.folder_open_24_regular,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreview(BuildContext context) {
    final file = File(_selectedFilePath!);
    final sizeInBytes = file.lengthSync();
    final sizeInKB = (sizeInBytes / 1024).toStringAsFixed(1);
    final fileName = file.path.split(Platform.pathSeparator).last;

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
            'Selected File',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                FluentIcons.document_24_filled,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Size: $sizeInKB KB',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Import Options',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _overwriteExisting,
          onChanged: (value) {
            setState(() {
              _overwriteExisting = value ?? false;
            });
          },
          title: const Text('Overwrite existing entries'),
          subtitle: const Text(
            'Replace existing entries with imported ones',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _validateEntries,
          onChanged: (value) {
            setState(() {
              _validateEntries = value ?? true;
            });
          },
          title: const Text('Validate entries'),
          subtitle: const Text(
            'Check for errors before importing',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final progress = _totalEntries > 0 ? _processedEntries / _totalEntries : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Importing...',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        FluentProgressBar(value: _totalEntries > 0 ? progress : null),
        const SizedBox(height: 8),
        if (_totalEntries > 0)
          Text(
            'Processed $_processedEntries of $_totalEntries entries',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _buildImportResult(BuildContext context, TmImportResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                FluentIcons.checkmark_circle_24_filled,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                'Import Complete',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildResultRow('Total entries', result.totalEntries.toString()),
          _buildResultRow('Imported', result.importedEntries.toString()),
          if (result.skippedEntries > 0)
            _buildResultRow(
              'Skipped (duplicates)',
              result.skippedEntries.toString(),
            ),
          if (result.failedEntries > 0)
            _buildResultRow(
              'Failed (validation errors)',
              result.failedEntries.toString(),
            ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tmx'],
      dialogTitle: 'Select TMX File',
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
      });
    }
  }

  Future<void> _startImport() async {
    if (_selectedFilePath == null) return;

    await ref.read(tmImportStateProvider.notifier).importFromTmx(
          filePath: _selectedFilePath!,
          overwriteExisting: _overwriteExisting,
          onProgress: (processed, total) {
            setState(() {
              _processedEntries = processed;
              _totalEntries = total;
            });
          },
        );
  }
}
