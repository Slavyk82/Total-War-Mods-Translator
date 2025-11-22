import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/llm_provider_model.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Accordion section for a single LLM provider.
///
/// Displays provider settings, API key configuration, and model management
/// with checkboxes for enabling/disabling models.
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
  bool _isExpanded = false;
  bool _isTesting = false;
  bool _isFetching = false;
  String? _processingModelId;

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);

    try {
      final notifier = ref.read(llmProviderSettingsProvider.notifier);
      final (success, errorMessage) = await notifier.testConnection(widget.providerCode);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Connection successful!');
        } else {
          FluentToast.error(
            context,
            'Connection failed: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _fetchModels() async {
    setState(() => _isFetching = true);

    try {
      final settingsAsync = ref.read(llmProviderSettingsProvider);
      if (settingsAsync.isLoading || settingsAsync.value == null) {
        if (mounted) {
          FluentToast.error(context, 'Settings are loading. Please wait.');
        }
        return;
      }

      final settings = settingsAsync.value!;
      final apiKey = settings['${widget.providerCode}_api_key'] ?? '';
      if (apiKey.isEmpty) {
        if (mounted) {
          FluentToast.error(context, 'Please configure API key first.');
        }
        return;
      }

      final modelsNotifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await modelsNotifier.fetchAndStoreModels(apiKey);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Successfully fetched models!');
        } else {
          FluentToast.error(
            context,
            'Failed: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  Future<void> _toggleModelEnabled(LlmProviderModel model) async {
    setState(() => _processingModelId = model.id);

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.toggleEnabled(model.id);

      if (mounted) {
        if (!success) {
          FluentToast.error(
            context,
            'Failed: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _processingModelId = null);
      }
    }
  }

  Future<void> _setAsDefault(LlmProviderModel model) async {
    if (model.isDefault) return;

    setState(() => _processingModelId = model.id);

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.setAsDefault(model.id);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Model set as default');
        } else {
          FluentToast.error(
            context,
            'Failed: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _processingModelId = null);
      }
    }
  }

  /// Filter models based on provider-specific rules.
  ///
  /// For OpenAI, only keeps models matching: gpt-X, gpt-X.X, or gpt-X.X-turbo
  /// where X is a number.
  List<LlmProviderModel> _filterModels(List<LlmProviderModel> models) {
    if (widget.providerCode != 'openai') {
      return models;
    }

    // Regex to match: gpt-\d+(\.\d+)?(-turbo)?
    // Examples: gpt-3, gpt-3.5, gpt-4, gpt-4.5-turbo, etc.
    final gptPattern = RegExp(r'^gpt-\d+(\.\d+)?(-turbo)?$');

    return models.where((model) {
      return gptPattern.hasMatch(model.modelId);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(llmModelsProvider(widget.providerCode));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header (always visible)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isExpanded
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : null,
                  borderRadius: _isExpanded
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        )
                      : BorderRadius.circular(8),
                ),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? FluentIcons.chevron_down_24_regular
                        : FluentIcons.chevron_right_24_regular,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.providerName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  // Quick status indicator
                  modelsAsync.when(
                    data: (models) {
                      if (models.isEmpty) return const SizedBox.shrink();
                      final enabledCount = models.where((m) => m.isEnabled && !m.isArchived).length;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: enabledCount > 0
                              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$enabledCount model${enabledCount != 1 ? 's' : ''} enabled',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: enabledCount > 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            ),
          ),

          // Expanded content
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API Key field
                  Text(
                    'API Key',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: widget.apiKeyController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Enter API key...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (_) => widget.onSaveApiKey(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildIconButton(
                        icon: FluentIcons.plug_connected_24_regular,
                        tooltip: 'Test connection',
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

                  // Models section
                  if (widget.providerCode != 'deepl') ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          'Available Models',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Spacer(),
                        _buildIconButton(
                          icon: FluentIcons.arrow_download_24_regular,
                          tooltip: 'Fetch models from API',
                          isLoading: _isFetching,
                          onTap: _fetchModels,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildModelsSection(modelsAsync),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: isLoading ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isLoading
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildModelsSection(AsyncValue<List<LlmProviderModel>> modelsAsync) {
    return modelsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Error loading models: $error',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      data: (models) {
        // Filter models based on provider
        final filteredModels = _filterModels(models);

        if (filteredModels.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Icon(
                  FluentIcons.question_circle_24_regular,
                  size: 32,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No models found',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Click the download button to fetch models',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                ),
              ],
            ),
          );
        }

        final availableModels = filteredModels.where((m) => !m.isArchived).toList();
        final archivedModels = filteredModels.where((m) => m.isArchived).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info box
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Check models to enable them for translations. Click the star to set as default.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            // Available models
            if (availableModels.isNotEmpty) ...[
              ...availableModels.map((model) => _buildModelItem(model)),
            ],

            // Archived models
            if (archivedModels.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Archived Models (${archivedModels.length})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).disabledColor,
                    ),
              ),
              const SizedBox(height: 8),
              ...archivedModels.map((model) => _buildModelItem(model)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildModelItem(LlmProviderModel model) {
    final isProcessingThis = _processingModelId == model.id;
    final canInteract = _processingModelId == null && !model.isArchived;

    return MouseRegion(
      cursor: canInteract ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: model.isEnabled && !model.isArchived
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: model.isEnabled && !model.isArchived
                ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                : Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            // Checkbox
            if (model.isArchived)
              Icon(
                FluentIcons.archive_24_regular,
                size: 20,
                color: Theme.of(context).disabledColor,
              )
            else if (isProcessingThis)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              GestureDetector(
                onTap: canInteract ? () => _toggleModelEnabled(model) : null,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: model.isEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: model.isEnabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: model.isEnabled
                      ? Icon(
                          FluentIcons.checkmark_24_regular,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : null,
                ),
              ),

            const SizedBox(width: 12),

            // Model name
            Expanded(
              child: Text(
                model.friendlyName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: model.isDefault ? FontWeight.w600 : FontWeight.normal,
                      color: model.isArchived ? Theme.of(context).disabledColor : null,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Default star
            if (!model.isArchived) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canInteract && !model.isDefault ? () => _setAsDefault(model) : null,
                child: Icon(
                  model.isDefault
                      ? FluentIcons.star_24_filled
                      : FluentIcons.star_24_regular,
                  size: 18,
                  color: model.isDefault
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],

            // Badges
            if (model.isDefault || model.isArchived) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: model.isDefault
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Theme.of(context).disabledColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  model.isDefault ? 'Default' : 'Archived',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: model.isDefault
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).disabledColor,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
