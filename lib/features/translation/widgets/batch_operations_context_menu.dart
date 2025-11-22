import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Context menu for batch operations (shown on right-click)
///
/// Provides the same actions as the toolbar but in a popup menu format.
/// Includes keyboard shortcut hints for better discoverability.
class BatchOperationsContextMenu extends StatelessWidget {
  const BatchOperationsContextMenu({
    super.key,
    required this.position,
    required this.onTranslate,
    required this.onMarkValidated,
    required this.onCopyToClipboard,
    required this.onExport,
    required this.onClearTranslations,
    required this.onApplyGlossary,
    required this.onValidate,
    required this.onDelete,
  });

  final Offset position;
  final VoidCallback onTranslate;
  final VoidCallback onMarkValidated;
  final VoidCallback onCopyToClipboard;
  final VoidCallback onExport;
  final VoidCallback onClearTranslations;
  final VoidCallback onApplyGlossary;
  final VoidCallback onValidate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(); // Placeholder - actual implementation below
  }

  /// Show the context menu at the specified position
  static Future<void> show({
    required BuildContext context,
    required Offset position,
    required VoidCallback onTranslate,
    required VoidCallback onMarkValidated,
    required VoidCallback onCopyToClipboard,
    required VoidCallback onExport,
    required VoidCallback onClearTranslations,
    required VoidCallback onApplyGlossary,
    required VoidCallback onValidate,
    required VoidCallback onDelete,
  }) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<void>>[
        _buildMenuItem(
          icon: FluentIcons.translate_24_regular,
          title: 'Translate Selected',
          shortcut: 'Ctrl+T',
          onTap: () {
            Navigator.of(context).pop();
            onTranslate();
          },
        ),
        _buildMenuItem(
          icon: FluentIcons.checkmark_circle_24_regular,
          title: 'Mark as Validated',
          onTap: () {
            Navigator.of(context).pop();
            onMarkValidated();
          },
        ),
        _buildMenuItem(
          icon: FluentIcons.shield_checkmark_24_regular,
          title: 'Validate',
          onTap: () {
            Navigator.of(context).pop();
            onValidate();
          },
        ),
        _buildMenuItem(
          icon: FluentIcons.book_24_regular,
          title: 'Apply Glossary',
          onTap: () {
            Navigator.of(context).pop();
            onApplyGlossary();
          },
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          icon: FluentIcons.copy_24_regular,
          title: 'Copy to Clipboard',
          shortcut: 'Ctrl+C',
          onTap: () {
            Navigator.of(context).pop();
            onCopyToClipboard();
          },
        ),
        _buildMenuItem(
          icon: FluentIcons.arrow_export_24_regular,
          title: 'Export Selected',
          onTap: () {
            Navigator.of(context).pop();
            onExport();
          },
        ),
        const PopupMenuDivider(),
        _buildMenuItem(
          icon: FluentIcons.delete_24_regular,
          title: 'Clear Translations',
          isDestructive: true,
          onTap: () {
            Navigator.of(context).pop();
            onClearTranslations();
          },
        ),
        _buildMenuItem(
          icon: FluentIcons.delete_24_regular,
          title: 'Delete Units',
          shortcut: 'Delete',
          isDestructive: true,
          onTap: () {
            Navigator.of(context).pop();
            onDelete();
          },
        ),
      ],
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  static PopupMenuItem _buildMenuItem({
    required IconData icon,
    required String title,
    String? shortcut,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    return PopupMenuItem(
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final color = isDestructive
              ? Colors.red[700]
              : Theme.of(context).colorScheme.onSurface;

          return Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ),
              if (shortcut != null) ...[
                const SizedBox(width: 16),
                Text(
                  shortcut,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Helper widget for showing context menu on right-click
class BatchOperationsContextMenuWrapper extends StatelessWidget {
  const BatchOperationsContextMenuWrapper({
    super.key,
    required this.child,
    required this.onTranslate,
    required this.onMarkValidated,
    required this.onCopyToClipboard,
    required this.onExport,
    required this.onClearTranslations,
    required this.onApplyGlossary,
    required this.onValidate,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onTranslate;
  final VoidCallback onMarkValidated;
  final VoidCallback onCopyToClipboard;
  final VoidCallback onExport;
  final VoidCallback onClearTranslations;
  final VoidCallback onApplyGlossary;
  final VoidCallback onValidate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        BatchOperationsContextMenu.show(
          context: context,
          position: details.globalPosition,
          onTranslate: onTranslate,
          onMarkValidated: onMarkValidated,
          onCopyToClipboard: onCopyToClipboard,
          onExport: onExport,
          onClearTranslations: onClearTranslations,
          onApplyGlossary: onApplyGlossary,
          onValidate: onValidate,
          onDelete: onDelete,
        );
      },
      child: child,
    );
  }
}
