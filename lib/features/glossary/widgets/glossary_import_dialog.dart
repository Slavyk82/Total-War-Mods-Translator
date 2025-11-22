import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/glossary_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog for importing glossary from file
class GlossaryImportDialog extends ConsumerStatefulWidget {
  final String glossaryId;

  const GlossaryImportDialog({
    super.key,
    required this.glossaryId,
  });

  @override
  ConsumerState<GlossaryImportDialog> createState() =>
      _GlossaryImportDialogState();
}

class _GlossaryImportDialogState extends ConsumerState<GlossaryImportDialog> {
  ImportFormat _selectedFormat = ImportFormat.csv;
  String? _selectedFilePath;
  bool _skipDuplicates = true;
  String _targetLanguage = 'fr';

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(glossaryImportStateProvider);

    return AlertDialog(
      title: const Text('Import Glossary'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Format selector
              Text(
                'Format',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<ImportFormat>(
                initialValue: _selectedFormat,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: ImportFormat.values.map((format) {
                  return DropdownMenuItem(
                    value: format,
                    child: Text(format.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedFormat = value ?? ImportFormat.csv;
                  });
                },
              ),
              const SizedBox(height: 16),

              // File picker
              Text(
                'File',
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
                          FluentIcons.folder_open_24_regular,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedFilePath ?? 'Click to select file...',
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

              // Language settings (for CSV/Excel)
              if (_selectedFormat != ImportFormat.tbx) ...[
                Text(
                  'Target Language',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _targetLanguage,
                  decoration: const InputDecoration(
                    labelText: 'Target Language',
                    border: OutlineInputBorder(),
                  ),
                  items: _languageCodes.map((lang) {
                    return DropdownMenuItem(
                      value: lang,
                      child: Text(lang.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _targetLanguage = value ?? 'fr';
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Import options
              Text(
                'Options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('Skip duplicate entries'),
                subtitle: const Text(
                  'Existing entries will not be overwritten',
                ),
                value: _skipDuplicates,
                onChanged: (value) {
                  setState(() {
                    _skipDuplicates = value ?? true;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 16),

              // Progress and results
              importState.when(
                data: (result) {
                  if (result != null) {
                    return _buildImportSummary(result);
                  }
                  return const SizedBox.shrink();
                },
                loading: () => Column(
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Importing...',
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
          onPressed: importState.isLoading ? null : _import,
          icon: const Icon(FluentIcons.arrow_import_24_regular),
          child: const Text('Import'),
        ),
      ],
    );
  }

  Widget _buildImportSummary(ImportResult result) {
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
                'Import Summary',
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _selectedFormat.extensions,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
      });
    }
  }

  Future<void> _import() async {
    if (_selectedFilePath == null) {
      if (mounted) {
        FluentToast.error(context, 'Please select a file to import');
      }
      return;
    }

    switch (_selectedFormat) {
      case ImportFormat.csv:
        await ref.read(glossaryImportStateProvider.notifier).importCsv(
              glossaryId: widget.glossaryId,
              filePath: _selectedFilePath!,
              targetLanguageCode: _targetLanguage,
              skipDuplicates: _skipDuplicates,
            );
        break;

      case ImportFormat.tbx:
        await ref.read(glossaryImportStateProvider.notifier).importTbx(
              glossaryId: widget.glossaryId,
              filePath: _selectedFilePath!,
            );
        break;

      case ImportFormat.excel:
        await ref.read(glossaryImportStateProvider.notifier).importExcel(
              glossaryId: widget.glossaryId,
              filePath: _selectedFilePath!,
              targetLanguageCode: _targetLanguage,
              skipDuplicates: _skipDuplicates,
            );
        break;
    }
  }

  static const List<String> _languageCodes = [
    'en',
    'fr',
    'de',
    'es',
    'it',
    'pt',
    'ru',
    'zh',
    'ja',
    'ko',
  ];
}

/// Import format options
enum ImportFormat {
  csv,
  tbx,
  excel;

  String get displayName {
    switch (this) {
      case ImportFormat.csv:
        return 'CSV';
      case ImportFormat.tbx:
        return 'TBX (TermBase eXchange)';
      case ImportFormat.excel:
        return 'Excel';
    }
  }

  List<String> get extensions {
    switch (this) {
      case ImportFormat.csv:
        return ['csv'];
      case ImportFormat.tbx:
        return ['tbx', 'xml'];
      case ImportFormat.excel:
        return ['xlsx', 'xls'];
    }
  }
}
