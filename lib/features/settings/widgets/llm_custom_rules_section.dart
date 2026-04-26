import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/llm_custom_rules_providers.dart';
import 'llm_custom_rules_datagrid.dart';
import 'llm_custom_rule_editor_dialog.dart';

/// Expandable section for managing LLM custom translation rules.
class LlmCustomRulesSection extends ConsumerWidget {
  const LlmCustomRulesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledCount = ref.watch(enabledRulesCountProvider).value ?? 0;

    return SettingsAccordionSection(
      icon: FluentIcons.text_bullet_list_ltr_24_regular,
      title: t.settings.customRules.accordionTitle,
      subtitle: t.settings.customRules.accordionSubtitle,
      activeCount: enabledCount,
      child: _LlmCustomRulesBody(onAdd: () => _addRule(context, ref)),
    );
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const LlmCustomRuleEditorDialog(),
    );

    if (result == null || result.isEmpty) return;
    if (!context.mounted) return;

    final (success, error) =
        await ref.read(llmCustomRulesProvider.notifier).addRule(result);

    if (!context.mounted) return;
    if (success) {
      FluentToast.success(context, t.settings.customRules.toasts.addSuccess);
    } else {
      FluentToast.error(context, error ?? t.settings.customRules.toasts.addFailed);
    }
  }
}

class _LlmCustomRulesBody extends StatelessWidget {
  const _LlmCustomRulesBody({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.info_24_regular,
                size: 18,
                color: tokens.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.settings.customRules.infoText,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textMid,
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
            SmallTextButton(
              label: t.settings.customRules.addRuleButton,
              icon: FluentIcons.add_24_regular,
              tooltip: t.tooltips.settings.addRule,
              onTap: onAdd,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Non-const: column headers are translated; see rationale in
        // `settings_screen.dart`.
        LlmCustomRulesDataGrid(),
      ],
    );
  }
}
