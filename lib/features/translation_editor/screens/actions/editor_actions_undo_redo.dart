import 'package:twmt/i18n/strings.g.dart';
import '../../../../services/toast_notification_service.dart';
import '../../providers/editor_providers.dart';
import 'editor_actions_base.dart';

/// Mixin handling undo/redo operations
mixin EditorActionsUndoRedo on EditorActionsBase {
  Future<void> handleUndo() async {
    final undoRedoManager = ref.read(undoRedoManagerProvider);

    try {
      final success = await undoRedoManager.undo();
      if (!context.mounted) return;
      if (success) {
        ToastNotificationService.showSuccess(context, t.translationEditor.actions.undoSuccess);
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastNotificationService.showError(context, t.translationEditor.actions.undoFailed(error: e.toString()));
    }
  }

  Future<void> handleRedo() async {
    final undoRedoManager = ref.read(undoRedoManagerProvider);

    try {
      final success = await undoRedoManager.redo();
      if (!context.mounted) return;
      if (success) {
        ToastNotificationService.showSuccess(context, t.translationEditor.actions.redoSuccess);
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastNotificationService.showError(context, t.translationEditor.actions.redoFailed(error: e.toString()));
    }
  }
}
