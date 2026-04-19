import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed dialog scaffold shared across the app.
///
/// Renders the canonical popup shape: panel background, bordered rounded
/// container, header row (icon + title), optional body widget, and actions
/// row of [SmallTextButton]. Mirrors `ModRuleEditorDialog`'s archetype so
/// every popup inherits the same chrome without hand-rolling Material
/// `AlertDialog` with hardcoded colours.
class TokenDialog extends StatelessWidget {
  /// Leading icon in the header row.
  final IconData icon;

  /// Override for the icon colour. Defaults to `tokens.accent`.
  final Color? iconColor;

  /// Title text rendered with `tokens.fontDisplay`.
  final String title;

  /// Optional subtitle under the title (e.g. mod name) in `tokens.textDim`.
  final String? subtitle;

  /// Optional body widget between header and actions row.
  final Widget? body;

  /// Action buttons (typically [SmallTextButton]) pinned to the bottom-right.
  final List<Widget> actions;

  /// Optional leading actions (pinned to the bottom-left, e.g. Delete).
  final List<Widget> leadingActions;

  /// Fixed width in px. Defaults to 480.
  final double width;

  const TokenDialog({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.body,
    this.actions = const [],
    this.leadingActions = const [],
    this.width = 480,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Dialog(
      backgroundColor: tokens.panel,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 22, color: iconColor ?? tokens.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: tokens.fontDisplay.copyWith(
                            fontSize: 18,
                            color: tokens.text,
                            fontStyle: tokens.fontDisplayStyle,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: tokens.fontBody.copyWith(
                              fontSize: 12,
                              color: tokens.textDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (body != null) ...[
                const SizedBox(height: 16),
                body!,
              ],
              if (actions.isNotEmpty || leadingActions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    ...leadingActions,
                    const Spacer(),
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Static helpers for common message popups ----------

  /// Shows a simple info popup with an OK button. Uses `tokens.info` tint.
  static Future<void> showInfo(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = FluentIcons.info_24_regular,
    String okLabel = 'OK',
  }) {
    return _showMessage(
      context,
      title: title,
      message: message,
      icon: icon,
      iconColorSelector: (t) => t.info,
      okLabel: okLabel,
    );
  }

  /// Shows a warning popup with an OK button. Uses `tokens.warn` tint.
  static Future<void> showWarning(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = FluentIcons.warning_24_regular,
    String okLabel = 'OK',
  }) {
    return _showMessage(
      context,
      title: title,
      message: message,
      icon: icon,
      iconColorSelector: (t) => t.warn,
      okLabel: okLabel,
    );
  }

  /// Shows an error popup with an OK button. Uses `tokens.err` tint.
  static Future<void> showError(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = FluentIcons.error_circle_24_regular,
    String okLabel = 'OK',
  }) {
    return _showMessage(
      context,
      title: title,
      message: message,
      icon: icon,
      iconColorSelector: (t) => t.err,
      okLabel: okLabel,
    );
  }

  /// Shows a confirmation popup. Resolves to `true` when the filled primary
  /// action is tapped, `false` on cancel or barrier dismiss.
  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = FluentIcons.question_circle_24_regular,
    IconData? confirmIcon,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return TokenDialog(
          icon: icon,
          iconColor: destructive ? tokens.err : tokens.accent,
          title: title,
          body: Text(
            message,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          actions: [
            SmallTextButton(
              label: cancelLabel,
              onTap: () => Navigator.pop(ctx, false),
            ),
            SmallTextButton(
              label: confirmLabel,
              icon: confirmIcon,
              filled: true,
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  static Future<void> _showMessage(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color Function(TwmtThemeTokens) iconColorSelector,
    required String okLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.tokens;
        return TokenDialog(
          icon: icon,
          iconColor: iconColorSelector(tokens),
          title: title,
          body: Text(
            message,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          actions: [
            SmallTextButton(
              label: okLabel,
              filled: true,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }
}
