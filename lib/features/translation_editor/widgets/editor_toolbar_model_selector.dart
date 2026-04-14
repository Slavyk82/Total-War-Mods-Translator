import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/editor_providers.dart';

/// LLM model selector dropdown for the editor toolbar.
///
/// Watches the list of available models, the currently selected model and the
/// active provider from settings, then picks the best default when no model is
/// explicitly selected.
class EditorToolbarModelSelector extends ConsumerStatefulWidget {
  final bool compact;

  const EditorToolbarModelSelector({super.key, this.compact = false});

  @override
  ConsumerState<EditorToolbarModelSelector> createState() =>
      _EditorToolbarModelSelectorState();
}

class _EditorToolbarModelSelectorState
    extends ConsumerState<EditorToolbarModelSelector> {
  // Guards against re-seeding on every rebuild while the provider hasn't yet
  // propagated the initial value. Without this flag, a stream of model-list
  // updates can enqueue multiple post-frame writes before the first one lands.
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(availableLlmModelsProvider);
    final selectedModelId = ref.watch(selectedLlmModelProvider);
    final settingsAsync = ref.watch(llmProviderSettingsProvider);

    return modelsAsync.when(
      data: (models) {
        if (models.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get the active provider from settings (e.g., 'openai', 'anthropic', 'deepl')
        final activeProvider = settingsAsync.whenOrNull(
          data: (settings) => settings[SettingsKeys.activeProvider],
        ) ?? '';

        // Find the current selection or default model
        // Priority order:
        // 1. Currently selected model (if valid)
        // 2. Default model from the active provider
        // 3. Any enabled model from the active provider
        // 4. Any default model across all providers
        // 5. First available model
        final currentModel = selectedModelId != null
          ? models.firstWhere(
              (m) => m.id == selectedModelId,
              orElse: () => _findBestDefaultModel(models, activeProvider),
            )
          : _findBestDefaultModel(models, activeProvider);

        // Seed the provider once with the best default when no model is set.
        if (selectedModelId == null && !_seeded) {
          _seeded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(selectedLlmModelProvider.notifier)
                .setModel(currentModel.id);
          });
        }

        return Tooltip(
          message: TooltipStrings.editorModelSelector,
          waitDuration: const Duration(milliseconds: 500),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 4 : 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  FluentIcons.brain_circuit_24_regular,
                  size: 16,
                ),
                const SizedBox(width: 6),
                DropdownButton<String>(
                  value: currentModel.id,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: models.map((model) {
                    // In compact mode, show only model name without provider prefix
                    final displayText = widget.compact
                      ? model.friendlyName
                      : '${model.providerCode}: ${model.friendlyName}';
                    return DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(
                        displayText,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      ref.read(selectedLlmModelProvider.notifier).setModel(newValue);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
      loading: () => SizedBox(
        width: widget.compact ? 80 : 150,
        height: 20,
        child: const LinearProgressIndicator(),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  /// Find the best default model based on active provider setting.
  ///
  /// Priority order:
  /// 1. Default model from the active provider
  /// 2. Any enabled model from the active provider
  /// 3. Any default model across all providers
  /// 4. First available model
  LlmProviderModel _findBestDefaultModel(
    List<LlmProviderModel> models,
    String activeProvider,
  ) {
    if (activeProvider.isNotEmpty) {
      // Try to find default model from active provider
      final activeProviderDefault = models.where(
        (m) => m.providerCode == activeProvider && m.isDefault,
      ).firstOrNull;
      if (activeProviderDefault != null) {
        return activeProviderDefault;
      }

      // Try any enabled model from active provider
      final activeProviderModel = models.where(
        (m) => m.providerCode == activeProvider,
      ).firstOrNull;
      if (activeProviderModel != null) {
        return activeProviderModel;
      }
    }

    // Fallback: any default model across all providers
    final anyDefault = models.where((m) => m.isDefault).firstOrNull;
    if (anyDefault != null) {
      return anyDefault;
    }

    // Final fallback: first model
    return models.first;
  }
}
