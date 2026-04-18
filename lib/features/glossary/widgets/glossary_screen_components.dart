import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Empty state when no glossaries exist.
class GlossaryEmptyState extends StatelessWidget {
  const GlossaryEmptyState({super.key, required this.onNewGlossary});
  final VoidCallback onNewGlossary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.book_24_regular,
              size: 56,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'No glossaries yet',
              style: tokens.fontDisplay.copyWith(
                fontSize: 18,
                color: tokens.text,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a glossary to manage your translation terminology',
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GlossaryActionButton(
              icon: FluentIcons.add_24_regular,
              label: 'Create New Glossary',
              onPressed: onNewGlossary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Action button used by [GlossaryEmptyState]. Kept after §7.2 migration
/// because the empty-state CTA still references it; the editor-view
/// callers (`GlossaryEditorHeader`/`Footer`/`Toolbar`) were removed.
class GlossaryActionButton extends StatelessWidget {
  const GlossaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final bgColor = isDestructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    final fgColor = isDestructive
        ? Theme.of(context).colorScheme.onError
        : Theme.of(context).colorScheme.onPrimary;

    Widget button = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedOpacity(
        opacity: isEnabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fgColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: fgColor,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }
}
