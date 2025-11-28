import 'package:flutter/material.dart';
import '../../../../services/translation/models/translation_context.dart';
import '../../../projects/providers/project_detail_providers.dart';
import '../../../settings/providers/settings_providers.dart';
import '../../providers/editor_providers.dart';
import '../../providers/translation_settings_provider.dart';
import '../../utils/translation_batch_helper.dart';
import '../../widgets/editor_dialogs.dart';
import '../../widgets/provider_setup_dialog.dart';
import '../translation_progress_screen.dart';
import 'editor_actions_base.dart';

/// Mixin handling translation workflow operations
mixin EditorActionsTranslation on EditorActionsBase {
  Future<void> handleTranslateAll() async {
    try {
      final projectLanguageId = await getProjectLanguageId();

      final unitIds = await TranslationBatchHelper.getUntranslatedUnitIds(
        ref: ref,
        projectLanguageId: projectLanguageId,
      );

      if (unitIds.isEmpty) {
        if (!mounted) return;
        EditorDialogs.showNoUntranslatedDialog(context);
        return;
      }

      if (!await _checkProviderConfigured()) return;

      if (!mounted) return;
      final confirmed = await EditorDialogs.showTranslateConfirmationDialog(
        context,
        title: 'Translate All',
        message: 'Translate ${unitIds.length} untranslated units?',
      );

      if (!confirmed) return;
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
      final projectLanguageId = await getProjectLanguageId();
      final selectedIds = selectionState.selectedUnitIds.toList();
      final untranslatedIds = await TranslationBatchHelper.filterUntranslatedUnits(
        ref: ref,
        unitIds: selectedIds,
        projectLanguageId: projectLanguageId,
      );

      if (untranslatedIds.isEmpty) {
        if (!mounted) return;
        EditorDialogs.showAllTranslatedDialog(context);
        return;
      }

      if (!await _checkProviderConfigured()) return;

      if (!mounted) return;
      final confirmed = await EditorDialogs.showTranslateConfirmationDialog(
        context,
        title: 'Translate Selected',
        message: 'Translate ${untranslatedIds.length} untranslated units '
            '(${selectedIds.length - untranslatedIds.length} already translated)?',
      );

      if (!confirmed) return;
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

  Future<void> handleForceRetranslateSelected() async {
    print('[DEBUG] handleForceRetranslateSelected called');
    final selectionState = ref.read(editorSelectionProvider);
    print('[DEBUG] selectionState.hasSelection: ${selectionState.hasSelection}');
    print('[DEBUG] selectionState.selectedUnitIds.length: ${selectionState.selectedUnitIds.length}');

    if (!selectionState.hasSelection) {
      print('[DEBUG] No selection - showing dialog');
      EditorDialogs.showNoSelectionDialog(context);
      return;
    }

    try {
      final selectedIds = selectionState.selectedUnitIds.toList();
      print('[DEBUG] selectedIds count: ${selectedIds.length}');
      if (selectedIds.isEmpty) {
        print('[DEBUG] selectedIds is empty - returning');
        return;
      }

      print('[DEBUG] Checking provider configured...');
      if (!await _checkProviderConfigured()) {
        print('[DEBUG] Provider not configured - returning');
        return;
      }

      if (!mounted) {
        print('[DEBUG] Not mounted - returning');
        return;
      }
      print('[DEBUG] Showing confirmation dialog...');
      final confirmed = await EditorDialogs.showTranslateConfirmationDialog(
        context,
        title: 'Force Retranslate',
        message: 'Retranslate ${selectedIds.length} unit(s)?\n\n'
            'Warning: This will overwrite existing translations.',
      );
      print('[DEBUG] Confirmation result: $confirmed');

      if (!confirmed) {
        print('[DEBUG] Not confirmed - returning');
        return;
      }
      print('[DEBUG] Creating and starting batch with ${selectedIds.length} units');
      await createAndStartBatch(selectedIds);
      print('[DEBUG] createAndStartBatch completed');
    } catch (e, stackTrace) {
      print('[DEBUG] Error in handleForceRetranslateSelected: $e');
      print('[DEBUG] Stack trace: $stackTrace');
      if (!mounted) return;
      EditorDialogs.showErrorDialog(
        context,
        'Failed to start translation',
        e.toString(),
      );
    }
  }

  Future<bool> _checkProviderConfigured() async {
    final hasProvider = await TranslationBatchHelper.checkProviderConfigured(
      ref: ref,
      getSettings: () => ref.read(llmProviderSettingsProvider.future),
    );

    if (!hasProvider) {
      if (!mounted) return false;
      showProviderSetupDialog();
      return false;
    }
    return true;
  }

  void showProviderSetupDialog();
  Future<void> createAndStartBatch(List<String> unitIds);
}

/// Mixin handling batch creation and translation orchestration
mixin EditorActionsBatch on EditorActionsBase {
  void showProviderSetupDialogImpl() {
    showDialog(
      context: context,
      builder: (context) => ProviderSetupDialog(
        onGoToSettings: () {
          // Navigate to settings screen handled by caller
        },
      ),
    );
  }

  Future<void> createAndStartBatchImpl(List<String> unitIds) async {
    if (!mounted) return;

    try {
      final orchestrator = ref.read(translationOrchestratorProvider);

      // Get project name for display
      final projectDetails = await ref.read(projectDetailsProvider(projectId).future);
      final projectName = projectDetails.project.name;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TranslationProgressScreen(
            orchestrator: orchestrator,
            onComplete: () => refreshProviders(),
            preparationCallback: () => _prepareBatch(unitIds),
            projectName: projectName,
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

  Future<({String batchId, TranslationContext context})> _prepareBatch(
      List<String> unitIds) async {
    final projectLanguageId = await getProjectLanguageId();
    final selectedModelId = ref.read(selectedLlmModelProvider);
    final modelRepo = ref.read(llmProviderModelRepositoryProvider);

    String providerCode;
    String? modelId;

    if (selectedModelId != null) {
      final modelResult = await modelRepo.getById(selectedModelId);
      if (modelResult.isErr) {
        throw Exception('Failed to load selected model');
      }
      final model = modelResult.unwrap();
      providerCode = model.providerCode;
      modelId = model.modelId;
    } else {
      final llmSettings = await ref.read(llmProviderSettingsProvider.future);
      providerCode = llmSettings['active_llm_provider'] ?? '';

      if (providerCode.isEmpty) {
        throw Exception('No LLM provider selected');
      }
    }

    final providerId = 'provider_$providerCode';

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

    final settings = ref.read(translationSettingsProvider);

    final translationContext = await TranslationBatchHelper.buildTranslationContext(
      ref: ref,
      projectId: projectId,
      projectLanguageId: projectLanguageId,
      providerId: providerId,
      modelId: modelId,
      unitsPerBatch: settings.unitsPerBatch,
      parallelBatches: settings.parallelBatches,
      skipTranslationMemory: settings.skipTranslationMemory,
    );

    return (batchId: batchId, context: translationContext);
  }
}
