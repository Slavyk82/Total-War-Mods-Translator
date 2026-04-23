import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed Cancel/Confirm dialog shared across the app.
///
/// Wraps [TokenDialog] with the canonical confirmation shape so every yes/no
/// prompt inherits the same chrome instead of falling back to Material
/// `AlertDialog`. Pops `true` on confirm, `false`/`null` on cancel or
/// barrier dismiss.
///
/// Provide either [message] (plain text) or [body] (custom widget) — not
/// both. Set [destructive] to `true` for delete-style prompts: the header
/// icon becomes `tokens.err` and the confirm button renders in the filled
/// accent variant.
///
/// Pass [warningMessage] to append the standard "cannot be undone" banner
/// below the main content.
class TokenConfirmDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? body;
  final String confirmLabel;
  final IconData? confirmIcon;
  final String cancelLabel;
  final bool destructive;
  final String? warningMessage;
  final double width;

  const TokenConfirmDialog({
    super.key,
    this.icon = FluentIcons.warning_24_regular,
    required this.title,
    this.message,
    this.body,
    this.confirmLabel = 'Confirm',
    this.confirmIcon,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.warningMessage,
    this.width = 480,
  }) : assert(
          message != null || body != null,
          'TokenConfirmDialog requires either message or body',
        );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TokenDialog(
      icon: icon,
      iconColor: destructive ? tokens.err : null,
      title: title,
      width: width,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (body != null)
            body!
          else
            Text(
              message!,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
            ),
          if (warningMessage != null) ...[
            const SizedBox(height: 12),
            _WarningBanner(message: warningMessage!),
          ],
        ],
      ),
      actions: [
        SmallTextButton(
          label: cancelLabel,
          onTap: () => Navigator.of(context).pop(false),
        ),
        SmallTextButton(
          label: confirmLabel,
          icon: confirmIcon,
          filled: destructive,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warnBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.warn.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.info_24_regular,
            size: 16,
            color: tokens.warn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.warn,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
