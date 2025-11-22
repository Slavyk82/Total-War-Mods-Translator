import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Export step enumeration
enum ExportStep {
  preparingData,
  generatingLocFiles,
  creatingPack,
  finalizing,
  completed,
  error,
}

/// Export progress dialog
///
/// Shows progress while exporting translations
class ExportProgressDialog extends StatelessWidget {
  final ExportStep currentStep;
  final double progress;
  final String? currentLanguage;
  final int? totalLanguages;
  final int? currentLanguageIndex;
  final String? errorMessage;

  const ExportProgressDialog({
    super.key,
    required this.currentStep,
    this.progress = 0.0,
    this.currentLanguage,
    this.totalLanguages,
    this.currentLanguageIndex,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  _getStepIcon(),
                  size: 24,
                  color: currentStep == ExportStep.error
                      ? Colors.red
                      : currentStep == ExportStep.completed
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  _getStepTitle(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Progress bar (hide if error or completed)
            if (currentStep != ExportStep.error &&
                currentStep != ExportStep.completed)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getProgressText(),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),

            // Error message
            if (currentStep == ExportStep.error && errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      FluentIcons.error_circle_24_regular,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Success message
            if (currentStep == ExportStep.completed)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      FluentIcons.checkmark_circle_24_regular,
                      color: Colors.green,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Export completed successfully!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Close button (only for error or completed)
            if (currentStep == ExportStep.error ||
                currentStep == ExportStep.completed)
              Align(
                alignment: Alignment.centerRight,
                child: FluentButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  child: const Text('Close'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getStepIcon() {
    switch (currentStep) {
      case ExportStep.preparingData:
        return FluentIcons.clipboard_task_24_regular;
      case ExportStep.generatingLocFiles:
        return FluentIcons.document_add_24_regular;
      case ExportStep.creatingPack:
        return FluentIcons.archive_24_regular;
      case ExportStep.finalizing:
        return FluentIcons.checkmark_24_regular;
      case ExportStep.completed:
        return FluentIcons.checkmark_circle_24_filled;
      case ExportStep.error:
        return FluentIcons.error_circle_24_filled;
    }
  }

  String _getStepTitle() {
    switch (currentStep) {
      case ExportStep.preparingData:
        return 'Preparing Data';
      case ExportStep.generatingLocFiles:
        return 'Generating .loc Files';
      case ExportStep.creatingPack:
        return 'Creating .pack File';
      case ExportStep.finalizing:
        return 'Finalizing Export';
      case ExportStep.completed:
        return 'Export Complete';
      case ExportStep.error:
        return 'Export Failed';
    }
  }

  String _getProgressText() {
    switch (currentStep) {
      case ExportStep.preparingData:
        return 'Loading translation data...';
      case ExportStep.generatingLocFiles:
        if (currentLanguage != null &&
            currentLanguageIndex != null &&
            totalLanguages != null) {
          return 'Generating $currentLanguage (${currentLanguageIndex! + 1}/$totalLanguages)...';
        }
        return 'Generating localization files...';
      case ExportStep.creatingPack:
        return 'Creating Total War .pack file...';
      case ExportStep.finalizing:
        return 'Finalizing and cleaning up...';
      case ExportStep.completed:
      case ExportStep.error:
        return '';
    }
  }
}
