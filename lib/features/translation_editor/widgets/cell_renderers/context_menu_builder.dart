import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../providers/editor_providers.dart';
import '../../../../services/shared/logging_service.dart';
import '../../../../services/service_locator.dart';

/// Context menu builder for DataGrid rows
///
/// Provides context menu items for translation editor operations
class ContextMenuBuilder {
  /// Show context menu for selected rows
  static void showContextMenu({
    required BuildContext context,
    required Offset position,
    required TranslationRow row,
    required int selectionCount,
    required VoidCallback onEdit,
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

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: <PopupMenuEntry<String>>[
        if (isSingleSelection)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(FluentIcons.edit_24_regular, size: 16),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
        if (isSingleSelection) const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'select_all',
          child: Row(
            children: [
              Icon(FluentIcons.select_all_on_24_regular, size: 16),
              SizedBox(width: 8),
              Text('Select All'),
            ],
          ),
        ),
        if (onForceRetranslate != null)
          PopupMenuItem(
            value: 'force_retranslate',
            enabled: hasSelection,
            child: Row(
              children: [
                Icon(
                  FluentIcons.arrow_sync_24_regular,
                  size: 16,
                  color: hasSelection ? null : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  selectionCount > 1
                      ? 'Force Retranslate ($selectionCount)'
                      : 'Force Retranslate',
                  style: TextStyle(color: hasSelection ? null : Colors.grey),
                ),
              ],
            ),
          ),
        if (onMarkAsTranslated != null)
          PopupMenuItem(
            value: 'mark_as_translated',
            enabled: hasSelection,
            child: Row(
              children: [
                Icon(
                  FluentIcons.checkmark_circle_24_regular,
                  size: 16,
                  color: hasSelection ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  selectionCount > 1
                      ? 'Mark as Translated ($selectionCount)'
                      : 'Mark as Translated',
                  style: TextStyle(color: hasSelection ? Colors.green : Colors.grey),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'clear',
          enabled: hasSelection,
          child: Row(
            children: [
              Icon(
                FluentIcons.delete_24_regular,
                size: 16,
                color: hasSelection ? null : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                selectionCount > 1
                    ? 'Clear Translation ($selectionCount)'
                    : 'Clear Translation',
                style: TextStyle(color: hasSelection ? null : Colors.grey),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (isSingleSelection)
          const PopupMenuItem(
            value: 'history',
            child: Row(
              children: [
                Icon(FluentIcons.history_24_regular, size: 16),
                SizedBox(width: 8),
                Text('View History'),
              ],
            ),
          ),
        if (isSingleSelection && onViewPrompt != null)
          const PopupMenuItem(
            value: 'view_prompt',
            child: Row(
              children: [
                Icon(FluentIcons.code_24_regular, size: 16),
                SizedBox(width: 8),
                Text('View Prompt'),
              ],
            ),
          ),
        if (isSingleSelection) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          enabled: hasSelection,
          child: Row(
            children: [
              Icon(
                FluentIcons.delete_24_regular,
                size: 16,
                color: hasSelection ? Colors.red : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                selectionCount > 1 ? 'Delete ($selectionCount)' : 'Delete',
                style: TextStyle(color: hasSelection ? Colors.red : Colors.grey),
              ),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == null) return;

      final logging = ServiceLocator.get<LoggingService>();

      switch (value) {
        case 'edit':
          onEdit();
          break;
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
