import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Export format option
class ExportFormatOption {
  final ExportFormat format;
  final String label;
  final String description;
  final IconData icon;

  const ExportFormatOption({
    required this.format,
    required this.label,
    required this.description,
    required this.icon,
  });
}

/// Export validation filter option
enum ValidationFilter {
  all,
  validatedOnly,
  needsReview,
}

/// Language selection state
class LanguageSelection {
  final String languageId;
  final String languageCode;
  final String languageName;
  final double completionPercent;
  bool isSelected;

  LanguageSelection({
    required this.languageId,
    required this.languageCode,
    required this.languageName,
    required this.completionPercent,
    this.isSelected = false,
  });
}

/// Export translations dialog
///
/// Allows user to select languages, format, and options for exporting translations
class ExportTranslationsDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;
  final List<LanguageSelection> availableLanguages;

  const ExportTranslationsDialog({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.availableLanguages,
  });

  @override
  ConsumerState<ExportTranslationsDialog> createState() =>
      _ExportTranslationsDialogState();
}

class _ExportTranslationsDialogState
    extends ConsumerState<ExportTranslationsDialog> {
  static const _formatOptions = [
    ExportFormatOption(
      format: ExportFormat.pack,
      label: 'Total War .pack file',
      description: 'Native mod format for Total War games (recommended)',
      icon: FluentIcons.archive_24_regular,
    ),
    ExportFormatOption(
      format: ExportFormat.csv,
      label: 'CSV file',
      description: 'Comma-separated values for spreadsheet applications',
      icon: FluentIcons.document_table_24_regular,
    ),
    ExportFormatOption(
      format: ExportFormat.excel,
      label: 'Excel file',
      description: 'Microsoft Excel workbook format',
      icon: FluentIcons.document_data_24_regular,
    ),
    ExportFormatOption(
      format: ExportFormat.tmx,
      label: 'TMX file',
      description: 'Translation Memory eXchange format for CAT tools',
      icon: FluentIcons.code_24_regular,
    ),
  ];

  ExportFormat _selectedFormat = ExportFormat.pack;
  ValidationFilter _validationFilter = ValidationFilter.validatedOnly;
  String _outputPath = '';
  late List<LanguageSelection> _languages;
  bool _generatePackImage = true;

  @override
  void initState() {
    super.initState();
    _languages = List.from(widget.availableLanguages);
    _initializeOutputPath();
  }

  Future<void> _initializeOutputPath() async {
    try {
      final documentsPath = Platform.environment['USERPROFILE'] ?? '';
      if (documentsPath.isNotEmpty) {
        final defaultPath = path.join(
          documentsPath,
          'Documents',
          'TWMT',
          'Exports',
          widget.projectName,
        );

        setState(() {
          _outputPath = defaultPath;
        });
      }
    } catch (e) {
      // Ignore errors, user can manually select path
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedLanguages = _languages.where((l) => l.isSelected).toList();
    final canExport = selectedLanguages.isNotEmpty && _outputPath.isNotEmpty;

    return Dialog(
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(FluentIcons.arrow_export_24_regular, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Export Translations',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FluentIconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language selection
                    _buildSectionHeader('Select Languages'),
                    const SizedBox(height: 12),
                    _buildLanguageSelection(),
                    const SizedBox(height: 24),

                    // Export format
                    _buildSectionHeader('Export Format'),
                    const SizedBox(height: 12),
                    _buildFormatSelection(),
                    const SizedBox(height: 24),

                    // Validation filter
                    _buildSectionHeader('Translation Filter'),
                    const SizedBox(height: 12),
                    _buildValidationFilter(),
                    const SizedBox(height: 24),

                    // Pack image option (only for .pack format)
                    if (_selectedFormat == ExportFormat.pack) ...[
                      _buildSectionHeader('Pack Image'),
                      const SizedBox(height: 12),
                      _buildPackImageOption(),
                      const SizedBox(height: 24),
                    ],

                    // Output location
                    _buildSectionHeader('Output Location'),
                    const SizedBox(height: 12),
                    _buildOutputLocation(),
                    const SizedBox(height: 24),

                    // Preview
                    if (selectedLanguages.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('Export Preview'),
                          const SizedBox(height: 12),
                          _buildPreview(),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FluentTextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FluentButton(
                    onPressed: canExport ? _handleExport : null,
                    icon: const Icon(FluentIcons.arrow_export_24_regular),
                    child: const Text('Export'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildLanguageSelection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Select all/deselect all
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: _selectAllLanguages,
                  child: const Text('Select All'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _deselectAllLanguages,
                  child: const Text('Deselect All'),
                ),
              ],
            ),
          ),

          // Language list
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              final language = _languages[index];
              return _buildLanguageItem(language, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageItem(LanguageSelection language, int index) {
    return Container(
      decoration: BoxDecoration(
        border: index < _languages.length - 1
            ? Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              )
            : null,
      ),
      child: CheckboxListTile(
        value: language.isSelected,
        onChanged: (value) {
          setState(() {
            language.isSelected = value ?? false;
          });
        },
        title: Text(language.languageName),
        subtitle: Row(
          children: [
            Text('${language.completionPercent.toStringAsFixed(1)}% complete'),
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(
                value: language.completionPercent / 100,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatSelection() {
    return Column(
      children: _formatOptions.map((option) {
        // ignore: deprecated_member_use
        return RadioListTile<ExportFormat>(
          value: option.format,
          // ignore: deprecated_member_use
          groupValue: _selectedFormat,
          // ignore: deprecated_member_use
          onChanged: (value) {
            setState(() {
              _selectedFormat = value!;
            });
          },
          title: Row(
            children: [
              Icon(option.icon, size: 18),
              const SizedBox(width: 8),
              Text(option.label),
            ],
          ),
          subtitle: Text(
            option.description,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPackImageOption() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CheckboxListTile(
        value: _generatePackImage,
        onChanged: (value) {
          setState(() {
            _generatePackImage = value ?? true;
          });
        },
        title: const Row(
          children: [
            Icon(FluentIcons.image_24_regular, size: 18),
            SizedBox(width: 8),
            Text('Generate pack image with language flag'),
          ],
        ),
        subtitle: const Text(
          'Creates a preview image for Steam Workshop with the target language flag',
        ),
      ),
    );
  }

  Widget _buildValidationFilter() {
    return Column(
      children: [
        // ignore: deprecated_member_use
        RadioListTile<ValidationFilter>(
          value: ValidationFilter.all,
          // ignore: deprecated_member_use
          groupValue: _validationFilter,
          // ignore: deprecated_member_use
          onChanged: (value) {
            setState(() {
              _validationFilter = value!;
            });
          },
          title: const Text('All translations'),
          subtitle: const Text('Export all available translations'),
        ),
        // ignore: deprecated_member_use
        RadioListTile<ValidationFilter>(
          value: ValidationFilter.validatedOnly,
          // ignore: deprecated_member_use
          groupValue: _validationFilter,
          // ignore: deprecated_member_use
          onChanged: (value) {
            setState(() {
              _validationFilter = value!;
            });
          },
          title: const Text('Validated only (recommended)'),
          subtitle: const Text('Export only approved and reviewed translations'),
        ),
        // ignore: deprecated_member_use
        RadioListTile<ValidationFilter>(
          value: ValidationFilter.needsReview,
          // ignore: deprecated_member_use
          groupValue: _validationFilter,
          // ignore: deprecated_member_use
          onChanged: (value) {
            setState(() {
              _validationFilter = value!;
            });
          },
          title: const Text('Needs review'),
          subtitle: const Text('Export translations that need review'),
        ),
      ],
    );
  }

  Widget _buildOutputLocation() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: _outputPath),
            decoration: const InputDecoration(
              hintText: 'Select output folder...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            readOnly: true,
          ),
        ),
        const SizedBox(width: 12),
        FluentButton(
          onPressed: _browseOutputPath,
          icon: const Icon(FluentIcons.folder_open_24_regular),
          child: const Text('Browse'),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final selectedLanguages = _languages.where((l) => l.isSelected).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FluentIcons.info_24_regular, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Export Summary',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPreviewItem('Languages', selectedLanguages.length.toString()),
          _buildPreviewItem('Format', _selectedFormat.toString().split('.').last.toUpperCase()),
          _buildPreviewItem(
            'Filter',
            _validationFilter == ValidationFilter.all
                ? 'All translations'
                : _validationFilter == ValidationFilter.validatedOnly
                    ? 'Validated only'
                    : 'Needs review',
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Files to be created:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...selectedLanguages.map(
            (lang) => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Text(
                '• ${lang.languageCode}_text.loc',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _selectAllLanguages() {
    setState(() {
      for (final language in _languages) {
        language.isSelected = true;
      }
    });
  }

  void _deselectAllLanguages() {
    setState(() {
      for (final language in _languages) {
        language.isSelected = false;
      }
    });
  }

  Future<void> _browseOutputPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Export Folder',
      initialDirectory: _outputPath.isNotEmpty ? _outputPath : null,
    );

    if (result != null) {
      setState(() {
        _outputPath = result;
      });
    }
  }

  void _handleExport() {
    final selectedLanguages = _languages.where((l) => l.isSelected).toList();

    Navigator.of(context).pop({
      'languages': selectedLanguages.map((l) => l.languageCode).toList(),
      'format': _selectedFormat,
      'validatedOnly': _validationFilter == ValidationFilter.validatedOnly,
      'outputPath': _outputPath,
      'generatePackImage': _generatePackImage,
    });
  }
}
