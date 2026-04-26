import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';
import '../providers/settings_providers.dart';
import 'llm_provider_section.dart';
import 'llm_custom_rules_section.dart';

/// LLM Providers tab for configuring API keys and provider settings.
class LlmProvidersTab extends ConsumerStatefulWidget {
  const LlmProvidersTab({super.key});

  @override
  ConsumerState<LlmProvidersTab> createState() => _LlmProvidersTabState();
}

class _LlmProvidersTabState extends ConsumerState<LlmProvidersTab> {
  late final TextEditingController _anthropicKeyController;
  late final TextEditingController _openaiKeyController;
  late final TextEditingController _deeplKeyController;
  late final TextEditingController _deepseekKeyController;
  late final TextEditingController _geminiKeyController;
  bool _initialLoadDone = false;

  // Debounce bursts of Slider `onChanged` events so a single drag collapses
  // to one provider write. `_pendingRateLimit` drives the Slider's `value`
  // while the debounce is in flight so the thumb doesn't snap back.
  Timer? _rateLimitDebounce;
  int? _pendingRateLimit;

  @override
  void initState() {
    super.initState();
    _anthropicKeyController = TextEditingController();
    _openaiKeyController = TextEditingController();
    _deeplKeyController = TextEditingController();
    _deepseekKeyController = TextEditingController();
    _geminiKeyController = TextEditingController();

    // Seed controllers from loaded settings once, via listenManual (not in build).
    ref.listenManual<AsyncValue<Map<String, String>>>(
      llmProviderSettingsProvider,
      (_, next) {
        if (_initialLoadDone) return;
        final settings = next is AsyncData<Map<String, String>> ? next.value : null;
        if (settings == null) return;
        _initialLoadDone = true;
        _anthropicKeyController.text = settings[SettingsKeys.anthropicApiKey] ?? '';
        _openaiKeyController.text = settings[SettingsKeys.openaiApiKey] ?? '';
        _deeplKeyController.text = settings[SettingsKeys.deeplApiKey] ?? '';
        _deepseekKeyController.text = settings[SettingsKeys.deepseekApiKey] ?? '';
        _geminiKeyController.text = settings[SettingsKeys.geminiApiKey] ?? '';
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _rateLimitDebounce?.cancel();
    _anthropicKeyController.dispose();
    _openaiKeyController.dispose();
    _deeplKeyController.dispose();
    _deepseekKeyController.dispose();
    _geminiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey({
    required String providerLabel,
    required TextEditingController controller,
    required Future<void> Function(String) update,
  }) async {
    try {
      await update(controller.text);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, t.settings.llmProviders.providerSection.toasts.saveApiKeyError(provider: providerLabel, error: e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final settingsAsync = ref.watch(llmProviderSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: FluentSpinner()),
      error: (error, stack) => Center(
        child: Text(
          t.settings.errors.loadSettings(error: error),
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.err),
        ),
      ),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Header
            Text(
              t.settings.llmProviders.title,
              style: tokens.fontDisplay.copyWith(
                fontSize: 20,
                color: tokens.accent,
                fontWeight: FontWeight.bold,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.settings.llmProviders.subtitle,
              style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.textDim),
            ),
            const SizedBox(height: 24),

            // Anthropic Section
            LlmProviderSection(
              providerCode: 'anthropic',
              providerName: 'Anthropic (Claude)',
              apiKeyController: _anthropicKeyController,
              onSaveApiKey: () => _saveApiKey(
                providerLabel: 'Anthropic',
                controller: _anthropicKeyController,
                update: ref.read(llmProviderSettingsProvider.notifier).updateAnthropicApiKey,
              ),
            ),
            const SizedBox(height: 16),

            // OpenAI Section
            LlmProviderSection(
              providerCode: 'openai',
              providerName: 'OpenAI',
              apiKeyController: _openaiKeyController,
              onSaveApiKey: () => _saveApiKey(
                providerLabel: 'OpenAI',
                controller: _openaiKeyController,
                update: ref.read(llmProviderSettingsProvider.notifier).updateOpenaiApiKey,
              ),
            ),
            const SizedBox(height: 16),

            // DeepL Section
            LlmProviderSection(
              providerCode: 'deepl',
              providerName: 'DeepL',
              apiKeyController: _deeplKeyController,
              onSaveApiKey: () => _saveApiKey(
                providerLabel: 'DeepL',
                controller: _deeplKeyController,
                update: ref.read(llmProviderSettingsProvider.notifier).updateDeeplApiKey,
              ),
            ),
            const SizedBox(height: 16),

            // DeepSeek Section
            LlmProviderSection(
              providerCode: 'deepseek',
              providerName: 'DeepSeek',
              apiKeyController: _deepseekKeyController,
              onSaveApiKey: () => _saveApiKey(
                providerLabel: 'DeepSeek',
                controller: _deepseekKeyController,
                update: ref.read(llmProviderSettingsProvider.notifier).updateDeepseekApiKey,
              ),
            ),
            const SizedBox(height: 16),

            // Gemini Section
            LlmProviderSection(
              providerCode: 'gemini',
              providerName: 'Google Gemini',
              apiKeyController: _geminiKeyController,
              onSaveApiKey: () => _saveApiKey(
                providerLabel: 'Gemini',
                controller: _geminiKeyController,
                update: ref.read(llmProviderSettingsProvider.notifier).updateGeminiApiKey,
              ),
            ),
            const SizedBox(height: 24),

            // Custom Translation Rules Section
            // Non-const: see locale-rebuild rationale in `settings_screen.dart`.
            LlmCustomRulesSection(),
            const SizedBox(height: 32),

            // Advanced Settings
            _buildAdvancedSettings(settings),
          ],
        );
      },
    );
  }

  Widget _buildAdvancedSettings(Map<String, String> settings) {
    final tokens = context.tokens;
    final savedRateLimit =
        int.tryParse(settings[SettingsKeys.rateLimit] ?? '500') ?? 500;
    // While a debounce is in flight, follow the pending value so the thumb
    // and the numeric label track the drag without waiting for the write.
    final rateLimit = _pendingRateLimit ?? savedRateLimit;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.settings_24_regular,
                size: 20,
                color: tokens.accent,
              ),
              const SizedBox(width: 12),
              Text(
                t.settings.llmProviders.advancedSettings.title,
                style: tokens.fontBody.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(FluentIcons.timer_24_regular, size: 16, color: tokens.textMid),
              const SizedBox(width: 8),
              Text(
                t.settings.llmProviders.advancedSettings.rateLimitLabel,
                style: tokens.fontBody.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: tokens.accent,
                    inactiveTrackColor: tokens.border,
                    thumbColor: tokens.accent,
                    overlayColor: tokens.accentBg,
                    valueIndicatorColor: tokens.accent,
                    valueIndicatorTextStyle: tokens.fontMono.copyWith(
                      color: tokens.accentFg,
                      fontSize: 11,
                    ),
                  ),
                  child: Slider(
                    value: rateLimit.toDouble(),
                    min: 10,
                    max: 500,
                    divisions: 49,
                    label: rateLimit.toString(),
                    onChanged: (value) {
                      final next = value.toInt();
                      // Optimistic UI: reflect the new value immediately so
                      // the thumb doesn't snap back while the write is
                      // debounced. See `_pendingRateLimit` above.
                      setState(() => _pendingRateLimit = next);
                      _rateLimitDebounce?.cancel();
                      _rateLimitDebounce = Timer(
                        const Duration(milliseconds: 300),
                        () async {
                          try {
                            final notifier = ref
                                .read(llmProviderSettingsProvider.notifier);
                            await notifier.updateRateLimit(next);
                            if (mounted) {
                              setState(() => _pendingRateLimit = null);
                            }
                          } catch (e) {
                            if (mounted) {
                              FluentToast.error(
                                context,
                                t.settings.llmProviders.advancedSettings.saveError(error: e),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  rateLimit.toString(),
                  textAlign: TextAlign.center,
                  style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
