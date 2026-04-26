import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';
import 'llm_models_list.dart';

/// Accordion section for a single LLM provider.
///
/// Displays provider settings and API key configuration.
class LlmProviderSection extends ConsumerStatefulWidget {
  final String providerCode;
  final String providerName;
  final TextEditingController apiKeyController;
  final VoidCallback onSaveApiKey;
  final Widget? additionalSettings;

  const LlmProviderSection({
    super.key,
    required this.providerCode,
    required this.providerName,
    required this.apiKeyController,
    required this.onSaveApiKey,
    this.additionalSettings,
  });

  @override
  ConsumerState<LlmProviderSection> createState() => _LlmProviderSectionState();
}

class _LlmProviderSectionState extends ConsumerState<LlmProviderSection> {
  bool _isTesting = false;

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      final (success, errorMessage) =
          await notifier.testConnection(widget.providerCode);

      if (mounted) {
        if (success) {
          FluentToast.success(context, t.settings.llmProviders.providerSection.toasts.connectionSuccess);
        } else {
          FluentToast.error(
            context,
            t.settings.llmProviders.providerSection.toasts.connectionFailed(error: errorMessage ?? 'Unknown error'),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SettingsAccordionSection(
        icon: FluentIcons.plug_connected_24_regular,
        title: widget.providerName,
        subtitle: t.settings.llmProviders.providerSection.subtitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Key label
            Text(
              t.settings.llmProviders.providerSection.apiKeyLabel,
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TokenTextField(
                    controller: widget.apiKeyController,
                    hint: t.settings.llmProviders.providerSection.apiKeyHint,
                    enabled: true,
                    obscureText: true,
                    onChanged: (_) => widget.onSaveApiKey(),
                  ),
                ),
                const SizedBox(width: 8),
                _TestConnectionButton(
                  isLoading: _isTesting,
                  onTap: _testConnection,
                ),
              ],
            ),

            // Additional settings (model dropdown, etc.)
            if (widget.additionalSettings != null) ...[
              const SizedBox(height: 16),
              widget.additionalSettings!,
            ],

            // Models list
            const SizedBox(height: 16),
            LlmModelsList(providerCode: widget.providerCode),
          ],
        ),
      ),
    );
  }
}

class _TestConnectionButton extends StatelessWidget {
  const _TestConnectionButton({
    required this.isLoading,
    required this.onTap,
  });

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: t.settings.llmProviders.providerSection.testConnectionTooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor:
            isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: isLoading ? null : onTap,
          child: Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(
                color: isLoading
                    ? tokens.border.withValues(alpha: 0.4)
                    : tokens.border,
              ),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            alignment: Alignment.center,
            child: isLoading
                ? const FluentSpinner(size: 16, strokeWidth: 2)
                : Icon(
                    FluentIcons.plug_connected_24_regular,
                    size: 18,
                    color: tokens.accent,
                  ),
          ),
        ),
      ),
    );
  }
}
