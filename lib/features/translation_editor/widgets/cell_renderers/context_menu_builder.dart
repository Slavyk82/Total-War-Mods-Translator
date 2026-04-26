import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../providers/editor_providers.dart';
import '../../../../providers/shared/logging_providers.dart';

/// Context menu builder for DataGrid rows
///
/// Provides context menu items for translation editor operations
class ContextMenuBuilder {
  /// Show context menu for selected rows
  static void showContextMenu({
    required BuildContext context,
    required WidgetRef ref,
    required Offset position,
    required TranslationRow row,
    required int selectionCount,
    required VoidCallback onSelectAll,
    required Future<void> Function() onClear,
    required Future<void> Function() onViewHistory,
    required Future<void> Function() onDelete,
    Future<void> Function()? onForceRetranslate,
    Future<void> Function()? onViewPrompt,
    Future<void> Function()? onMarkAsTranslated,
  }) {
    final hasSelection = selectionCount > 0;
    final isSingleSelection = selectionCount == 1;
    final tokens = context.tokens;
    // Disabled colour for icons / labels: faint token so it reads as inactive
    // against the menu surface in both Atelier and Forge.
    final disabledColor = tokens.textFaint;

    PopupMenuItem<String> buildItem({
      required String value,
      required IconData icon,
      required String label,
      bool enabled = true,
      Color? iconColor,
      Color? labelColor,
    }) {
      final effectiveIcon = enabled ? (iconColor ?? tokens.text) : disabledColor;
      final effectiveLabel = enabled ? (labelColor ?? tokens.text) : disabledColor;
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 16, color: effectiveIcon),
            const SizedBox(width: 8),
            Text(
              label,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: effectiveLabel,
              ),
            ),
          ],
        ),
      );
    }

    showMenu<String>(
      context: context,
      color: tokens.panel2,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.border),
      ),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: <PopupMenuEntry<String>>[
        buildItem(
          value: 'select_all',
          icon: FluentIcons.select_all_on_24_regular,
          label: t.translationEditor.contextMenu.selectAll,
        ),
        if (onForceRetranslate != null)
          buildItem(
            value: 'force_retranslate',
            icon: FluentIcons.arrow_sync_24_regular,
            label: selectionCount > 1
                ? t.translationEditor.contextMenu.forceRetranslateCount(count: selectionCount)
                : t.translationEditor.contextMenu.forceRetranslate,
            enabled: hasSelection,
          ),
        if (onMarkAsTranslated != null)
          buildItem(
            value: 'mark_as_translated',
            icon: FluentIcons.checkmark_circle_24_regular,
            label: selectionCount > 1
                ? t.translationEditor.contextMenu.markAsTranslatedCount(count: selectionCount)
                : t.translationEditor.contextMenu.markAsTranslated,
            enabled: hasSelection,
            iconColor: tokens.ok,
            labelColor: tokens.ok,
          ),
        buildItem(
          value: 'clear',
          icon: FluentIcons.delete_24_regular,
          label: selectionCount > 1
              ? t.translationEditor.contextMenu.clearTranslationCount(count: selectionCount)
              : t.translationEditor.contextMenu.clearTranslation,
          enabled: hasSelection,
        ),
        PopupMenuDivider(height: 8, color: tokens.border),
        if (isSingleSelection)
          buildItem(
            value: 'history',
            icon: FluentIcons.history_24_regular,
            label: t.translationEditor.contextMenu.viewHistory,
          ),
        if (isSingleSelection && onViewPrompt != null)
          buildItem(
            value: 'view_prompt',
            icon: FluentIcons.code_24_regular,
            label: t.translationEditor.contextMenu.viewPrompt,
          ),
        if (isSingleSelection)
          PopupMenuDivider(height: 8, color: tokens.border),
        buildItem(
          value: 'delete',
          icon: FluentIcons.delete_24_regular,
          label: selectionCount > 1
              ? t.translationEditor.contextMenu.deleteCount(count: selectionCount)
              : t.common.actions.delete,
          enabled: hasSelection,
          iconColor: tokens.err,
          labelColor: tokens.err,
        ),
      ],
    ).then((value) async {
      if (value == null) return;

      final logging = ref.read(loggingServiceProvider);

      switch (value) {
        case 'select_all':
          onSelectAll();
          break;
        case 'force_retranslate':
          logging.debug('Context menu: force_retranslate clicked', {
            'selectionCount': selectionCount,
          });
          if (onForceRetranslate != null) {
            logging.debug('Context menu: calling onForceRetranslate');
            await onForceRetranslate();
            logging.debug('Context menu: onForceRetranslate completed');
          } else {
            logging.warning('Context menu: onForceRetranslate is null!');
          }
          break;
        case 'mark_as_translated':
          if (onMarkAsTranslated != null) {
            await onMarkAsTranslated();
          }
          break;
        case 'clear':
          await onClear();
          break;
        case 'history':
          await onViewHistory();
          break;
        case 'view_prompt':
          if (onViewPrompt != null) {
            await onViewPrompt();
          }
          break;
        case 'delete':
          await onDelete();
          break;
      }
    });
  }
}
