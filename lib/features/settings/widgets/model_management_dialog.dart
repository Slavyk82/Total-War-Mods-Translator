import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
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
///
/// Retokenised (Plan 5e · Task 7): structure preserved; all `Theme.of(context)`
/// calls replaced by tokens; raw `Colors.*` removed in favour of tokens.
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
    final tokens = context.tokens;
    final modelsAsync = ref.watch(llmModelsProvider(widget.providerCode));

    return Dialog(
      backgroundColor: tokens.panel,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      child: SizedBox(
        width: 700,
        height: 600,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    FluentIcons.apps_list_24_regular,
                    size: 22,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage ${widget.providerName} Models',
                          style: tokens.fontDisplay.copyWith(
                            fontSize: 18,
                            color: tokens.text,
                            fontStyle: tokens.fontDisplayStyle,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select which models are available for translations',
                          style: tokens.fontBody.copyWith(
                            fontSize: 13,
                            color: tokens.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      FluentIcons.dismiss_24_regular,
                      color: tokens.textMid,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 16),

              // Legend
              _buildLegend(tokens),
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
                          color: tokens.err,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading models',
                          style: tokens.fontBody.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: tokens.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          style: tokens.fontBody.copyWith(
                            fontSize: 12,
                            color: tokens.textDim,
                          ),
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
                              color: tokens.textFaint,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No models found',
                              style: tokens.fontBody.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: tokens.text,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Click "Fetch Models" to load available models',
                              style: tokens.fontBody.copyWith(
                                fontSize: 12,
                                color: tokens.textDim,
                              ),
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
                            style: tokens.fontBody.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: tokens.accent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...availableModels
                              .map((model) => _buildModelItem(tokens, model)),
                        ],

                        // Archived models (if any)
                        if (archivedModels.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            'Archived Models (${archivedModels.length})',
                            style: tokens.fontBody.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: tokens.textFaint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...archivedModels
                              .map((model) => _buildModelItem(tokens, model)),
                        ],
                      ],
                    );
                  },
                ),
              ),

              // Footer
              const SizedBox(height: 16),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallTextButton(
                    label: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.info_24_regular,
            size: 16,
            color: tokens.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Check models to make them available for translations. Click the star to set a model as global default (only one default across all providers).',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelItem(TwmtThemeTokens tokens, LlmProviderModel model) {
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
              ? tokens.accentBg
              : tokens.panel2,
          border: Border.all(
            color: model.isEnabled && !model.isArchived
                ? tokens.accent.withValues(alpha: 0.5)
                : tokens.border,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Row(
          children: [
            // Checkbox
            if (model.isArchived)
              Icon(
                FluentIcons.archive_24_regular,
                size: 20,
                color: tokens.textFaint,
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
                    color: model.isEnabled ? tokens.accent : Colors.transparent,
                    border: Border.all(
                      color:
                          model.isEnabled ? tokens.accent : tokens.border,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: model.isEnabled
                      ? Icon(
                          FluentIcons.checkmark_24_regular,
                          size: 14,
                          color: tokens.accentFg,
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
                    style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      fontWeight: model.isDefault
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: model.isArchived
                          ? tokens.textFaint
                          : tokens.text,
                    ),
                  ),
                  if (model.modelId != model.friendlyName) ...[
                    const SizedBox(height: 2),
                    Text(
                      model.modelId,
                      style: tokens.fontMono.copyWith(
                        fontSize: 11.5,
                        color: tokens.textDim,
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
                          ? tokens.accent.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      model.isDefault
                          ? FluentIcons.star_24_filled
                          : FluentIcons.star_24_regular,
                      size: 20,
                      color:
                          model.isDefault ? tokens.accent : tokens.textFaint,
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
                      ? tokens.accent.withValues(alpha: 0.1)
                      : tokens.textFaint.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  model.isDefault ? 'Default' : 'Archived',
                  style: tokens.fontMono.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: model.isDefault ? tokens.accent : tokens.textFaint,
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
