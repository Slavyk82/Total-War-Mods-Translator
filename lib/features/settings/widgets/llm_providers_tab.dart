import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
    _anthropicKeyController.dispose();
    _openaiKeyController.dispose();
    _deeplKeyController.dispose();
    _deepseekKeyController.dispose();
    _geminiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveAnthropicApiKey() async {
    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      await notifier.updateAnthropicApiKey(_anthropicKeyController.text);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving Anthropic API key: $e');
      }
    }
  }

  Future<void> _saveOpenaiApiKey() async {
    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      await notifier.updateOpenaiApiKey(_openaiKeyController.text);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving OpenAI API key: $e');
      }
    }
  }

  Future<void> _saveDeeplApiKey() async {
    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      await notifier.updateDeeplApiKey(_deeplKeyController.text);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving DeepL API key: $e');
      }
    }
  }

  Future<void> _saveDeepseekApiKey() async {
    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      await notifier.updateDeepseekApiKey(_deepseekKeyController.text);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving DeepSeek API key: $e');
      }
    }
  }

  Future<void> _saveGeminiApiKey() async {
    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      await notifier.updateGeminiApiKey(_geminiKeyController.text);
    } catch (e) {
      if (mounted) {
        FluentToast.error(context, 'Error saving Gemini API key: $e');
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
          'Error loading settings: $error',
          style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.err),
        ),
      ),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Header
            Text(
              'LLM Providers',
              style: tokens.fontDisplay.copyWith(
                fontSize: 20,
                color: tokens.text,
                fontWeight: FontWeight.bold,
                fontStyle: tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure API keys and models for translation providers',
              style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.textDim),
            ),
            const SizedBox(height: 24),

            // Anthropic Section
            LlmProviderSection(
              providerCode: 'anthropic',
              providerName: 'Anthropic (Claude)',
              apiKeyController: _anthropicKeyController,
              onSaveApiKey: _saveAnthropicApiKey,
            ),
            const SizedBox(height: 16),

            // OpenAI Section
            LlmProviderSection(
              providerCode: 'openai',
              providerName: 'OpenAI',
              apiKeyController: _openaiKeyController,
              onSaveApiKey: _saveOpenaiApiKey,
            ),
            const SizedBox(height: 16),

            // DeepL Section
            LlmProviderSection(
              providerCode: 'deepl',
              providerName: 'DeepL',
              apiKeyController: _deeplKeyController,
              onSaveApiKey: _saveDeeplApiKey,
            ),
            const SizedBox(height: 16),

            // DeepSeek Section
            LlmProviderSection(
              providerCode: 'deepseek',
              providerName: 'DeepSeek',
              apiKeyController: _deepseekKeyController,
              onSaveApiKey: _saveDeepseekApiKey,
            ),
            const SizedBox(height: 16),

            // Gemini Section
            LlmProviderSection(
              providerCode: 'gemini',
              providerName: 'Google Gemini',
              apiKeyController: _geminiKeyController,
              onSaveApiKey: _saveGeminiApiKey,
            ),
            const SizedBox(height: 24),

            // Custom Translation Rules Section
            const LlmCustomRulesSection(),
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
    final rateLimit = int.tryParse(settings[SettingsKeys.rateLimit] ?? '500') ?? 500;

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
                'Advanced Settings',
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
                'Rate Limit (requests per minute)',
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
                    onChanged: (value) async {
                      try {
                        final notifier = ref.read(llmProviderSettingsProvider.notifier);
                        await notifier.updateRateLimit(value.toInt());
                      } catch (e) {
                        if (mounted) {
                          FluentToast.error(context, 'Error saving rate limit: $e');
                        }
                      }
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
