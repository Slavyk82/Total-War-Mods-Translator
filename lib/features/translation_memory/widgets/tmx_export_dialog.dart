import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/tm_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog for exporting TM entries to TMX files
class TmxExportDialog extends ConsumerStatefulWidget {
  const TmxExportDialog({super.key});

  @override
  ConsumerState<TmxExportDialog> createState() => _TmxExportDialogState();
}

class _TmxExportDialogState extends ConsumerState<TmxExportDialog> {
  String? _outputPath;
  String? _targetLanguage;
  ExportScope _exportScope = ExportScope.all;
  bool _includeMetadata = true;
  bool _includeStats = true;

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(tmExportStateProvider);
    final filterState = ref.watch(tmFilterStateProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.arrow_export_24_regular,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Export Translation Memory (TMX)'),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filters section
              _buildFiltersSection(context, filterState),

              const SizedBox(height: 24),

              // Export scope
              _buildExportScopeSection(context),

              const SizedBox(height: 24),

              // Output path
              _buildOutputPathPicker(context),

              const SizedBox(height: 24),

              // Format options
              _buildFormatOptionsSection(context),

              const SizedBox(height: 24),

              // Progress or result
              exportState.when(
                data: (result) {
                  if (result != null) {
                    return _buildExportResult(context, result);
                  }
                  return const SizedBox.shrink();
                },
                loading: () => _buildProgress(context),
                error: (error, stack) => _buildError(context, error.toString()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Cancel button
        FluentTextButton(
          onPressed: exportState.isLoading
              ? null
              : () {
                  ref.read(tmExportStateProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),

        // Export button
        FluentButton(
          onPressed: _outputPath == null || exportState.isLoading
              ? null
              : () => _startExport(),
          icon: const Icon(FluentIcons.arrow_export_24_regular),
          child: const Text('Export'),
        ),
      ],
    );
  }

  Widget _buildFiltersSection(BuildContext context, TmFilters filterState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filters',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        _buildDropdown(
          context,
          label: 'Target Language',
          value: _targetLanguage,
          hint: 'All',
          items: const ['EN', 'FR', 'DE', 'ZH', 'ES'],
          onChanged: (value) {
            setState(() {
              _targetLanguage = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildExportScopeSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What to export',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            // ignore: deprecated_member_use
            RadioListTile<ExportScope>(
              value: ExportScope.all,
              // ignore: deprecated_member_use
              groupValue: _exportScope,
              // ignore: deprecated_member_use
              onChanged: (value) {
                setState(() {
                  _exportScope = value!;
                });
              },
              title: const Text('All entries (matching filters)'),
              contentPadding: EdgeInsets.zero,
            ),
            // ignore: deprecated_member_use
            RadioListTile<ExportScope>(
              value: ExportScope.frequentlyUsed,
              // ignore: deprecated_member_use
              groupValue: _exportScope,
              // ignore: deprecated_member_use
              onChanged: (value) {
                setState(() {
                  _exportScope = value!;
                });
              },
              title: const Text('Frequently used only (>5 times)'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputPathPicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Output File',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _pickOutputPath,
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
                    FluentIcons.save_24_regular,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _outputPath ?? 'Click to select save location',
                      style: TextStyle(
                        color: _outputPath != null
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

  Widget _buildFormatOptionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Format Options',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _includeMetadata,
          onChanged: (value) {
            setState(() {
              _includeMetadata = value ?? true;
            });
          },
          title: const Text('Include metadata'),
          subtitle: const Text('Add quality scores, usage counts, etc.'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _includeStats,
          onChanged: (value) {
            setState(() {
              _includeStats = value ?? true;
            });
          },
          title: const Text('Include statistics'),
          subtitle: const Text('Add export summary and stats to file header'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required String label,
    required String? value,
    required String hint,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          hint: Text(hint),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(hint),
            ),
            ...items.map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(item),
                )),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exporting...',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        const FluentProgressBar(),
      ],
    );
  }

  Widget _buildExportResult(BuildContext context, TmExportResult result) {
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
                'Export Complete',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Exported ${result.entriesExported} entries',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            result.filePath,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

  Future<void> _pickOutputPath() async {
    final result = await FilePicker.platform.saveFile(
      type: FileType.custom,
      allowedExtensions: ['tmx'],
      dialogTitle: 'Save TMX File',
      fileName: 'translation_memory_export.tmx',
    );

    if (result != null) {
      setState(() {
        _outputPath = result;
      });
    }
  }

  Future<void> _startExport() async {
    if (_outputPath == null) return;

    await ref.read(tmExportStateProvider.notifier).exportToTmx(
          outputPath: _outputPath!,
          targetLanguageCode: _targetLanguage,
        );
  }
}

enum ExportScope {
  all,
  frequentlyUsed,
}
