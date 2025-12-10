import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
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
  late TextEditingController _anthropicKeyController;
  late TextEditingController _openaiKeyController;
  late TextEditingController _deeplKeyController;

  @override
  void initState() {
    super.initState();
    _anthropicKeyController = TextEditingController();
    _openaiKeyController = TextEditingController();
    _deeplKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _anthropicKeyController.dispose();
    _openaiKeyController.dispose();
    _deeplKeyController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(llmProviderSettingsProvider);

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('Error loading settings: $error'),
      ),
      data: (settings) {
        // Initialize controllers with loaded data
        if (_anthropicKeyController.text.isEmpty) {
          _anthropicKeyController.text = settings[SettingsKeys.anthropicApiKey] ?? '';
        }
        if (_openaiKeyController.text.isEmpty) {
          _openaiKeyController.text = settings[SettingsKeys.openaiApiKey] ?? '';
        }
        if (_deeplKeyController.text.isEmpty) {
          _deeplKeyController.text = settings[SettingsKeys.deeplApiKey] ?? '';
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Header
            Text(
              'LLM Providers',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure API keys and models for translation providers',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
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
    final rateLimit = int.tryParse(settings[SettingsKeys.rateLimit] ?? '500') ?? 500;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.settings_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Advanced Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(FluentIcons.timer_24_regular, size: 16),
              const SizedBox(width: 8),
              Text(
                'Rate Limit (requests per minute)',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
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
              const SizedBox(width: 12),
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rateLimit.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
