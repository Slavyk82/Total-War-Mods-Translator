import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/editor_providers.dart';

/// LLM model selector for the editor sidebar.
///
/// Watches the list of available models, the currently selected model and the
/// active provider from settings, then picks the best default when no model is
/// explicitly selected.
///
/// Rendered as a real inline dropdown: the trigger matches the sidebar action
/// buttons (36-px stretched pill) and the menu opens directly below it via
/// [MenuAnchor]. The previous `DropdownButton` popup floated over the anchor
/// and felt disconnected from the sidebar column.
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

  final MenuController _menuController = MenuController();

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
            ) ??
            '';

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

        final tokens = context.tokens;
        final triggerLabel = widget.compact
            ? currentModel.friendlyName
            : '${currentModel.providerCode}: ${currentModel.friendlyName}';

        return Tooltip(
          message: TooltipStrings.editorModelSelector,
          waitDuration: const Duration(milliseconds: 500),
          child: MenuAnchor(
            controller: _menuController,
            crossAxisUnconstrained: false,
            alignmentOffset: const Offset(0, 4),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(tokens.panel2),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 4),
              ),
              side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
              ),
              elevation: const WidgetStatePropertyAll(4),
            ),
            menuChildren: [
              for (final model in models)
                _ModelMenuItem(
                  model: model,
                  selected: model.id == currentModel.id,
                  tokens: tokens,
                  onTap: () {
                    ref
                        .read(selectedLlmModelProvider.notifier)
                        .setModel(model.id);
                  },
                ),
            ],
            builder: (context, controller, _) {
              return _TriggerButton(
                label: triggerLabel,
                tokens: tokens,
                compact: widget.compact,
                isOpen: controller.isOpen,
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              );
            },
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
      final activeProviderDefault = models
          .where((m) => m.providerCode == activeProvider && m.isDefault)
          .firstOrNull;
      if (activeProviderDefault != null) {
        return activeProviderDefault;
      }

      // Try any enabled model from active provider
      final activeProviderModel =
          models.where((m) => m.providerCode == activeProvider).firstOrNull;
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

/// Dropdown trigger rendered like the other sidebar buttons.
class _TriggerButton extends StatelessWidget {
  final String label;
  final TwmtThemeTokens tokens;
  final bool compact;
  final bool isOpen;
  final VoidCallback onTap;

  const _TriggerButton({
    required this.label,
    required this.tokens,
    required this.compact,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: compact ? null : 36,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 4 : 0,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(
              color: isOpen ? tokens.accent : tokens.border,
            ),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.brain_circuit_24_regular,
                size: compact ? 16 : 14,
                color: tokens.textMid,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: compact ? 13 : 12.5,
                    color: tokens.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isOpen
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 18,
                color: tokens.textMid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in the opened dropdown menu.
class _ModelMenuItem extends StatelessWidget {
  final LlmProviderModel model;
  final bool selected;
  final TwmtThemeTokens tokens;
  final VoidCallback onTap;

  const _ModelMenuItem({
    required this.model,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      onPressed: onTap,
      style: ButtonStyle(
        backgroundColor: selected
            ? WidgetStatePropertyAll(tokens.accentBg)
            : null,
        overlayColor: WidgetStatePropertyAll(
          tokens.accent.withValues(alpha: 0.12),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      ),
      leadingIcon: Icon(
        selected
            ? FluentIcons.checkmark_24_regular
            : FluentIcons.brain_circuit_24_regular,
        size: 14,
        color: selected ? tokens.accent : tokens.textMid,
      ),
      child: Text(
        '${model.providerCode}: ${model.friendlyName}',
        style: tokens.fontBody.copyWith(
          fontSize: 13,
          color: selected ? tokens.accent : tokens.text,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
