import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../../providers/batch/batch_operations_provider.dart';
import '../../../models/domain/translation_version.dart';
import '../../../models/domain/llm_provider_model.dart';
import '../../translation_editor/providers/editor_providers.dart';

/// Dialog for batch translating selected units
///
/// Allows user to configure translation settings:
/// - Provider selection (Anthropic, OpenAI, DeepL)
/// - Model selection
/// - Quality mode (Fast/Balanced/Quality)
/// - Glossary usage
/// - Translation memory usage
///
/// Shows progress during translation with:
/// - Progress bar
/// - Current unit being translated
/// - Success/failure counts
/// - Estimated time remaining
class BatchTranslateDialog extends ConsumerStatefulWidget {
  const BatchTranslateDialog({
    super.key,
    required this.selectedUnits,
    required this.onTranslate,
  });

  final List<TranslationVersion> selectedUnits;
  final Function({
    required String provider,
    required String model,
    required String qualityMode,
    required bool useGlossary,
    required bool useTranslationMemory,
  }) onTranslate;

  @override
  ConsumerState<BatchTranslateDialog> createState() => _BatchTranslateDialogState();
}

class _BatchTranslateDialogState extends ConsumerState<BatchTranslateDialog> {
  String _selectedProvider = AppConstants.defaultLlmProvider;
  String? _selectedModel;
  String _qualityMode = 'balanced';
  bool _useGlossary = true;
  bool _useTranslationMemory = true;

  // Models are loaded dynamically from DB via availableLlmModelsProvider
  Map<String, List<LlmProviderModel>> _modelsByProvider = {};
  bool _modelsLoaded = false;

  @override
  Widget build(BuildContext context) {
    final operationState = ref.watch(batchOperationProvider);
    final modelsAsync = ref.watch(availableLlmModelsProvider);

    // Load models from DB when available
    modelsAsync.whenData((models) {
      if (!_modelsLoaded && models.isNotEmpty) {
        _modelsByProvider = {};
        for (final model in models) {
          _modelsByProvider.putIfAbsent(model.providerCode, () => []).add(model);
        }
        
        // Set default model (global default or first available)
        final defaultModel = models.where((m) => m.isDefault).firstOrNull ?? models.first;
        _selectedProvider = defaultModel.providerCode;
        _selectedModel = defaultModel.modelId;
        _modelsLoaded = true;
      }
    });

    return Dialog(
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.translate_24_regular,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Translate ${widget.selectedUnits.length} Units',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: operationState.isInProgress
                  ? _buildProgressView(operationState)
                  : _buildConfigurationView(),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (operationState.isInProgress) ...[
                  _buildButton(
                    label: 'Pause',
                    icon: FluentIcons.pause_24_regular,
                    onPressed: () {
                      // TODO: Implement pause functionality
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildButton(
                    label: 'Cancel',
                    onPressed: () {
                      ref.read(batchOperationProvider.notifier).cancel();
                      Navigator.of(context).pop();
                    },
                  ),
                ] else ...[
                  _buildButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _buildButton(
                    label: 'Start Translation',
                    icon: FluentIcons.play_24_regular,
                    isPrimary: true,
                    onPressed: _startTranslation,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationView() {
    // Get available providers from loaded models
    final availableProviders = _modelsByProvider.keys.toList();
    if (availableProviders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Ensure selected provider is valid
    if (!availableProviders.contains(_selectedProvider)) {
      _selectedProvider = availableProviders.first;
    }

    // Get models for current provider
    final providerModels = _modelsByProvider[_selectedProvider] ?? [];
    final modelIds = providerModels.map((m) => m.modelId).toList();

    // Ensure selected model is valid
    if (_selectedModel == null || !modelIds.contains(_selectedModel)) {
      _selectedModel = modelIds.isNotEmpty ? modelIds.first : null;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider selection
          Text(
            'Translation Provider',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _buildDropdown(
            value: _selectedProvider,
            items: availableProviders,
            onChanged: (value) {
              setState(() {
                _selectedProvider = value!;
                final newModels = _modelsByProvider[_selectedProvider] ?? [];
                _selectedModel = newModels.isNotEmpty ? newModels.first.modelId : null;
              });
            },
            itemBuilder: (item) => _capitalizeFirst(item),
          ),
          const SizedBox(height: 16),

          // Model selection
          Text(
            'Model',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (modelIds.isNotEmpty && _selectedModel != null)
            _buildDropdown(
              value: _selectedModel!,
              items: modelIds,
              onChanged: (value) => setState(() => _selectedModel = value!),
              itemBuilder: (item) {
                final model = providerModels.firstWhere((m) => m.modelId == item);
                return model.displayName ?? item;
              },
            )
          else
            Text(
              'No models available for this provider',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          const SizedBox(height: 16),

          // Quality mode
          Text(
            'Quality Mode',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _buildDropdown(
            value: _qualityMode,
            items: const ['fast', 'balanced', 'quality'],
            onChanged: (value) => setState(() => _qualityMode = value!),
            itemBuilder: (item) => _capitalizeFirst(item),
          ),
          const SizedBox(height: 16),

          // Options
          _buildCheckbox(
            label: 'Use Glossary',
            value: _useGlossary,
            onChanged: (value) => setState(() => _useGlossary = value!),
          ),
          const SizedBox(height: 8),
          _buildCheckbox(
            label: 'Use Translation Memory',
            value: _useTranslationMemory,
            onChanged: (value) => setState(() => _useTranslationMemory = value!),
          ),
          const SizedBox(height: 24),

          // Preview
          Text(
            'Preview (First 3 Units)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.selectedUnits.take(3).map((unit) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Unit: ${unit.unitId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressView(BatchOperationState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Progress bar
        LinearProgressIndicator(
          value: state.progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 16),

        // Progress text
        Text(
          '${(state.progress * 100).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),

        // Current item
        if (state.currentItem != null)
          Text(
            'Translating: ${state.currentItem}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),

        // Stats
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStat(
              label: 'Completed',
              value: '${state.processedItems}/${state.totalItems}',
              icon: FluentIcons.checkmark_circle_24_regular,
              color: Colors.green[700]!,
            ),
            _buildStat(
              label: 'Success',
              value: '${state.successCount}',
              icon: FluentIcons.checkmark_24_regular,
              color: Colors.blue[700]!,
            ),
            _buildStat(
              label: 'Failed',
              value: '${state.failureCount}',
              icon: FluentIcons.error_circle_24_regular,
              color: Colors.red[700]!,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Estimated time
        if (state.estimatedTimeRemaining != null)
          Text(
            'Est. ${_formatDuration(state.estimatedTimeRemaining!)} remaining',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String Function(String) itemBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(itemBuilder(item)),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  Widget _buildButton({
    required String label,
    IconData? icon,
    bool isPrimary = false,
    required VoidCallback onPressed,
  }) {
    if (isPrimary) {
      return FluentButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    } else {
      return FluentTextButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    }
  }

  void _startTranslation() {
    if (_selectedModel == null) return;
    
    ref.read(batchOperationProvider.notifier).start(
      operation: BatchOperationType.translate,
      totalItems: widget.selectedUnits.length,
    );

    widget.onTranslate(
      provider: _selectedProvider,
      model: _selectedModel!,
      qualityMode: _qualityMode,
      useGlossary: _useGlossary,
      useTranslationMemory: _useTranslationMemory,
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}
