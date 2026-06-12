import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';
import 'package:twmt/providers/settings_providers.dart';
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

  /// Persists the current API-key field text. Returns a future so callers
  /// (e.g. the Test-connection flow) can await the secure-storage write
  /// before reading the key back.
  final Future<void> Function() onSaveApiKey;
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

  // Debounce the API-key field. Each keystroke would otherwise call
  // [onSaveApiKey], which writes to flutter_secure_storage and invalidates the
  // provider settings (forcing several secure-storage reads + DB reads on every
  // character). flutter_secure_storage is comparatively slow on Windows, so we
  // coalesce rapid typing/pasting into a single save after a short idle delay.
  static const Duration _apiKeyDebounce = Duration(milliseconds: 600);
  Timer? _apiKeyDebounceTimer;

  void _onApiKeyChanged() {
    _apiKeyDebounceTimer?.cancel();
    _apiKeyDebounceTimer = Timer(_apiKeyDebounce, () {
      if (mounted) widget.onSaveApiKey();
    });
  }

  @override
  void dispose() {
    // Flush any pending save so a value typed right before disposal is not lost.
    if (_apiKeyDebounceTimer?.isActive ?? false) {
      _apiKeyDebounceTimer!.cancel();
      unawaited(widget.onSaveApiKey());
    }
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      // Flush the debounced API-key save before testing. testConnection
      // reads the key from secure storage, so without this a click that
      // follows typing (within the 600 ms debounce or while the async
      // storage write is in flight) would validate the stale stored key —
      // or report 'No API key configured' on first-time setup. Awaiting an
      // unconditional save guarantees the field's current text is persisted
      // before the test reads it back.
      _apiKeyDebounceTimer?.cancel();
      await widget.onSaveApiKey();
      if (!mounted) return;

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
                    onChanged: (_) => _onApiKeyChanged(),
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
