import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
      title: 'No Translation Provider Configured',
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'To use automatic translation, you need to configure at least '
            'one LLM provider. Please go to Settings and set up one of the '
            'following providers:',
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
              children: const [
                _ProviderItem(
                  icon: FluentIcons.brain_circuit_24_regular,
                  name: 'Anthropic Claude',
                  description:
                      'High-quality translations with context awareness',
                ),
                SizedBox(height: 12),
                _ProviderItem(
                  icon: FluentIcons.bot_24_regular,
                  name: 'OpenAI GPT',
                  description:
                      'Versatile language model with good translations',
                ),
                SizedBox(height: 12),
                _ProviderItem(
                  icon: FluentIcons.translate_24_regular,
                  name: 'DeepL',
                  description: 'Specialized translation service',
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        SmallTextButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: 'Go to Settings',
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
