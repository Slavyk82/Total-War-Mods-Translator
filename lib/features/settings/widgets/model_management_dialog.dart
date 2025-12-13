import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/llm_provider_model.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';

/// Dialog for managing LLM models for a specific provider.
///
/// Allows users to:
/// - View all available models
/// - Enable/disable models with checkboxes
/// - Set a model as default
/// - See archived models (read-only)
class ModelManagementDialog extends ConsumerStatefulWidget {
  final String providerCode;
  final String providerName;

  const ModelManagementDialog({
    super.key,
    required this.providerCode,
    required this.providerName,
  });

  @override
  ConsumerState<ModelManagementDialog> createState() =>
      _ModelManagementDialogState();
}

class _ModelManagementDialogState extends ConsumerState<ModelManagementDialog> {
  bool _isProcessing = false;
  String? _processingModelId;

  Future<void> _toggleModelEnabled(LlmProviderModel model) async {
    setState(() {
      _isProcessing = true;
      _processingModelId = model.id;
    });

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.toggleEnabled(model.id);

      if (mounted) {
        if (success) {
          FluentToast.success(
            context,
            model.isEnabled ? 'Model disabled' : 'Model enabled',
          );
        } else {
          FluentToast.error(
            context,
            'Failed to toggle model: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingModelId = null;
        });
      }
    }
  }

  Future<void> _setAsDefault(LlmProviderModel model) async {
    if (model.isDefault) return;

    setState(() {
      _isProcessing = true;
      _processingModelId = model.id;
    });

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.setAsDefault(model.id);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Model set as default');
        } else {
          FluentToast.error(
            context,
            'Failed to set default: ${errorMessage ?? "Unknown error"}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingModelId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(llmModelsProvider(widget.providerCode));

    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.apps_list_24_regular,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage ${widget.providerName} Models',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select which models are available for translations',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Legend
            _buildLegend(context),
            const SizedBox(height: 16),

            // Models list
            Expanded(
              child: modelsAsync.when(
                loading: () => const Center(
                  child: FluentSpinner(),
                ),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        FluentIcons.error_circle_24_regular,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading models',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                data: (models) {
                  if (models.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.question_circle_24_regular,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No models found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Click "Fetch Models" to load available models',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  // Separate available and archived models
                  final availableModels =
                      models.where((m) => !m.isArchived).toList();
                  final archivedModels =
                      models.where((m) => m.isArchived).toList();

                  return ListView(
                    children: [
                      // Available models
                      if (availableModels.isNotEmpty) ...[
                        Text(
                          'Available Models (${availableModels.length})',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...availableModels
                            .map((model) => _buildModelItem(context, model)),
                      ],

                      // Archived models (if any)
                      if (archivedModels.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Archived Models (${archivedModels.length})',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).disabledColor,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...archivedModels
                            .map((model) => _buildModelItem(context, model)),
                      ],
                    ],
                  );
                },
              ),
            ),

            // Footer
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FluentTextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
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
              'Check models to make them available for translations. Click the star to set a model as global default (only one default across all providers).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelItem(BuildContext context, LlmProviderModel model) {
    final isProcessingThis = _isProcessing && _processingModelId == model.id;
    final canInteract = !_isProcessing && !model.isArchived;

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
          borderRadius: BorderRadius.circular(8),
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
              const FluentSpinner(size: 20, strokeWidth: 2)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.friendlyName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              model.isDefault ? FontWeight.w600 : FontWeight.normal,
                          color: model.isArchived
                              ? Theme.of(context).disabledColor
                              : null,
                        ),
                  ),
                  if (model.modelId != model.friendlyName) ...[
                    const SizedBox(height: 2),
                    Text(
                      model.modelId,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                    ),
                  ],
                ],
              ),
            ),

            // Default star button
            if (!model.isArchived) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canInteract && !model.isDefault
                    ? () => _setAsDefault(model)
                    : null,
                child: MouseRegion(
                  cursor: canInteract && !model.isDefault
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: model.isDefault
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      model.isDefault
                          ? FluentIcons.star_24_filled
                          : FluentIcons.star_24_regular,
                      size: 20,
                      color: model.isDefault
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ],

            // Status badges
            if (model.isDefault || model.isArchived) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: model.isDefault
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Theme.of(context).disabledColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  model.isDefault ? 'Default' : 'Archived',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
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
