import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../settings/providers/llm_custom_rules_providers.dart';
import '../providers/editor_providers.dart';
import 'mod_rule_editor_dialog.dart';

/// Mod-specific prompt rule button for the editor sidebar.
///
/// Opens the [ModRuleEditorDialog] on tap. In non-compact mode the widget
/// renders at the same 36-px stretched-pill footprint as the other sidebar
/// buttons so §AI Context reads as a uniform column. When the project
/// already has a custom rule the button adopts the accent palette as a
/// passive "has content" indicator.
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

    final tokens = context.tokens;

    return projectAsync.when(
      data: (project) {
        final hasRule = hasRuleAsync.whenOrNull(data: (v) => v) ?? false;
        final fg = hasRule ? tokens.accent : tokens.text;
        final borderColor = hasRule ? tokens.accent : tokens.border;
        final bg = hasRule ? tokens.accentBg : tokens.panel2;
        final icon = Icon(
          hasRule
              ? FluentIcons.text_bullet_list_ltr_24_filled
              : FluentIcons.text_bullet_list_ltr_24_regular,
          size: compact ? 16 : 14,
          color: fg,
        );

        return Tooltip(
          message: hasRule
              ? TooltipStrings.editorModRuleEdit
              : TooltipStrings.editorModRuleAdd,
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showModRuleDialog(context, project.name),
              child: compact
                  ? _buildCompact(tokens, bg, borderColor, icon)
                  : _buildFull(tokens, bg, borderColor, icon, fg),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildFull(
    TwmtThemeTokens tokens,
    Color bg,
    Color borderColor,
    Widget icon,
    Color fg,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Mod-specific rule',
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(
    TwmtThemeTokens tokens,
    Color bg,
    Color borderColor,
    Widget icon,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: icon,
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
