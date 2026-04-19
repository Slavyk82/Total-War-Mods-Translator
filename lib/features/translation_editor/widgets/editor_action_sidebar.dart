import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import 'editor_toolbar_batch_settings.dart';
import 'editor_toolbar_mod_rule.dart';
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';

/// Left sidebar of the translation editor (240 px).
///
/// Hosts the controls previously in `EditorActionBar`, organised into 4
/// labelled sections by intent: §AI CONTEXT (model + prompt configuration) ·
/// §TRANSLATE · §REVIEW · §PACK. The search field lives in the top
/// `FilterToolbar`; filters are the STATUS pill group.
///
/// §Translate exposes a single smart button: when the grid has rows selected
/// it reads "Translate selection" and routes to [onTranslateSelected];
/// otherwise it reads "Translate all" and routes to [onTranslateAll]. The
/// `Ctrl+T` screen-scope shortcut mirrors this routing — selection-aware by
/// design — so the displayed hint is constant.
class EditorActionSidebar extends ConsumerWidget {
  final String projectId;
  final String languageId;
  final VoidCallback onTranslateAll;
  final VoidCallback onTranslateSelected;
  final VoidCallback onValidate;
  final VoidCallback onRescanValidation;
  final VoidCallback onExport;
  final VoidCallback onImportPack;

  const EditorActionSidebar({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onRescanValidation,
    required this.onExport,
    required this.onImportPack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(label: 'AI Context', tokens: tokens),
            const SizedBox(height: 10),
            const EditorToolbarModelSelector(),
            const SizedBox(height: 8),
            const EditorToolbarSkipTm(),
            const SizedBox(height: 8),
            EditorToolbarModRule(projectId: projectId),
            const SizedBox(height: 10),
            const EditorToolbarBatchSettings(),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Translate', tokens: tokens),
            const SizedBox(height: 10),
            Consumer(
              builder: (context, ref, _) {
                final selection = ref.watch(editorSelectionProvider);
                final hasSelection = selection.hasSelection;
                final label =
                    hasSelection ? 'Translate selection' : 'Translate all';
                // Ctrl+T is selection-aware at the screen scope, so the hint
                // stays constant regardless of the current grid state.
                return _SidebarActionButton(
                  icon: FluentIcons.translate_24_regular,
                  label: label,
                  primary: true,
                  shortcutHint: 'Ctrl+T',
                  onTap: hasSelection ? onTranslateSelected : onTranslateAll,
                );
              },
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Review', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.checkmark_circle_24_regular,
              label: 'Validate selected',
              onTap: onValidate,
            ),
            const SizedBox(height: 6),
            Center(
              child: SmallTextButton(
                label: 'Rescan all',
                icon: FluentIcons.arrow_sync_24_regular,
                onTap: onRescanValidation,
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Pack', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.box_24_regular,
              label: 'Generate pack',
              onTap: onExport,
            ),
            const SizedBox(height: 6),
            Center(
              child: SmallTextButton(
                label: 'Import pack',
                icon: FluentIcons.arrow_import_24_regular,
                onTap: onImportPack,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final TwmtThemeTokens tokens;
  const _SectionHeader({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayStyle,
              fontSize: 13,
              color: tokens.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.border, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  /// Optional trailing keyboard-shortcut hint (e.g. `Ctrl+T`). When provided,
  /// the button layout switches from centre-hug to a left-anchored label with
  /// the hint pinned right so users can discover the binding at a glance.
  final String? shortcutHint;

  const _SidebarActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.shortcutHint,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onTap != null;
    final bg = primary
        ? tokens.accent
        : (enabled ? tokens.panel2 : Colors.transparent);
    final fg = primary
        ? tokens.accentFg
        : (enabled ? tokens.text : tokens.textFaint);
    final borderColor = primary
        ? tokens.accent
        : tokens.border;
    final hasHint = shortcutHint != null;
    final labelText = Text(
      label,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: tokens.fontBody.copyWith(
        fontSize: 12.5,
        color: fg,
        fontWeight: FontWeight.w500,
      ),
    );
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          alignment: Alignment.center,
          // A single hug-and-centre layout whether or not a hint is attached:
          // icon + label + (optional) kbd badge sit in one tight cluster.
          // This keeps the badge visually identical across states — long
          // labels ellipsize via [Flexible] rather than stretching a gap.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Flexible(child: labelText),
              if (hasHint) ...[
                const SizedBox(width: 6),
                _KbdBadge(text: shortcutHint!, primary: primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline keyboard-shortcut chip rendered inside action buttons.
///
/// Matches the button's variant: on [primary] buttons we tint a translucent
/// accent-fg pill; on outlined buttons we drop the chip onto the panel surface
/// with a dim foreground. Text is rendered in a monospace-like face at 10px
/// so it reads as "kbd" rather than regular copy.
class _KbdBadge extends StatelessWidget {
  final String text;
  final bool primary;

  const _KbdBadge({required this.text, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = primary ? tokens.accentFg : tokens.textDim;
    final bg = primary
        ? tokens.accentFg.withValues(alpha: 0.16)
        : tokens.panel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}
