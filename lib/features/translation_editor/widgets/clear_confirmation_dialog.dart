import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Token-themed clear-confirmation dialog.
///
/// Mirrors [DeleteConfirmationDialog] for the "Clear Translation" action so
/// users get the same destructive prompt chrome before wiping the translated
/// text of the selected rows. Returns `true` on confirm and `false`/`null`
/// on cancel or barrier dismiss.
class ClearConfirmationDialog extends StatelessWidget {
  final int count;

  const ClearConfirmationDialog({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final message = count == 1
        ? 'Are you sure you want to clear this translation?'
        : 'Are you sure you want to clear $count translations?';

    return TokenDialog(
      icon: FluentIcons.warning_24_regular,
      iconColor: tokens.err,
      title: 'Confirm Clear',
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
                    'This action cannot be undone.',
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
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(false),
        ),
        SmallTextButton(
          label: 'Clear',
          icon: FluentIcons.eraser_24_regular,
          filled: true,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
