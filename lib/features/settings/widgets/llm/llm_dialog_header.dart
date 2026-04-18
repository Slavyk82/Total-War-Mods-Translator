import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Header row of the [ModelManagementDialog] with a leading icon, a bold
/// title, a muted subtitle, and a trailing dismiss button.
///
/// The [providerName] is interpolated into the "Manage {name} Models" title
/// so each provider's dialog reads naturally. [onClose] fires when the user
/// taps the X icon.
class LlmDialogHeader extends StatelessWidget {
  /// Display name of the LLM provider (e.g. "OpenAI", "Anthropic").
  final String providerName;

  /// Invoked when the dismiss button is tapped.
  final VoidCallback onClose;

  const LlmDialogHeader({
    super.key,
    required this.providerName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Icon(
          FluentIcons.apps_list_24_regular,
          size: 22,
          color: tokens.accent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage $providerName Models',
                style: tokens.fontDisplay.copyWith(
                  fontSize: 18,
                  color: tokens.text,
                  fontStyle: tokens.fontDisplayStyle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select which models are available for translations',
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            FluentIcons.dismiss_24_regular,
            color: tokens.textMid,
          ),
          onPressed: onClose,
        ),
      ],
    );
  }
}
