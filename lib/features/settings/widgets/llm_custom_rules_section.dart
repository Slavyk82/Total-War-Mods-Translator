import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/llm_custom_rules_providers.dart';
import 'llm_custom_rules_datagrid.dart';
import 'llm_custom_rule_editor_dialog.dart';

/// Expandable section for managing LLM custom translation rules
class LlmCustomRulesSection extends ConsumerStatefulWidget {
  const LlmCustomRulesSection({super.key});

  @override
  ConsumerState<LlmCustomRulesSection> createState() =>
      _LlmCustomRulesSectionState();
}

class _LlmCustomRulesSectionState extends ConsumerState<LlmCustomRulesSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final enabledCountAsync = ref.watch(enabledRulesCountProvider);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Accordion header
          _buildHeader(enabledCountAsync),
          // Expanded content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AsyncValue<int> enabledCountAsync) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isExpanded
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: _isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(7))
                : BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.text_bullet_list_ltr_24_regular,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom Translation Rules',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add custom instructions to translation prompts',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ),
              // Badge showing enabled count
              enabledCountAsync.when(
                data: (count) => count > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count active',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  FluentIcons.chevron_down_24_regular,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: 18,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Custom rules are appended to every translation prompt sent to the LLM. '
                    'Use this to define global instructions, terminology guidelines, '
                    'or translation preferences that apply to all projects.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.8),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Add rule button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: _addRule,
                icon: const Icon(FluentIcons.add_24_regular, size: 18),
                label: const Text('Add Rule'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // DataGrid
          const LlmCustomRulesDataGrid(),
        ],
      ),
    );
  }

  Future<void> _addRule() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const LlmCustomRuleEditorDialog(),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final (success, error) =
          await ref.read(llmCustomRulesProvider.notifier).addRule(result);

      if (mounted) {
        if (success) {
          FluentToast.success(context, 'Rule added successfully');
        } else {
          FluentToast.error(context, error ?? 'Failed to add rule');
        }
      }
    }
  }
}
