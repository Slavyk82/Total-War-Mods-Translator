import 'package:flutter/foundation.dart';
import '../../../../services/toast_notification_service.dart';
import '../../providers/editor_providers.dart';
import '../../providers/translation_settings_provider.dart';
import '../../widgets/translation_settings_dialog.dart';
import 'editor_actions_base.dart';

/// Mixin handling undo/redo operations
mixin EditorActionsUndoRedo on EditorActionsBase {
  Future<void> handleUndo() async {
    final undoRedoManager = ref.read(undoRedoManagerProvider);

    try {
      final success = await undoRedoManager.undo();
      if (!context.mounted) return;
      if (success) {
        ToastNotificationService.showSuccess(context, 'Undo successful');
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastNotificationService.showError(context, 'Undo failed: $e');
    }
  }

  Future<void> handleRedo() async {
    final undoRedoManager = ref.read(undoRedoManagerProvider);

    try {
      final success = await undoRedoManager.redo();
      if (!context.mounted) return;
      if (success) {
        ToastNotificationService.showSuccess(context, 'Redo successful');
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastNotificationService.showError(context, 'Redo failed: $e');
    }
  }

  Future<void> handleTranslationSettings() async {
    if (!context.mounted) return;

    final currentSettings =
        await ref.read(translationSettingsProvider.notifier).ensureLoaded();

    if (!context.mounted) return;

    final result = await showTranslationSettingsDialog(
      context,
      currentUnitsPerBatch: currentSettings.unitsPerBatch,
      currentParallelBatches: currentSettings.parallelBatches,
    );

    debugPrint(
        '[TranslationSettings] Dialog result: $result');

    if (result == null) return;
    if (!context.mounted) return;

    debugPrint(
        '[TranslationSettings] Calling updateSettings with units=${result['unitsPerBatch']}, parallel=${result['parallelBatches']}');
    await ref.read(translationSettingsProvider.notifier).updateSettings(
      unitsPerBatch: result['unitsPerBatch']!,
      parallelBatches: result['parallelBatches']!,
    );

    if (!context.mounted) return;

    ToastNotificationService.showSuccess(
      context,
      'Translation settings updated',
    );
  }
}
