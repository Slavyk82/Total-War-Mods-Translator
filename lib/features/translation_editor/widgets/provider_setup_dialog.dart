import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Dialog shown when no LLM provider is configured.
///
/// Prompts the user to configure a provider before translating, themed via
/// [TokenDialog] so it matches the rest of the app's popups.
class ProviderSetupDialog extends StatelessWidget {
  const ProviderSetupDialog({
    super.key,
    required this.onGoToSettings,
  });

  final VoidCallback onGoToSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TokenDialog(
      icon: FluentIcons.warning_24_regular,
      iconColor: tokens.warn,
      title: t.translationEditor.dialogs.providerSetup.title,
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.translationEditor.dialogs.providerSetup.message,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.textDim,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.panel2,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              children: [
                _ProviderItem(
                  icon: FluentIcons.brain_circuit_24_regular,
                  name: t.translationEditor.dialogs.providerSetup.anthropic,
                  description: t.translationEditor.dialogs.providerSetup.anthropicDesc,
                ),
                const SizedBox(height: 12),
                _ProviderItem(
                  icon: FluentIcons.bot_24_regular,
                  name: t.translationEditor.dialogs.providerSetup.openai,
                  description: t.translationEditor.dialogs.providerSetup.openaiDesc,
                ),
                const SizedBox(height: 12),
                _ProviderItem(
                  icon: FluentIcons.translate_24_regular,
                  name: t.translationEditor.dialogs.providerSetup.deepl,
                  description: t.translationEditor.dialogs.providerSetup.deeplDesc,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        SmallTextButton(
          label: t.common.actions.cancel,
          onTap: () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: t.translationEditor.dialogs.providerSetup.goToSettings,
          icon: FluentIcons.settings_24_regular,
          filled: true,
          onTap: () {
            Navigator.of(context).pop();
            onGoToSettings();
          },
        ),
      ],
    );
  }
}

class _ProviderItem extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;

  const _ProviderItem({
    required this.icon,
    required this.name,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: tokens.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: tokens.fontBody.copyWith(
                  fontSize: 13,
                  color: tokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
