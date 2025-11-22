import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../services/translation/i_translation_orchestrator.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../services/translation/models/translation_progress.dart';
import '../../../models/common/result.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog utilities for translation editor screen
///
/// Provides reusable dialogs for various editor operations:
/// - Feature not implemented notifications
/// - No selection warnings
/// - Provider setup prompts
/// - Translation confirmations
/// - Error messages
class EditorDialogs {
  const EditorDialogs._();

  static void showFeatureNotImplemented(
    BuildContext context,
    String feature,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.info_24_regular),
            const SizedBox(width: 8),
            Text(feature),
          ],
        ),
        content: const Text(
          'This feature will be fully implemented in the next phase.\n\n'
          'Current implementation provides the UI structure and event handlers.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showNoSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.warning_24_regular, color: Colors.orange),
            SizedBox(width: 8),
            Text('No Selection'),
          ],
        ),
        content: const Text(
          'Please select one or more translation units to translate.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showNoUntranslatedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.info_24_regular, color: Colors.blue),
            SizedBox(width: 8),
            Text('No Untranslated Units'),
          ],
        ),
        content: const Text(
          'All units in this project language are already translated.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showAllTranslatedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.info_24_regular, color: Colors.blue),
            SizedBox(width: 8),
            Text('All Selected Units Translated'),
          ],
        ),
        content: const Text(
          'All selected units are already translated.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showErrorDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.error_circle_24_regular, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<bool> showTranslateConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.translate_24_regular),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FluentButton(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(FluentIcons.translate_24_regular),
            child: const Text('Translate'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  static void showTranslationProgressDialog(
    BuildContext context, {
    required String batchId,
    required ITranslationOrchestrator orchestrator,
    required TranslationContext translationContext,
    required VoidCallback onComplete,
  }) {
    final originalContext = context;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StreamBuilder(
          stream: orchestrator.translateBatch(
            batchId: batchId,
            context: translationContext,
          ),
          builder: (builderContext, snapshot) {
            if (snapshot.hasError) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(FluentIcons.error_circle_24_regular, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Translation Error'),
                  ],
                ),
                content: Text('Translation failed: ${snapshot.error}'),
                actions: [
                  FluentTextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onComplete();
                    },
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            if (!snapshot.hasData) {
              return const AlertDialog(
                title: Text('Initializing Translation...'),
                content: SizedBox(
                  height: 100,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }

            final result = snapshot.data as Result<TranslationProgress, dynamic>;

            if (result.isErr) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(FluentIcons.error_circle_24_regular, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Translation Error'),
                  ],
                ),
                content: Text('Translation failed: ${result.unwrapErr()}'),
                actions: [
                  FluentTextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onComplete();
                    },
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final progress = result.unwrap();

            // Check if translation is complete
            if (progress.status == TranslationProgressStatus.completed) {
              // Auto-close dialog after a short delay
              Future.delayed(const Duration(seconds: 1), () {
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop();
                  onComplete();

                  // Show success message using the original context
                  if (originalContext.mounted) {
                    FluentToast.success(
                      originalContext,
                      'Translation completed: ${progress.successfulUnits}/${progress.totalUnits} units',
                    );
                  }
                }
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(FluentIcons.translate_24_regular),
                  const SizedBox(width: 8),
                  Text(_getProgressTitle(progress.status)),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress.totalUnits > 0
                          ? progress.processedUnits / progress.totalUnits
                          : 0.0,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Progress: ${progress.processedUnits}/${progress.totalUnits} units',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Successful: ${progress.successfulUnits}'),
                    Text('Failed: ${progress.failedUnits}'),
                    Text('Skipped: ${progress.skippedUnits}'),
                    const SizedBox(height: 8),
                    Text('Phase: ${_getPhaseDisplay(progress.currentPhase)}'),
                    if (progress.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Error: ${progress.errorMessage}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (progress.status == TranslationProgressStatus.inProgress)
                  FluentTextButton(
                    onPressed: () async {
                      await orchestrator.cancelTranslation(batchId: batchId);
                    },
                    child: const Text('Cancel'),
                  ),
                if (progress.status == TranslationProgressStatus.completed ||
                    progress.status == TranslationProgressStatus.failed ||
                    progress.status == TranslationProgressStatus.cancelled)
                  FluentTextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onComplete();
                    },
                    child: const Text('Close'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static String _getProgressTitle(TranslationProgressStatus status) {
    switch (status) {
      case TranslationProgressStatus.queued:
        return 'Queued...';
      case TranslationProgressStatus.inProgress:
        return 'Translating...';
      case TranslationProgressStatus.completed:
        return 'Translation Complete';
      case TranslationProgressStatus.failed:
        return 'Translation Failed';
      case TranslationProgressStatus.cancelled:
        return 'Translation Cancelled';
      case TranslationProgressStatus.paused:
        return 'Translation Paused';
    }
  }

  static String _getPhaseDisplay(TranslationPhase phase) {
    switch (phase) {
      case TranslationPhase.initializing:
        return 'Initializing';
      case TranslationPhase.tmExactLookup:
        return 'Checking Translation Memory (Exact)';
      case TranslationPhase.tmFuzzyLookup:
        return 'Checking Translation Memory (Fuzzy)';
      case TranslationPhase.buildingPrompt:
        return 'Building Prompt';
      case TranslationPhase.llmTranslation:
        return 'Translating with LLM';
      case TranslationPhase.validating:
        return 'Validating Translations';
      case TranslationPhase.saving:
        return 'Saving Translations';
      case TranslationPhase.updatingTm:
        return 'Updating Translation Memory';
      case TranslationPhase.finalizing:
        return 'Finalizing';
      case TranslationPhase.completed:
        return 'Completed';
    }
  }

  static void showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(FluentIcons.info_24_regular, color: Colors.blue),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<String?> showExportDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.arrow_export_24_regular),
            SizedBox(width: 8),
            Text('Export Translations'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select export format:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(FluentIcons.document_24_regular),
              title: const Text('.pack (Total War Mod)'),
              subtitle: const Text('Game-ready package file'),
              onTap: () => Navigator.of(context).pop('pack'),
            ),
            ListTile(
              leading: const Icon(FluentIcons.table_24_regular),
              title: const Text('CSV'),
              subtitle: const Text('Comma-separated values'),
              onTap: () => Navigator.of(context).pop('csv'),
            ),
            ListTile(
              leading: const Icon(FluentIcons.document_table_24_regular),
              title: const Text('Excel'),
              subtitle: const Text('Microsoft Excel spreadsheet'),
              onTap: () => Navigator.of(context).pop('excel'),
            ),
          ],
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    return result;
  }
}
