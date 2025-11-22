import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import '../../../services/toast_notification_service.dart';
import '../../../services/history/undo_redo_manager.dart';
import '../../../models/domain/translation_version.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/editor_providers.dart';
import '../widgets/editor_dialogs.dart';
import '../widgets/provider_setup_dialog.dart';
import '../utils/translation_batch_helper.dart';

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
      ref.invalidate(translationRowsProvider(projectId, languageId));

      // 5. Update TM with new translation (if not empty)
      if (newText.isNotEmpty) {
        // Get project language to determine language codes
        final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
        final plResult = await projectLanguageRepo.getById(languageId);

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
      ref.invalidate(translationRowsProvider(projectId, languageId));

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
      ref.invalidate(translationRowsProvider(projectId, languageId));

      // 5. Increment TM usage count
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);
      final plResult = await projectLanguageRepo.getById(languageId);

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
      ref.invalidate(translationRowsProvider(projectId, languageId));

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
      // Get all untranslated units for this project language
      final unitIds = await TranslationBatchHelper.getUntranslatedUnitIds(
        ref: ref,
        projectLanguageId: languageId,
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

  Future<void> handleValidate() async {
    try {
      final versionRepo = ref.read(translationVersionRepositoryProvider);
      final unitRepo = ref.read(translationUnitRepositoryProvider);
      final validationService = ref.read(validationServiceProvider);

      // 1. Get all translations for this project language
      final versionsResult = await versionRepo.getByProjectLanguage(languageId);
      if (versionsResult.isErr) {
        throw Exception('Failed to load translations');
      }

      final versions = versionsResult.unwrap();
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
      int issuesCount = 0;

      // Start validation
      for (final version in versions) {
        if (version.translatedText == null || version.translatedText!.isEmpty) {
          continue; // Skip empty translations
        }

        // Get source text
        final unitResult = await unitRepo.getById(version.unitId);
        if (unitResult.isErr) continue;

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
            issuesCount += issues.length;
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
      ref.invalidate(translationRowsProvider(projectId, languageId));

      // 4. Show results dialog
      if (mounted) {
        EditorDialogs.showInfoDialog(
          context,
          'Validation Complete',
          'Validated $validatedCount translations.\n'
              'Found $issuesCount validation issues.',
        );
      }

      ref.read(loggingServiceProvider).info(
        'Validation completed',
        {'validatedCount': validatedCount, 'issuesCount': issuesCount},
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

      // Get export orchestrator service
      final exportService = ref.read(exportOrchestratorServiceProvider);
      final languageRepo = ref.read(languageRepositoryProvider);
      final projectLanguageRepo = ref.read(projectLanguageRepositoryProvider);

      // Get project language info
      final plResult = await projectLanguageRepo.getById(languageId);
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
      // BUG FIX: Get the project_language_id (UUID), not the language_id!
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

      final projectLanguageId = projectLanguage.id;

      final orchestrator = ref.read(translationOrchestratorProvider);

      // Get the selected LLM model from the dropdown
      // If no model is selected, use the default model
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
      // Provider codes: "anthropic", "openai", "deepl"
      // Database expects: "provider_anthropic", "provider_openai", "provider_deepl"
      final providerId = 'provider_$providerCode';

      // Create batch entities
      final batchId = await TranslationBatchHelper.createAndPrepareBatch(
        ref: ref,
        projectLanguageId: projectLanguageId,
        unitIds: unitIds,
        providerId: providerId,
        onError: () {
          if (mounted) {
            EditorDialogs.showErrorDialog(
              context,
              'Failed to create batch',
              'Could not create translation batch',
            );
          }
        },
      );

      if (batchId == null) return;

      // Build translation context
      final translationContext = await TranslationBatchHelper.buildTranslationContext(
        ref: ref,
        projectId: projectId,
        projectLanguageId: projectLanguageId,
        providerId: providerId,
        modelId: modelId,
      );

      // Start translation with orchestrator
      if (mounted) {
        EditorDialogs.showTranslationProgressDialog(
          context,
          batchId: batchId,
          orchestrator: orchestrator,
          translationContext: translationContext,
          onComplete: () {
            // Refresh DataGrid - handled by parent screen
          },
        );
      }
    } catch (e, stackTrace) {
      ref.read(loggingServiceProvider).error(
        'Failed to create and start batch',
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
}
