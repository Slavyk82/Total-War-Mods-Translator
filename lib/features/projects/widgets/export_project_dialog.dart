import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../models/domain/export_history.dart';
import '../providers/projects_screen_providers.dart';
import '../../../repositories/export_history_repository.dart';
import 'export_project/export_format_selector.dart';
import 'export_project/export_options_panel.dart';
import 'export_project/export_dialog_components.dart';

/// Export project dialog following Fluent Design patterns.
///
/// Coordinates the export workflow by orchestrating child components:
/// - ExportFormatSelector: Format selection UI
/// - ExportOptionsPanel: Language selection and options
/// - FluentDialogButton: Action buttons
///
/// Allows exporting project translations in various formats:
/// - Total War .pack files (one per language)
/// - CSV files (for external review)
/// - Excel files (for external review)
/// - TMX files (translation memory exchange)
///
/// Options:
/// - Select languages to export
/// - Choose export format
/// - Export only validated translations
/// - Select output directory
class ExportProjectDialog extends ConsumerStatefulWidget {
  final String projectId;

  const ExportProjectDialog({
    super.key,
    required this.projectId,
  });

  @override
  ConsumerState<ExportProjectDialog> createState() => _ExportProjectDialogState();
}

class _ExportProjectDialogState extends ConsumerState<ExportProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _outputPathController = TextEditingController();

  ExportFormat _selectedFormat = ExportFormat.pack;
  final Set<String> _selectedLanguageIds = {};
  bool _validatedOnly = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _outputPathController.dispose();
    super.dispose();
  }

  Future<void> _browseOutputFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select output folder for exported files',
    );

    if (result != null) {
      setState(() {
        _outputPathController.text = result;
      });
    }
  }

  Future<void> _exportProject() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLanguageIds.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one language to export';
      });
      return;
    }

    if (_outputPathController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please select an output folder';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // TODO: Integrate with actual export service when implemented
      // For now, we'll just create an export history record

      final exportHistoryRepo = ExportHistoryRepository();
      const uuid = Uuid();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Get selected language codes for the history record
      final languagesAsync = await ref.read(allLanguagesProvider.future);
      final selectedLanguageCodes = languagesAsync
          .where((lang) => _selectedLanguageIds.contains(lang.id))
          .map((lang) => lang.code.toUpperCase())
          .toList();

      final exportHistory = ExportHistory(
        id: uuid.v4(),
        projectId: widget.projectId,
        languages: jsonEncode(selectedLanguageCodes),
        format: _selectedFormat,
        validatedOnly: _validatedOnly,
        outputPath: _outputPathController.text.trim(),
        entryCount: 0, // Will be updated by actual export service
        exportedAt: now,
      );

      await exportHistoryRepo.insert(exportHistory);

      if (!mounted) return;

      // Show success message
      FluentToast.success(
        context,
        'Export queued successfully. Files will be created in:\n${_outputPathController.text}',
      );

      Navigator.of(context).pop(true);

      // TODO: Trigger actual export service
      // This will be implemented when the export service is ready
      // await ref.read(exportServiceProvider).exportProject(
      //   projectId: widget.projectId,
      //   languageIds: _selectedLanguageIds.toList(),
      //   format: _selectedFormat,
      //   validatedOnly: _validatedOnly,
      //   outputPath: _outputPathController.text.trim(),
      // );

    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to export project: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(
            FluentIcons.arrow_export_24_regular,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Export Project'),
        ],
      ),
      content: SizedBox(
        width: 550,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Info banner
                const InfoBanner(
                  message: 'Exports will be created with proper prefixing for Total War mod loading order.',
                ),
                const SizedBox(height: 16),

                // Error message
                if (_errorMessage != null) ...[
                  ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],

                // Export format
                _buildFieldLabel('Export Format', theme),
                const SizedBox(height: 8),
                ExportFormatSelector(
                  selectedFormat: _selectedFormat,
                  onFormatChanged: (format) {
                    setState(() => _selectedFormat = format);
                  },
                ),
                const SizedBox(height: 16),

                // Export options (languages, validation, output path)
                ExportOptionsPanel(
                  projectId: widget.projectId,
                  selectedLanguageIds: _selectedLanguageIds,
                  onLanguageSelectionChanged: (selection) {
                    setState(() {
                      _selectedLanguageIds.clear();
                      _selectedLanguageIds.addAll(selection);
                    });
                  },
                  validatedOnly: _validatedOnly,
                  onValidatedOnlyChanged: (value) {
                    setState(() => _validatedOnly = value);
                  },
                  outputPathController: _outputPathController,
                  onBrowseFolder: _browseOutputFolder,
                  selectedFormat: _selectedFormat,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FluentDialogButton(
          icon: FluentIcons.dismiss_24_regular,
          label: 'Cancel',
          onTap: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        FluentDialogButton(
          icon: FluentIcons.arrow_export_24_regular,
          label: 'Export',
          isPrimary: true,
          isLoading: _isLoading,
          onTap: _isLoading ? null : _exportProject,
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, ThemeData theme) {
    return Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
