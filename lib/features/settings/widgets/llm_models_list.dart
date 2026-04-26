import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/settings_providers.dart';
import '../../../widgets/common/fluent_spinner.dart';
import 'llm/llm_model_row.dart';
import 'llm/llm_provider_header.dart';

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
    final tokens = context.tokens;
    final modelsAsync = ref.watch(llmModelsProvider(providerCode));

    return modelsAsync.when(
      loading: () => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: const Center(
          child: FluentSpinner(size: 16, strokeWidth: 2),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.errBg,
          border: Border.all(color: tokens.err),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 16,
              color: tokens.err,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.settings.llmProviders.models.errorLoading(error: error),
                style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
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
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 16,
                  color: tokens.textDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.settings.llmProviders.models.noModels,
                    style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LlmProviderHeader(),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusMd),
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
                      child: LlmModelRow(
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
              t.settings.llmProviders.models.footer,
              style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
            ),
          ],
        );
      },
    );
  }
}
