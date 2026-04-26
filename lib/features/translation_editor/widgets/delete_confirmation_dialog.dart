import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed delete-confirmation dialog.
///
/// Wraps [TokenDialog] to provide a destructive Cancel/Delete prompt with
/// the same chrome as the rest of the editor popups. Returns `true` on
/// confirm and `false`/`null` on cancel or barrier dismiss.
class DeleteConfirmationDialog extends StatelessWidget {
  final int count;

  const DeleteConfirmationDialog({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final d = t.translationEditor.dialogs.deleteConfirm;
    final message = count == 1 ? d.messageSingle : d.messageMultiple(count: count);

    return TokenDialog(
      icon: FluentIcons.warning_24_regular,
      iconColor: tokens.err,
      title: d.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 12),
          Container(
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
                    d.cannotBeUndone,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12,
                      color: tokens.warn,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.cancel,
          onTap: () => Navigator.of(context).pop(false),
        ),
        SmallTextButton(
          label: d.deleteButton,
          icon: FluentIcons.delete_24_regular,
          filled: true,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
