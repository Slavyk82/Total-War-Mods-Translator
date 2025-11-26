import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/glossary_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog for exporting glossary to file
class GlossaryExportDialog extends ConsumerStatefulWidget {
  final String glossaryId;

  const GlossaryExportDialog({
    super.key,
    required this.glossaryId,
  });

  @override
  ConsumerState<GlossaryExportDialog> createState() =>
      _GlossaryExportDialogState();
}

class _GlossaryExportDialogState extends ConsumerState<GlossaryExportDialog> {
  String? _selectedFilePath;

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(glossaryExportStateProvider);

    return AlertDialog(
      title: const Text('Export Glossary (CSV)'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File path picker
              Text(
                'Output File',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _pickFile,
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
                          FluentIcons.save_24_regular,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedFilePath ?? 'Click to select output file...',
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Progress and results
              exportState.when(
                data: (result) {
                  if (result != null) {
                    return _buildExportSummary(result);
                  }
                  return const SizedBox.shrink();
                },
                loading: () => Column(
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Exporting...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                error: (error, stack) => Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.error_circle_24_regular,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Error: $error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FluentTextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FluentButton(
          onPressed: exportState.isLoading ? null : _export,
          icon: const Icon(FluentIcons.arrow_export_24_regular),
          child: const Text('Export'),
        ),
      ],
    );
  }

  Widget _buildExportSummary(ExportResult result) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.checkmark_circle_24_regular,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Export Summary',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Glossary Export',
      fileName: 'glossary.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      setState(() {
        _selectedFilePath = result;
      });
    }
  }

  Future<void> _export() async {
    if (_selectedFilePath == null) {
      if (mounted) {
        FluentToast.error(context, 'Please select an output file');
      }
      return;
    }

    await ref.read(glossaryExportStateProvider.notifier).exportCsv(
          glossaryId: widget.glossaryId,
          filePath: _selectedFilePath!,
        );
  }
}
