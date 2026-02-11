import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../../models/domain/translation_version.dart' show TranslationVersionStatus;
import '../providers/editor_providers.dart';
import '../../projects/providers/projects_screen_providers.dart'
    show projectsWithDetailsProvider, translationStatsVersionProvider;
import 'editor_data_source.dart';
import 'clear_progress_dialog.dart';

/// Handler for grid actions (copy, paste, validate, clear, delete)
///
/// Encapsulates all bulk operations on selected rows in the translation editor
class GridActionsHandler {
  final BuildContext context;
  final WidgetRef ref;
  final EditorDataSource dataSource;
  final Set<String> selectedRowIds;
  final String projectId;
  final String languageId;
  final Function(String unitId, String newText) onCellEdit;

  GridActionsHandler({
    required this.context,
    required this.ref,
    required this.dataSource,
    required this.selectedRowIds,
    required this.projectId,
    required this.languageId,
    required this.onCellEdit,
  });

  /// Copy selected rows to clipboard in TSV format
  Future<void> handleCopy(List<dynamic> selectedRows) async {
    if (selectedRows.isEmpty) {
      if (context.mounted) {
        FluentToast.warning(context, 'No rows selected');
      }
      return;
    }

    // Get the selected TranslationRow objects from the data source
    final selectedTranslations = <TranslationRow>[];
    for (final dataGridRow in selectedRows) {
      final rowIndex = dataSource.rows.indexOf(dataGridRow);
      if (rowIndex >= 0 && rowIndex < dataSource.translationRows.length) {
        selectedTranslations.add(dataSource.translationRows[rowIndex]);
      }
    }

    // Format as TSV (Key\tSource\tTranslation)
    final tsvData = selectedTranslations.map((row) {
      final translatedText = row.translatedText ?? '';
      return '${row.key}\t${row.sourceText}\t$translatedText';
    }).join('\n');

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: tsvData));

    // Show confirmation
    if (context.mounted) {
      FluentToast.success(
        context,
        'Copied ${selectedTranslations.length} row(s) to clipboard',
      );
    }
  }

  /// Paste from clipboard and update translations
  Future<void> handlePaste() async {
    // Read from clipboard
    final clipboardData = await Clipboard.getData('text/plain');

    if (clipboardData?.text == null || clipboardData!.text!.isEmpty) {
      if (context.mounted) {
        FluentToast.warning(context, 'Clipboard is empty');
      }
      return;
    }

    // Parse TSV format
    final lines = clipboardData.text!.split('\n');
    final updates = <String, String>{}; // Map of unitId -> translatedText
    int validLines = 0;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final parts = line.split('\t');
      if (parts.length >= 3) {
        final key = parts[0].trim();
        final translation = parts[2].trim();

        // Find the unit ID by key
        try {
          final matchingRow = dataSource.translationRows.firstWhere(
            (row) => row.key == key,
          );
          updates[matchingRow.id] = translation;
          validLines++;
        } catch (e) {
          // Key not found, skip this line
          continue;
        }
      }
    }

    if (updates.isEmpty) {
      if (context.mounted) {
        FluentToast.warning(context, 'No valid translations found in clipboard');
      }
      return;
    }

    // Apply updates using the onCellEdit callback
    for (final entry in updates.entries) {
      onCellEdit(entry.key, entry.value);
    }

    // Show confirmation
    if (context.mounted) {
      FluentToast.success(context, 'Pasted $validLines translation(s)');
    }
  }

  /// Mark selected translations as translated (validated/approved)
  Future<void> handleValidate() async {
    if (selectedRowIds.isEmpty) return;

    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final selectedRows = dataSource.translationRows
          .where((row) => selectedRowIds.contains(row.id))
          .toList();

      int successCount = 0;
      for (final row in selectedRows) {
        final updatedVersion = row.version.copyWith(
          status: TranslationVersionStatus.translated,
          validationIssues: null, // Clear validation issues when manually approved
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await versionRepo.update(updatedVersion);
        result.when(
          ok: (_) => successCount++,
          err: (error) {
            // Log error but continue with other rows
          },
        );
      }

      if (context.mounted) {
        FluentToast.success(
          context,
          'Marked $successCount translation(s) as translated',
        );
        
        // Refresh the data
        _refreshProviders();
      }
    } catch (e) {
      if (context.mounted) {
        FluentToast.error(context, 'Error: $e');
      }
    }
  }

  /// Refresh all relevant providers after data changes
  void _refreshProviders() {
    ref.invalidate(translationRowsProvider(projectId, languageId));
    ref.invalidate(projectsWithDetailsProvider);
    // Increment version to trigger refresh of pack compilation stats
    ref.read(translationStatsVersionProvider.notifier).increment();
  }

  /// Clear translation text for selected rows using batch SQL update
  Future<void> handleClear() async {
    if (selectedRowIds.isEmpty) return;

    final selectedRows = dataSource.translationRows
        .where((row) => selectedRowIds.contains(row.id))
        .toList();

    if (selectedRows.isEmpty) return;

    final versionIds = selectedRows.map((row) => row.version.id).toList();
    final showProgress = versionIds.length > 100;

    // State for progress dialog
    int currentProcessed = 0;
    int currentTotal = versionIds.length;
    String currentPhase = 'Preparing...';

    // Store root navigator to close dialog even if user navigates away
    NavigatorState? rootNavigator;

    // Show progress dialog for large operations using root navigator
    // This ensures the dialog can be closed even if the editor screen is disposed
    if (showProgress && context.mounted) {
      rootNavigator = Navigator.of(context, rootNavigator: true);
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (statefulContext, setDialogState) {
              // Store the setState function for updates
              _clearProgressSetState = (processed, total, phase) {
                if (statefulContext.mounted) {
                  setDialogState(() {
                    currentProcessed = processed;
                    currentTotal = total;
                    currentPhase = phase;
                  });
                }
              };

              return ClearProgressDialog(
                processed: currentProcessed,
                total: currentTotal,
                phase: currentPhase,
              );
            },
          );
        },
      );
    }

    // Helper to close dialog safely using root navigator
    void closeDialog() {
      if (showProgress && rootNavigator != null && rootNavigator!.mounted) {
        rootNavigator!.pop();
      }
      rootNavigator = null;
      _clearProgressSetState = null;
    }

    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);

      // Callback for progress updates
      void onProgress(int processed, int total, String phase) {
        _clearProgressSetState?.call(processed, total, phase);
      }

      final result = await versionRepo.clearBatch(
        versionIds,
        onProgress: showProgress ? onProgress : null,
      );

      // Close progress dialog
      closeDialog();

      if (context.mounted) {
        result.when(
          ok: (count) {
            FluentToast.success(context, 'Cleared $count translation(s)');
            _refreshProviders();
          },
          err: (error) {
            FluentToast.error(context, 'Error: $error');
          },
        );
      }
    } catch (e) {
      // Close progress dialog on error
      closeDialog();

      if (context.mounted) {
        FluentToast.error(context, 'Error: $e');
      }
    }
  }

  // Callback to update progress dialog state
  void Function(int, int, String)? _clearProgressSetState;

  /// Perform the actual deletion
  Future<void> performDelete(VoidCallback onDeleteComplete) async {
    if (selectedRowIds.isEmpty) return;

    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final selectedRows = dataSource.translationRows
          .where((row) => selectedRowIds.contains(row.id))
          .toList();

      int successCount = 0;
      for (final row in selectedRows) {
        final result = await versionRepo.delete(row.version.id);
        result.when(
          ok: (_) => successCount++,
          err: (error) {
            // Log error but continue with other rows
          },
        );
      }

      onDeleteComplete();

      if (context.mounted) {
        FluentToast.success(context, 'Deleted $successCount translation(s)');
        
        // Refresh the data
        _refreshProviders();
      }
    } catch (e) {
      if (context.mounted) {
        FluentToast.error(context, 'Error: $e');
      }
    }
  }
}
