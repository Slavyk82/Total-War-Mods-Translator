import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../../providers/history/history_providers.dart';
import 'history_timeline_panel.dart';

/// Toolbar widget providing undo/redo functionality and history access
///
/// Features:
/// - Undo button (Ctrl+Z)
/// - Redo button (Ctrl+Y)
/// - History button to show timeline panel
/// - Automatic enable/disable based on stack state
/// - Tooltips with keyboard shortcuts
class UndoRedoToolbar extends ConsumerWidget {
  /// ID of the translation version being edited
  final String versionId;

  /// Current translated text (for history panel)
  final String currentTranslatedText;

  /// Callback when history panel should be shown
  final VoidCallback? onShowHistory;

  const UndoRedoToolbar({
    super.key,
    required this.versionId,
    required this.currentTranslatedText,
    this.onShowHistory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUndo = ref.watch(canUndoProvider);
    final canRedo = ref.watch(canRedoProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Undo button
        Tooltip(
          message: 'Undo (Ctrl+Z)',
          child: _buildToolbarButton(
            context,
            icon: FluentIcons.arrow_undo_24_regular,
            onPressed: canUndo ? () => _handleUndo(context, ref) : null,
            enabled: canUndo,
          ),
        ),

        const SizedBox(width: 4),

        // Redo button
        Tooltip(
          message: 'Redo (Ctrl+Y)',
          child: _buildToolbarButton(
            context,
            icon: FluentIcons.arrow_redo_24_regular,
            onPressed: canRedo ? () => _handleRedo(context, ref) : null,
            enabled: canRedo,
          ),
        ),

        const SizedBox(width: 8),

        // Divider
        Container(
          width: 1,
          height: 24,
          color: Theme.of(context).dividerColor,
        ),

        const SizedBox(width: 8),

        // History button
        Tooltip(
          message: 'View history',
          child: _buildToolbarButton(
            context,
            icon: FluentIcons.history_24_regular,
            onPressed: () => _handleShowHistory(context),
            enabled: true,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbarButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
    required bool enabled,
  }) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: enabled
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enabled
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Future<void> _handleUndo(BuildContext context, WidgetRef ref) async {
    try {
      final notifier = ref.read(undoRedoManagerProvider.notifier);
      final success = await notifier.undo();

      if (context.mounted) {
        if (success) {
          FluentToast.success(context, 'Undone');
        } else {
          FluentToast.info(context, 'Nothing to undo');
        }
      }
    } catch (e) {
      if (context.mounted) {
        FluentToast.error(context, 'Failed to undo: $e');
      }
    }
  }

  Future<void> _handleRedo(BuildContext context, WidgetRef ref) async {
    try {
      final notifier = ref.read(undoRedoManagerProvider.notifier);
      final success = await notifier.redo();

      if (context.mounted) {
        if (success) {
          FluentToast.success(context, 'Redone');
        } else {
          FluentToast.info(context, 'Nothing to redo');
        }
      }
    } catch (e) {
      if (context.mounted) {
        FluentToast.error(context, 'Failed to redo: $e');
      }
    }
  }

  void _handleShowHistory(BuildContext context) {
    if (onShowHistory != null) {
      onShowHistory!();
    } else {
      // Default behavior: show as bottom sheet or side panel
      showDialog(
        context: context,
        builder: (context) => Dialog(
          alignment: Alignment.centerRight,
          insetPadding: EdgeInsets.zero,
          child: HistoryTimelinePanel(
            versionId: versionId,
            currentTranslatedText: currentTranslatedText,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }
}

