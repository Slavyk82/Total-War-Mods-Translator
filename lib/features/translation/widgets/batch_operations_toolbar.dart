import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../providers/batch/batch_selection_provider.dart';

/// Toolbar that appears when translation units are selected
///
/// Provides quick access to batch operations on selected units:
/// - Translate selected
/// - Mark as validated
/// - Copy to clipboard
/// - Export selected
/// - Clear translations
/// - Apply glossary
/// - Validate
/// - Delete
/// - Deselect all
class BatchOperationsToolbar extends ConsumerWidget {
  const BatchOperationsToolbar({
    super.key,
    required this.onTranslate,
    required this.onMarkValidated,
    required this.onCopyToClipboard,
    required this.onExport,
    required this.onClearTranslations,
    required this.onApplyGlossary,
    required this.onValidate,
    required this.onDelete,
  });

  final VoidCallback onTranslate;
  final VoidCallback onMarkValidated;
  final VoidCallback onCopyToClipboard;
  final VoidCallback onExport;
  final VoidCallback onClearTranslations;
  final VoidCallback onApplyGlossary;
  final VoidCallback onValidate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionState = ref.watch(batchSelectionProvider);

    if (!selectionState.hasSelection) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Selection count
            MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${selectionState.selectionCount} selected',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Action buttons
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ToolbarButton(
                      icon: FluentIcons.translate_24_regular,
                      label: 'Translate',
                      onPressed: onTranslate,
                      tooltip: 'Translate selected units (Ctrl+T)',
                    ),
                    const SizedBox(width: 8),
                    _ToolbarButton(
                      icon: FluentIcons.checkmark_circle_24_regular,
                      label: 'Mark Validated',
                      onPressed: onMarkValidated,
                      tooltip: 'Mark selected as validated',
                    ),
                    const SizedBox(width: 8),
                    _ToolbarButton(
                      icon: FluentIcons.shield_checkmark_24_regular,
                      label: 'Validate',
                      onPressed: onValidate,
                      tooltip: 'Run validation checks',
                    ),
                    const SizedBox(width: 8),
                    _ToolbarButton(
                      icon: FluentIcons.book_24_regular,
                      label: 'Apply Glossary',
                      onPressed: onApplyGlossary,
                      tooltip: 'Apply glossary terms',
                    ),
                    const SizedBox(width: 16),
                    // Divider
                    Container(
                      width: 1,
                      height: 32,
                      color: Theme.of(context).dividerColor,
                    ),
                    const SizedBox(width: 16),
                    _ToolbarButton(
                      icon: FluentIcons.copy_24_regular,
                      label: 'Copy',
                      onPressed: onCopyToClipboard,
                      tooltip: 'Copy to clipboard (Ctrl+C)',
                    ),
                    const SizedBox(width: 8),
                    _ToolbarButton(
                      icon: FluentIcons.arrow_export_24_regular,
                      label: 'Export',
                      onPressed: onExport,
                      tooltip: 'Export to file',
                    ),
                    const SizedBox(width: 16),
                    // Divider
                    Container(
                      width: 1,
                      height: 32,
                      color: Theme.of(context).dividerColor,
                    ),
                    const SizedBox(width: 16),
                    _ToolbarButton(
                      icon: FluentIcons.delete_24_regular,
                      label: 'Clear',
                      onPressed: onClearTranslations,
                      tooltip: 'Clear translations',
                      isDestructive: true,
                    ),
                    const SizedBox(width: 8),
                    _ToolbarButton(
                      icon: FluentIcons.delete_24_regular,
                      label: 'Delete',
                      onPressed: onDelete,
                      tooltip: 'Delete units (Delete)',
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Deselect all button
            _ToolbarButton(
              icon: FluentIcons.dismiss_circle_24_regular,
              label: 'Deselect',
              onPressed: () => ref.read(batchSelectionProvider.notifier).clearSelection(),
              tooltip: 'Clear selection (Esc)',
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual toolbar button with Fluent Design styling
class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.tooltip,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isDestructive;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isDestructive
        ? Colors.red[700]
        : Theme.of(context).colorScheme.primary;

    final backgroundColor = _isPressed
        ? (widget.isDestructive ? Colors.red[50] : Theme.of(context).colorScheme.primaryContainer)
        : _isHovered
            ? (widget.isDestructive
                ? Colors.red[50]?.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5))
            : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
