import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/providers/llm_custom_rules_providers.dart';
import '../providers/editor_providers.dart';
import '../providers/translation_settings_provider.dart';
import 'mod_rule_editor_dialog.dart';

/// Top toolbar for the translation editor
///
/// Contains LLM model selector, action buttons, and search
class EditorToolbar extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final VoidCallback onTranslationSettings;
  final VoidCallback onTranslateAll;
  final VoidCallback onTranslateSelected;
  final VoidCallback onValidate;
  final VoidCallback onExport;
  final VoidCallback onImportPack;

  const EditorToolbar({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onTranslationSettings,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onExport,
    required this.onImportPack,
  });

  @override
  ConsumerState<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends ConsumerState<EditorToolbar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectionState = ref.watch(editorSelectionProvider);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive breakpoints - adjusted for minimum window size of 800px
          final isCompact = constraints.maxWidth < 1200;
          final isVeryCompact = constraints.maxWidth < 1000;
          final searchMinWidth = 125.0;
          final searchMaxWidth = 172.0;

          return Row(
            children: [
              const SizedBox(width: 16),

              // LLM Model selector - hide label in very compact mode
              _buildModelSelector(compact: isVeryCompact),
              SizedBox(width: isCompact ? 8 : 16),

              // Skip TM checkbox - icon only in compact mode
              _buildSkipTmCheckbox(compact: isCompact),
              SizedBox(width: isCompact ? 8 : 16),

              // Action buttons - use Expanded to fill available space
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Translation Settings button
                      _buildActionButton(
                        icon: FluentIcons.settings_24_regular,
                        label: 'Settings',
                        tooltip: TooltipStrings.editorSettings,
                        onPressed: widget.onTranslationSettings,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),

                      // Mod Rule button
                      _buildModRuleButton(compact: isCompact),
                      SizedBox(width: isCompact ? 8 : 16),

                      // Action buttons
                      _buildActionButton(
                        icon: FluentIcons.translate_24_regular,
                        label: 'Translate All',
                        tooltip: TooltipStrings.editorTranslateAll,
                        onPressed: widget.onTranslateAll,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.translate_24_filled,
                        label: 'Translate Selected',
                        tooltip: TooltipStrings.editorTranslateSelected,
                        onPressed: selectionState.hasSelection
                          ? widget.onTranslateSelected
                          : null,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.checkmark_circle_24_regular,
                        label: 'Validate',
                        tooltip: TooltipStrings.editorValidate,
                        onPressed: widget.onValidate,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.arrow_import_24_regular,
                        label: 'Import pack',
                        tooltip: TooltipStrings.editorImportPack,
                        onPressed: widget.onImportPack,
                        color: Colors.blue.shade700,
                        compact: isCompact,
                      ),
                      SizedBox(width: isCompact ? 4 : 8),
                      _buildActionButton(
                        icon: FluentIcons.arrow_export_24_regular,
                        label: 'Generate pack',
                        tooltip: TooltipStrings.editorExport,
                        onPressed: widget.onExport,
                        color: Colors.green.shade700,
                        compact: isCompact,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 8 : 16),

              // Search field - responsive with smaller constraints
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: searchMinWidth,
                  maxWidth: searchMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: isVeryCompact ? 'Search...' : 'Search translations...',
                      prefixIcon: const Icon(
                        FluentIcons.search_24_regular,
                        size: 18,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                        ? FluentIconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(editorFilterProvider.notifier)
                                .setSearchQuery('');
                            },
                            tooltip: 'Clear search',
                            size: 28,
                            iconSize: 16,
                          )
                        : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      ref.read(editorFilterProvider.notifier)
                        .setSearchQuery(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? tooltip,
    Color? color,
    bool compact = false,
  }) {
    final isEnabled = onPressed != null;
    final buttonColor = color ?? Theme.of(context).colorScheme.primary;

    Widget button = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isEnabled
              ? buttonColor.withValues(alpha: 0.1)
              : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isEnabled
                ? buttonColor
                : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isEnabled
                  ? buttonColor
                  : Colors.grey,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                      ? buttonColor
                      : Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // In compact mode, always show tooltip since label is hidden
    final effectiveTooltip = compact ? (tooltip ?? label) : tooltip;
    if (effectiveTooltip != null) {
      return Tooltip(
        message: effectiveTooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }

  Widget _buildModelSelector({bool compact = false}) {
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

        // Initialize provider with default model if not set
        if (selectedModelId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedLlmModelProvider.notifier).setModel(currentModel.id);
          });
        }

        return Tooltip(
          message: TooltipStrings.editorModelSelector,
          waitDuration: const Duration(milliseconds: 500),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 8,
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
                    final displayText = compact
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
        width: compact ? 80 : 150,
        height: 20,
        child: const LinearProgressIndicator(),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildSkipTmCheckbox({bool compact = false}) {
    final settings = ref.watch(translationSettingsProvider);

    return Tooltip(
      message: TooltipStrings.editorSkipTm,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            ref.read(translationSettingsProvider.notifier)
                .setSkipTranslationMemory(!settings.skipTranslationMemory);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: settings.skipTranslationMemory
                  ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
              border: Border.all(
                color: settings.skipTranslationMemory
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).dividerColor,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  settings.skipTranslationMemory
                      ? FluentIcons.checkbox_checked_24_regular
                      : FluentIcons.checkbox_unchecked_24_regular,
                  size: 16,
                  color: settings.skipTranslationMemory
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Skip TM',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: settings.skipTranslationMemory
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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

  Widget _buildModRuleButton({bool compact = false}) {
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final hasRuleAsync = ref.watch(hasProjectRuleProvider(widget.projectId));

    return projectAsync.when(
      data: (project) {
        final hasRule = hasRuleAsync.whenOrNull(data: (v) => v) ?? false;

        return Tooltip(
          message: hasRule
              ? TooltipStrings.editorModRuleEdit
              : TooltipStrings.editorModRuleAdd,
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showModRuleDialog(project.name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: hasRule
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Colors.transparent,
                  border: Border.all(
                    color: hasRule
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasRule
                          ? FluentIcons.text_bullet_list_ltr_24_filled
                          : FluentIcons.text_bullet_list_ltr_24_regular,
                      size: 16,
                      color: hasRule
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Mod Rule',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: hasRule
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _showModRuleDialog(String projectName) {
    showDialog(
      context: context,
      builder: (context) => ModRuleEditorDialog(
        projectId: widget.projectId,
        projectName: projectName,
      ),
    );
  }
}
