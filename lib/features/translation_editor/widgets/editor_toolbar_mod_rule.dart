import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import '../../settings/providers/llm_custom_rules_providers.dart';
import '../providers/editor_providers.dart';
import 'mod_rule_editor_dialog.dart';

/// Mod-specific prompt rule button for the editor toolbar.
///
/// Displays an add/edit affordance depending on whether the project already
/// has a custom rule, and opens [ModRuleEditorDialog] on tap.
class EditorToolbarModRule extends ConsumerWidget {
  final bool compact;
  final String projectId;

  const EditorToolbarModRule({
    super.key,
    this.compact = false,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(currentProjectProvider(projectId));
    final hasRuleAsync = ref.watch(hasProjectRuleProvider(projectId));

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
              onTap: () => _showModRuleDialog(context, project.name),
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

  void _showModRuleDialog(BuildContext context, String projectName) {
    showDialog(
      context: context,
      builder: (context) => ModRuleEditorDialog(
        projectId: projectId,
        projectName: projectName,
      ),
    );
  }
}
