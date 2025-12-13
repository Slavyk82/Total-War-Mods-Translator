import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/llm_provider_model.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';

/// Widget displaying a list of LLM models for a provider.
///
/// Allows users to:
/// - View all available models (non-archived)
/// - Enable/disable models with checkboxes
/// - Set a model as global default (only one default across all providers)
class LlmModelsList extends ConsumerWidget {
  final String providerCode;

  const LlmModelsList({
    super.key,
    required this.providerCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(llmModelsProvider(providerCode));

    return modelsAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: FluentSpinner(size: 16, strokeWidth: 2),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withOpacity(0.5),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
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
        // Filter to only show non-archived models
        final availableModels = models.where((m) => !m.isArchived).toList();

        if (availableModels.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No models available for this provider',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Models',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...availableModels.asMap().entries.map((entry) {
                    final index = entry.key;
                    final model = entry.value;
                    final isLast = index == availableModels.length - 1;

                    return RepaintBoundary(
                      key: ValueKey(model.id),
                      child: _ModelItem(
                        model: model,
                        providerCode: providerCode,
                        showDivider: !isLast,
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check models to enable them. Click the star to set as global default.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _ModelItem extends ConsumerStatefulWidget {
  final LlmProviderModel model;
  final String providerCode;
  final bool showDivider;

  const _ModelItem({
    required this.model,
    required this.providerCode,
    required this.showDivider,
  });

  @override
  ConsumerState<_ModelItem> createState() => _ModelItemState();
}

class _ModelItemState extends ConsumerState<_ModelItem> {
  bool _isProcessing = false;

  Future<void> _toggleEnabled() async {
    if (_isProcessing) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.toggleEnabled(widget.model.id);

      if (!mounted) return;
      
      if (success) {
        FluentToast.success(
          context,
          widget.model.isEnabled ? 'Model disabled' : 'Model enabled',
        );
      } else {
        FluentToast.error(
          context,
          'Failed to toggle model: ${errorMessage ?? "Unknown error"}',
        );
      }
    } finally {
      if (mounted) {
        // Use post-frame callback to avoid MouseRegion issues during rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isProcessing = false);
          }
        });
      }
    }
  }

  Future<void> _setAsDefault() async {
    if (_isProcessing || widget.model.isDefault) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final notifier = ref.read(llmModelsProvider(widget.providerCode).notifier);
      final (success, errorMessage) = await notifier.setAsDefault(widget.model.id);

      if (!mounted) return;
      
      if (success) {
        FluentToast.success(context, 'Model set as default');
      } else {
        FluentToast.error(
          context,
          'Failed to set default: ${errorMessage ?? "Unknown error"}',
        );
      }
    } finally {
      if (mounted) {
        // Use post-frame callback to avoid MouseRegion issues during rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isProcessing = false);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: _isProcessing ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _isProcessing ? null : _toggleEnabled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.model.isEnabled
                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  // Checkbox
                  if (_isProcessing)
                    const FluentSpinner(size: 20, strokeWidth: 2)
                  else
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: widget.model.isEnabled
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: widget.model.isEnabled
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: widget.model.isEnabled
                          ? Icon(
                              FluentIcons.checkmark_24_regular,
                              size: 14,
                              color: Theme.of(context).colorScheme.onPrimary,
                            )
                          : null,
                    ),

                  const SizedBox(width: 12),

                  // Model name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.model.friendlyName,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: widget.model.isDefault
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                              ),
                            ),
                            if (widget.model.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Default',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.model.modelId != widget.model.friendlyName) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.model.modelId,
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
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isProcessing || widget.model.isDefault
                        ? null
                        : _setAsDefault,
                    child: MouseRegion(
                      cursor: _isProcessing || widget.model.isDefault
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.model.isDefault
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          widget.model.isDefault
                              ? FluentIcons.star_24_filled
                              : FluentIcons.star_24_regular,
                          size: 20,
                          color: widget.model.isDefault
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
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
      ],
    );
  }
}

