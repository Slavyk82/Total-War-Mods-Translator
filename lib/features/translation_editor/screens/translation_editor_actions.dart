import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import '../../../services/toast_notification_service.dart';
import '../../../services/history/undo_redo_manager.dart';
import '../../../models/domain/translation_version.dart';
import '../../../providers/batch/batch_operations_provider.dart' as batch;
import '../../../services/validation/models/validation_issue.dart' as validation;
import '../../settings/providers/settings_providers.dart';
import '../../projects/providers/projects_screen_providers.dart' show projectsWithDetailsProvider;
import '../../translation/widgets/batch_validation_dialog.dart';
import '../providers/editor_providers.dart';
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_dialogs.dart';
import '../widgets/provider_setup_dialog.dart';
import '../widgets/translation_settings_dialog.dart';
import '../utils/translation_batch_helper.dart';
import 'translation_progress_screen.dart';

/// Translation editor business logic actions
///
/// Handles all business operations for the translation editor:
/// - Cell editing and TM suggestion application
/// - Translation workflow (translate all/selected)
/// - Validation orchestration
/// - Export operations
/// - Undo/redo management
/// - Batch creation and orchestration
class TranslationEditorActions {
  TranslationEditorActions({
    required this.ref,
    required this.context,
    required this.projectId,
    required this.languageId,
  });

  final WidgetRef ref;
  final BuildContext context;
  final String projectId;
  final String languageId;

  bool get mounted => context.mounted;

  // ========== HELPER METHODS ==========

  /// Get the project_language_id from project_id and language_id
  Future<String> _getProjectLanguageId() async {
    final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
    final projectLanguagesResult = await projectLanguageRepo.getByProject(projectId);

    if (projectLanguagesResult.isErr) {
      throw Exception('Failed to load project languages');
    }

    final projectLanguages = projectLanguagesResult.unwrap();
    final projectLanguage = projectLanguages.firstWhere(
      (pl) => pl.languageId == languageId,
      orElse: () => throw Exception('Project language not found'),
    );

    return projectLanguage.id;
  }

  /// Refresh all relevant providers after data changes
  void _refreshProviders() {
    if (!mounted) return;
    ref.invalidate(translationRowsProvider(projectId, languageId));
    ref.invalidate(projectsWithDetailsProvider);
  }

  /// Convert validation issue type to readable label
  String _getIssueTypeLabel(validation.ValidationIssueType type) {
    switch (type) {
      case validation.ValidationIssueType.emptyTranslation:
        return 'Empty Translation';
      case validation.ValidationIssueType.lengthDifference:
        return 'Length Difference';
      case validation.ValidationIssueType.missingVariables:
        return 'Missing Variables';
      case validation.ValidationIssueType.whitespaceIssue:
        return 'Whitespace Issue';
      case validation.ValidationIssueType.punctuationMismatch:
        return 'Punctuation Mismatch';
      case validation.ValidationIssueType.caseMismatch:
        return 'Case Mismatch';
      case validation.ValidationIssueType.missingNumbers:
        return 'Missing Numbers';
    }
  }

  /// Export validation report to file
  Future<void> _exportValidationReport(
    String filePath,
    List<batch.ValidationIssue> issues,
  ) async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('Validation Report');
      buffer.writeln('=' * 80);
      buffer.writeln('Generated: ${DateTime.now()}');
      buffer.writeln('Total Issues: ${issues.length}');
      buffer.writeln();

      // Group issues by severity
      final errors = issues.where((i) => i.severity == batch.ValidationSeverity.error).toList();
      final warnings = issues.where((i) => i.severity == batch.ValidationSeverity.warning).toList();

      if (errors.isNotEmpty) {
        buffer.writeln('ERRORS (${errors.length})');
        buffer.writeln('-' * 80);
        for (final issue in errors) {
          buffer.writeln('Key: ${issue.unitKey}');
          buffer.writeln('Type: ${issue.issueType}');
          buffer.writeln('Description: ${issue.description}');
          buffer.writeln();
        }
      }

      if (warnings.isNotEmpty) {
        buffer.writeln('WARNINGS (${warnings.length})');
        buffer.writeln('-' * 80);
        for (final issue in warnings) {
          buffer.writeln('Key: ${issue.unitKey}');
          buffer.writeln('Type: ${issue.issueType}');
          buffer.writeln('Description: ${issue.description}');
          buffer.writeln();
        }
      }

      await File(filePath).writeAsString(buffer.toString());
      
      ref.read(loggingServiceProvider).info(
        'Validation report exported',
        {'filePath': filePath, 'issueCount': issues.length},
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to export validation report',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Export Failed',
          'Failed to export validation report: ${e.toString()}',
        );
      }
    }
  }

  // ========== CELL EDIT HANDLERS ==========

  Future<void> handleCellEdit(String unitId, String newText) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final tmService = ref.read(translationMemoryServiceProvider);
      final undoRedoManager = ref.read(undoRedoManagerProvider);

      // 1. Get current version and unit
      final versionsResult = await versionRepo.getByUnit(unitId);
      if (versionsResult.isErr) {
        throw Exception('Failed to get translation version');
      }

      final versions = versionsResult.unwrap();
      if (versions.isEmpty) {
        throw Exception('No translation version found for unit');
      }

      final currentVersion = versions.first;
      final oldText = currentVersion.translatedText ?? '';

      // Don't update if text hasn't changed
      if (oldText == newText) return;

      final unitResult = await unitRepo.getById(unitId);
      if (unitResult.isErr) {
        throw Exception('Failed to get translation unit');
      }

      final unit = unitResult.unwrap();

      // 2. Update version with new text
      final updatedVersion = currentVersion.copyWith(
        translatedText: newText,
        isManuallyEdited: true,
        status: newText.isEmpty
            ? TranslationVersionStatus.pending
            : TranslationVersionStatus.translated,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await versionRepo.update(updatedVersion);
      if (updateResult.isErr) {
        throw Exception('Failed to update translation version');
      }

      // 3. Record undo action using TranslationEditAction
      final historyAction = TranslationEditAction(
        versionId: currentVersion.id,
        oldValue: oldText,
        newValue: newText,
        timestamp: DateTime.now(),
        repository: versionRepo,
      );
      undoRedoManager.recordAction(historyAction);

      // Manually invalidate after recording (since action won't do it)
      _refreshProviders();

      // 5. Update TM with new translation (if not empty)
      if (newText.isNotEmpty) {
        // Get project language to determine language codes
        final projectLanguageId = await _getProjectLanguageId();
        final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
        final plResult = await projectLanguageRepo.getById(projectLanguageId);

        if (plResult.isOk) {
          final projectLanguage = plResult.unwrap();
          final languageRepo = ref.read(languageRepositoryProvider);
          final langResult = await languageRepo.getById(projectLanguage.languageId);

          if (langResult.isOk) {
            final language = langResult.unwrap();

            // Add to translation memory
            await tmService.addTranslation(
              sourceText: unit.sourceText,
              targetText: newText,
              targetLanguageCode: language.code,
              gameContext: unit.context,
            );
          }
        }
      }

      // 6. Refresh the data grid
      _refreshProviders();

      ref.read(loggingServiceProvider).info(
        'Translation updated',
        {'unitId': unitId, 'newText': newText.substring(0, newText.length > 50 ? 50 : newText.length)},
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to update translation',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Failed to update translation',
          e.toString(),
        );
      }
    }
  }

  Future<void> handleApplySuggestion(String unitId, String targetText) async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final tmService = ref.read(translationMemoryServiceProvider);
      final undoRedoManager = ref.read(undoRedoManagerProvider);

      // 1. Get current version and unit
      final versionsResult = await versionRepo.getByUnit(unitId);
      if (versionsResult.isErr) {
        throw Exception('Failed to get translation version');
      }

      final versions = versionsResult.unwrap();
      if (versions.isEmpty) {
        throw Exception('No translation version found for unit');
      }

      final currentVersion = versions.first;
      final oldText = currentVersion.translatedText ?? '';

      // Don't update if text hasn't changed
      if (oldText == targetText) return;

      final unitResult = await unitRepo.getById(unitId);
      if (unitResult.isErr) {
        throw Exception('Failed to get translation unit');
      }

      final unit = unitResult.unwrap();

      // 2. Update version with suggested text (mark as TM-sourced, not manually edited)
      final updatedVersion = currentVersion.copyWith(
        translatedText: targetText,
        isManuallyEdited: false, // TM suggestion, not manual edit
        status: TranslationVersionStatus.translated,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await versionRepo.update(updatedVersion);
      if (updateResult.isErr) {
        throw Exception('Failed to update translation version');
      }

      // 3. Record undo action using TranslationEditAction
      final historyAction = TranslationEditAction(
        versionId: currentVersion.id,
        oldValue: oldText,
        newValue: targetText,
        timestamp: DateTime.now(),
        repository: versionRepo,
      );
      undoRedoManager.recordAction(historyAction);

      // Manually invalidate after recording (since action won't do it)
      _refreshProviders();

      // 5. Increment TM usage count
      final projectLanguageId = await _getProjectLanguageId();
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
      final plResult = await projectLanguageRepo.getById(projectLanguageId);

      if (plResult.isOk) {
        final projectLanguage = plResult.unwrap();
        final languageRepo = ref.read(languageRepositoryProvider);
        final langResult = await languageRepo.getById(projectLanguage.languageId);

        if (langResult.isOk) {
          final language = langResult.unwrap();

          // Increment usage count for this TM entry
          // First find the exact match to get the entry ID
          final matchResult = await tmService.findExactMatch(
            sourceText: unit.sourceText,
            targetLanguageCode: language.code,
            gameContext: unit.context,
          );

          if (matchResult.isOk) {
            final match = matchResult.unwrap();
            if (match != null) {
              await tmService.incrementUsageCount(
                entryId: match.entryId,
              );
            }
          }
        }
      }

      // 6. Refresh the data grid
      _refreshProviders();

      ref.read(loggingServiceProvider).info(
        'TM suggestion applied',
        {'unitId': unitId, 'targetText': targetText.substring(0, targetText.length > 50 ? 50 : targetText.length)},
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to apply TM suggestion',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Failed to apply suggestion',
          e.toString(),
        );
      }
    }
  }

  // ========== TRANSLATION WORKFLOW HANDLERS ==========

  Future<void> handleTranslateAll() async {
    try {
      // Get the project_language_id from project_id and language_id
      final projectLanguageId = await _getProjectLanguageId();

      // Get all untranslated units for this project language
      final unitIds = await TranslationBatchHelper.getUntranslatedUnitIds(
        ref: ref,
        projectLanguageId: projectLanguageId,
      );

      if (unitIds.isEmpty) {
        if (!mounted) return;
        EditorDialogs.showNoUntranslatedDialog(context);
        return;
      }

      // Check if provider is configured
      final hasProvider = await TranslationBatchHelper.checkProviderConfigured(
        ref: ref,
        getSettings: () => ref.read(llmProviderSettingsProvider.future),
      );
      if (!hasProvider) {
        if (!mounted) return;
        showProviderSetupDialog();
        return;
      }

      // Show confirmation dialog
      if (!mounted) return;
      final confirmed = await EditorDialogs.showTranslateConfirmationDialog(
        context,
        title: 'Translate All',
        message: 'Translate ${unitIds.length} untranslated units?',
      );

      if (!confirmed) return;

      // Create batch and start translation
      await createAndStartBatch(unitIds);
    } catch (e) {
      if (!mounted) return;
      EditorDialogs.showErrorDialog(
        context,
        'Failed to start translation',
        e.toString(),
      );
    }
  }

  Future<void> handleTranslateSelected() async {
    final selectionState = ref.read(editorSelectionProvider);

    if (!selectionState.hasSelection) {
      EditorDialogs.showNoSelectionDialog(context);
      return;
    }

    try {
      // Filter selected units to only untranslated ones
      final selectedIds = selectionState.selectedUnitIds.toList();
      final untranslatedIds = await TranslationBatchHelper.filterUntranslatedUnits(
        ref: ref,
        unitIds: selectedIds,
      );

      if (untranslatedIds.isEmpty) {
        if (!mounted) return;
        EditorDialogs.showAllTranslatedDialog(context);
        return;
      }

      // Check if provider is configured
      final hasProvider = await TranslationBatchHelper.checkProviderConfigured(
        ref: ref,
        getSettings: () => ref.read(llmProviderSettingsProvider.future),
      );
      if (!hasProvider) {
        if (!mounted) return;
        showProviderSetupDialog();
        return;
      }

      // Show confirmation dialog
      if (!mounted) return;
      final confirmed = await EditorDialogs.showTranslateConfirmationDialog(
        context,
        title: 'Translate Selected',
        message: 'Translate ${untranslatedIds.length} untranslated units '
            '(${selectedIds.length - untranslatedIds.length} already translated)?',
      );

      if (!confirmed) return;

      // Create batch and start translation
      await createAndStartBatch(untranslatedIds);
    } catch (e) {
      if (!mounted) return;
      EditorDialogs.showErrorDialog(
        context,
        'Failed to start translation',
        e.toString(),
      );
    }
  }

  /// Force retranslate selected units (including already translated ones)
  Future<void> handleForceRetranslateSelected() async {
    final selectionState = ref.read(editorSelectionProvider);

    if (!selectionState.hasSelection) {
      EditorDialogs.showNoSelectionDialog(context);
      return;
    }

    try {
      final selectedIds = selectionState.selectedUnitIds.toList();

      if (selectedIds.isEmpty) {
        return;
      }

      // Check if provider is configured
      final hasProvider = await TranslationBatchHelper.checkProviderConfigured(
        ref: ref,
        getSettings: () => ref.read(llmProviderSettingsProvider.future),
      );
      if (!hasProvider) {
        if (!mounted) return;
        showProviderSetupDialog();
        return;
      }

      // Show confirmation dialog with warning about overwriting
      if (!mounted) return;
      final confirmed = await EditorDialogs.showTranslateConfirmationDialog(
        context,
        title: 'Force Retranslate',
        message: 'Retranslate ${selectedIds.length} unit(s)?\n\n'
            'Warning: This will overwrite existing translations.',
      );

      if (!confirmed) return;

      // Create batch and start translation (no filtering)
      await createAndStartBatch(selectedIds);
    } catch (e) {
      if (!mounted) return;
      EditorDialogs.showErrorDialog(
        context,
        'Failed to start translation',
        e.toString(),
      );
    }
  }

  Future<void> handleValidate() async {
    try {
      // Get the project_language_id from project_id and language_id
      final projectLanguageId = await _getProjectLanguageId();
      
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final validationService = ref.read(validationServiceProvider);

      // 1. Get all translations for this project language
      final versionsResult = await versionRepo.getByProjectLanguage(projectLanguageId);
      if (versionsResult.isErr) {
        throw Exception('Failed to load translations');
      }

      final versions = versionsResult.unwrap();
      
      ref.read(loggingServiceProvider).info(
        'Validation starting',
        {'totalVersions': versions.length},
      );

      if (versions.isEmpty) {
        if (mounted) {
          EditorDialogs.showInfoDialog(
            context,
            'No translations to validate',
            'Please add some translations first.',
          );
        }
        return;
      }

      // Show progress dialog
      if (!mounted) return;
      int validatedCount = 0;
      int skippedCount = 0;
      int totalIssuesCount = 0;
      final allIssues = <batch.ValidationIssue>[];

      // Start validation
      for (final version in versions) {
        if (version.translatedText == null || version.translatedText!.isEmpty) {
          skippedCount++;
          continue; // Skip empty translations
        }

        // Get source text
        final unitResult = await unitRepo.getById(version.unitId);
        if (unitResult.isErr) {
          ref.read(loggingServiceProvider).warning(
            'Failed to load unit for validation',
            {'versionId': version.id, 'unitId': version.unitId},
          );
          skippedCount++;
          continue;
        }

        final unit = unitResult.unwrap();

        // 2. Run validation service
        final validationResult = await validationService.validateTranslation(
          sourceText: unit.sourceText,
          translatedText: version.translatedText!,
          context: unit.context,
        );

        if (validationResult.isOk) {
          final issues = validationResult.unwrap();

          // 3. Update validation_issues field if there are issues
          if (issues.isNotEmpty) {
            final issuesJson = issues
                .map((issue) => {
                      'type': issue.type,
                      'severity': issue.severity.toString(),
                      'description': issue.description,
                      'suggestion': issue.suggestion,
                      'autoFixable': issue.autoFixable,
                      'autoFixValue': issue.autoFixValue,
                    })
                .toList();

            final updatedVersion = version.copyWith(
              validationIssues: issuesJson.toString(),
              updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );

            await versionRepo.update(updatedVersion);
            totalIssuesCount += issues.length;

            // Collect issues for dialog display
            for (final issue in issues) {
              allIssues.add(batch.ValidationIssue(
                unitKey: unit.key,
                unitId: unit.id,
                severity: issue.severity == validation.ValidationSeverity.error
                    ? batch.ValidationSeverity.error
                    : batch.ValidationSeverity.warning,
                issueType: _getIssueTypeLabel(issue.type),
                description: issue.description,
                canAutoFix: issue.autoFixable,
              ));
            }
          } else {
            // Clear validation issues if none found
            if (version.validationIssues != null) {
              final updatedVersion = version.copyWith(
                validationIssues: null,
                updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              );
              await versionRepo.update(updatedVersion);
            }
          }

          validatedCount++;
        }
      }

      // Refresh the data grid
      _refreshProviders();

      if (mounted) {
        // 4. Set validation results and show detailed dialog
        final passedCount = validatedCount - allIssues.map((i) => i.unitId).toSet().length;
        
        ref.read(loggingServiceProvider).debug(
          'Setting validation results',
          {
            'issuesCount': allIssues.length,
            'validatedCount': validatedCount,
            'passedCount': passedCount,
          },
        );

        ref.read(batch.batchValidationResultsProvider.notifier).setResults(
          issues: allIssues,
          totalValidated: validatedCount,
          passedCount: passedCount,
        );

        // Verify state was set
        final verifyState = ref.read(batch.batchValidationResultsProvider);
        ref.read(loggingServiceProvider).debug(
          'Verification after setting results',
          {
            'stateIssuesCount': verifyState.issues.length,
            'stateTotalValidated': verifyState.totalValidated,
            'statePassedCount': verifyState.passedCount,
          },
        );

        // Show detailed results dialog
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (context) => BatchValidationDialog(
            issues: allIssues,
            totalValidated: validatedCount,
            passedCount: passedCount,
            onAutoFix: () {
              // TODO: Implement auto-fix functionality
              Navigator.of(context).pop();
            },
            onExportReport: (filePath) async {
              await _exportValidationReport(filePath, allIssues);
            },
          ),
        );
      }

      ref.read(loggingServiceProvider).info(
        'Validation completed',
        {
          'totalVersions': versions.length,
          'validatedCount': validatedCount,
          'skippedCount': skippedCount,
          'issuesCount': totalIssuesCount,
          'affectedUnits': allIssues.map((i) => i.unitId).toSet().length,
        },
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to validate translations',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Validation failed',
          e.toString(),
        );
      }
    }
  }

  Future<void> handleExport() async {
    try {
      // Show export dialog with options
      final exportFormat = await EditorDialogs.showExportDialog(context);
      if (exportFormat == null) return; // User cancelled

      // Get the project_language_id from project_id and language_id
      final projectLanguageId = await _getProjectLanguageId();

      // Get export orchestrator service
      final exportService = ref.read(exportOrchestratorServiceProvider);
      final languageRepo = ref.read(languageRepositoryProvider);
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);

      // Get project language info
      final plResult = await projectLanguageRepo.getById(projectLanguageId);
      if (plResult.isErr) {
        throw Exception('Failed to load project language');
      }

      final projectLanguage = plResult.unwrap();
      final langResult = await languageRepo.getById(projectLanguage.languageId);
      if (langResult.isErr) {
        throw Exception('Failed to load language');
      }

      final language = langResult.unwrap();
      final languageCodes = [language.code];

      // Get default export directory from settings
      final outputPath = 'exports'; // TODO: Get from settings or file picker

      // Show progress and export based on format
      if (!mounted) return;

      switch (exportFormat) {
        case 'pack':
          final result = await exportService.exportToPack(
            projectId: projectId,
            languageCodes: languageCodes,
            outputPath: outputPath,
            validatedOnly: false,
            onProgress: (step, progress, {currentLanguage, currentIndex, total}) {
              // TODO: Show progress in dialog
            },
          );

          result.when(
            ok: (exportResult) {
              if (mounted) {
                EditorDialogs.showInfoDialog(
                  context,
                  'Export Complete',
                  'Exported ${exportResult.entryCount} translations to:\n${exportResult.outputPath}',
                );
              }
            },
            err: (error) {
              throw Exception(error.message);
            },
          );
          break;

        case 'csv':
          final result = await exportService.exportToCsv(
            projectId: projectId,
            languageCodes: languageCodes,
            outputPath: outputPath,
            validatedOnly: false,
          );

          result.when(
            ok: (exportResult) {
              if (mounted) {
                EditorDialogs.showInfoDialog(
                  context,
                  'Export Complete',
                  'Exported ${exportResult.entryCount} translations to:\n${exportResult.outputPath}',
                );
              }
            },
            err: (error) {
              throw Exception(error.message);
            },
          );
          break;

        case 'excel':
          final result = await exportService.exportToExcel(
            projectId: projectId,
            languageCodes: languageCodes,
            outputPath: outputPath,
            validatedOnly: false,
          );

          result.when(
            ok: (exportResult) {
              if (mounted) {
                EditorDialogs.showInfoDialog(
                  context,
                  'Export Complete',
                  'Exported ${exportResult.entryCount} translations to:\n${exportResult.outputPath}',
                );
              }
            },
            err: (error) {
              throw Exception(error.message);
            },
          );
          break;

        default:
          throw Exception('Unsupported export format: $exportFormat');
      }

      ref.read(loggingServiceProvider).info(
        'Export completed',
        {'format': exportFormat, 'languageCodes': languageCodes},
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to export translations',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Export failed',
          e.toString(),
        );
      }
    }
  }

  // ========== UNDO/REDO HANDLERS ==========

  Future<void> handleUndo() async {
    final undoRedoManager = ref.read(undoRedoManagerProvider);

    try {
      final success = await undoRedoManager.undo();
      if (success && mounted) {
        ToastNotificationService.showSuccess(
          context,
          'Undo successful',
        );
      }
    } catch (e) {
      if (mounted) {
        ToastNotificationService.showError(
          context,
          'Undo failed: $e',
        );
      }
    }
  }

  Future<void> handleRedo() async {
    final undoRedoManager = ref.read(undoRedoManagerProvider);

    try {
      final success = await undoRedoManager.redo();
      if (success && mounted) {
        ToastNotificationService.showSuccess(
          context,
          'Redo successful',
        );
      }
    } catch (e) {
      if (mounted) {
        ToastNotificationService.showError(
          context,
          'Redo failed: $e',
        );
      }
    }
  }

  // ========== BATCH CREATION ==========

  void showProviderSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => ProviderSetupDialog(
        onGoToSettings: () {
          // Navigate to settings screen
          context.go(AppRoutes.settings);
        },
      ),
    );
  }

  Future<void> createAndStartBatch(List<String> unitIds) async {
    if (!mounted) return;

    try {
      final orchestrator = ref.read(translationOrchestratorProvider);

      // Navigate to progress screen immediately
      // Pass a preparation callback that will be executed by the screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TranslationProgressScreen(
            orchestrator: orchestrator,
            onComplete: () {
              // Refresh DataGrid data and project stats
              _refreshProviders();
            },
            preparationCallback: () async {
              // All preparation happens here, asynchronously
              
              // Get the project_language_id from project_id and language_id
              final projectLanguageId = await _getProjectLanguageId();

              // Get the selected LLM model from the dropdown
              final selectedModelId = ref.read(selectedLlmModelProvider);
              final modelRepo = ref.read(llmProviderModelRepositoryProvider);

              String providerCode;
              String? modelId;

              if (selectedModelId != null) {
                // Use the selected model
                final modelResult = await modelRepo.getById(selectedModelId);
                if (modelResult.isErr) {
                  throw Exception('Failed to load selected model');
                }
                final model = modelResult.unwrap();
                providerCode = model.providerCode;
                modelId = model.modelId;

                // DEBUG: Log selected model details
                print('[DEBUG] Selected model from dropdown:');
                print('[DEBUG]   - selectedModelId (DB ID): $selectedModelId');
                print('[DEBUG]   - model.displayName: ${model.displayName}');
                print('[DEBUG]   - model.providerCode: ${model.providerCode}');
                print('[DEBUG]   - model.modelId (API model ID): ${model.modelId}');
              } else {
                // No model selected in dropdown, fall back to default from settings
                final llmSettings = await ref.read(llmProviderSettingsProvider.future);
                providerCode = llmSettings['active_llm_provider'] ?? '';

                if (providerCode.isEmpty) {
                  throw Exception('No LLM provider selected');
                }
                // modelId stays null - will use provider's default
              }

              // Convert provider code to database provider ID
              final providerId = 'provider_$providerCode';

              // Create batch entities
              final batchId = await TranslationBatchHelper.createAndPrepareBatch(
                ref: ref,
                projectLanguageId: projectLanguageId,
                unitIds: unitIds,
                providerId: providerId,
                onError: () {
                  throw Exception('Could not create translation batch');
                },
              );

              if (batchId == null) {
                throw Exception('Failed to create batch');
              }

              // Get translation settings
              final settings = ref.read(translationSettingsProvider);

              // Build translation context
              final translationContext = await TranslationBatchHelper.buildTranslationContext(
                ref: ref,
                projectId: projectId,
                projectLanguageId: projectLanguageId,
                providerId: providerId,
                modelId: modelId,
                unitsPerBatch: settings.unitsPerBatch,
                parallelBatches: settings.parallelBatches,
              );

              return (batchId: batchId, context: translationContext);
            },
          ),
        ),
      );
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to navigate to translation screen',
        e,
        stackTrace,
      );
      if (mounted) {
        EditorDialogs.showErrorDialog(
          context,
          'Failed to start translation',
          e.toString(),
        );
      }
    }
  }

  /// Handle translation settings button click
  Future<void> handleTranslationSettings() async {
    if (!mounted) return;

    // Ensure settings are loaded before showing dialog
    final currentSettings = await ref.read(translationSettingsProvider.notifier).ensureLoaded();
    
    if (!mounted) return;
    
    final result = await showTranslationSettingsDialog(
      context,
      currentUnitsPerBatch: currentSettings.unitsPerBatch,
      currentParallelBatches: currentSettings.parallelBatches,
    );

    debugPrint('[TranslationSettings] Dialog result: $result');
    
    if (result != null && mounted) {
      debugPrint('[TranslationSettings] Calling updateSettings with units=${result['unitsPerBatch']}, parallel=${result['parallelBatches']}');
      await ref.read(translationSettingsProvider.notifier).updateSettings(
        unitsPerBatch: result['unitsPerBatch']!,
        parallelBatches: result['parallelBatches']!,
      );

      ToastNotificationService.showSuccess(
        context,
        'Translation settings updated',
      );
    }
  }
}
