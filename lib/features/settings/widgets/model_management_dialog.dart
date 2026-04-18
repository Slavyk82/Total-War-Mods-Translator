import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../models/domain/llm_provider_model.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/common/fluent_spinner.dart';
import 'llm/llm_dialog_header.dart';
import 'llm/llm_model_card.dart';
import 'llm/llm_model_empty_state.dart';
import 'llm/llm_models_legend.dart';

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
/// Plan 5f · Task 8: header/legend/model card extracted into dedicated
/// primitives under `widgets/llm/`.
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
              LlmDialogHeader(
                providerName: widget.providerName,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 16),

              // Legend
              const LlmModelsLegend(),
              const SizedBox(height: 16),

              // Models list
              Expanded(
                child: modelsAsync.when(
                  loading: () => const Center(
                    child: FluentSpinner(),
                  ),
                  error: (error, stack) => LlmModelEmptyState(
                    icon: FluentIcons.error_circle_24_regular,
                    iconColor: tokens.err,
                    title: 'Error loading models',
                    subtitle: error.toString(),
                  ),
                  data: (models) {
                    if (models.isEmpty) {
                      return LlmModelEmptyState(
                        icon: FluentIcons.question_circle_24_regular,
                        iconColor: tokens.textFaint,
                        title: 'No models found',
                        subtitle:
                            'Click "Fetch Models" to load available models',
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
                          ...availableModels.map((model) => _modelCard(model)),
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
                          ...archivedModels.map((model) => _modelCard(model)),
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

  /// Wraps [LlmModelCard] with the dialog's mutation callbacks.
  Widget _modelCard(LlmProviderModel model) {
    final isProcessingThis = _isProcessing && _processingModelId == model.id;
    return LlmModelCard(
      model: model,
      isProcessingThis: isProcessingThis,
      isProcessing: _isProcessing,
      onToggleEnabled: () => _toggleModelEnabled(model),
      onSetAsDefault: () => _setAsDefault(model),
    );
  }
}
