import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/workflow/pipeline_timeline.dart';

import 'editor_toolbar_batch_settings.dart';
import 'editor_toolbar_mod_rule.dart';
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';

/// Left sidebar of the translation editor (240 px).
///
/// Hosts the controls previously in `EditorActionBar`, organised into 3
/// labelled sections by intent: §AI CONTEXT (model + prompt configuration),
/// §OTHER (Import pack) and §WORKFLOW (Translate → Review → Generate pack
/// as a numbered pipeline, mirroring the main navigation sidebar's Workflow
/// group). The search field lives in the top `FilterToolbar`; filters are
/// the STATE pill group.
///
/// §Workflow step 1 exposes a single smart button: when the grid has rows
/// selected it reads "Translate selection" and routes to
/// [onTranslateSelected]; otherwise it reads "Translate all" and routes to
/// [onTranslateAll]. The `Ctrl+T` screen-scope shortcut mirrors this
/// routing — selection-aware by design.
class EditorActionSidebar extends ConsumerWidget {
  final String projectId;
  final String languageId;
  final VoidCallback onTranslateAll;
  final VoidCallback onTranslateSelected;
  final VoidCallback onValidate;
  final VoidCallback onExport;
  final VoidCallback onImportPack;
  final VoidCallback onOpenModFolder;

  const EditorActionSidebar({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onExport,
    required this.onImportPack,
    required this.onOpenModFolder,
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
            _SectionHeader(label: t.translationEditor.toolbar.sectionAiContext, tokens: tokens),
            const SizedBox(height: 10),
            const EditorToolbarModelSelector(),
            const SizedBox(height: 8),
            const EditorToolbarSkipTm(),
            const SizedBox(height: 8),
            EditorToolbarModRule(projectId: projectId),
            const SizedBox(height: 10),
            const EditorToolbarBatchSettings(),
            const SizedBox(height: 20),
            _SectionHeader(label: t.translationEditor.toolbar.sectionOther, tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.arrow_import_24_regular,
              label: t.translationEditor.toolbar.importExternalPack,
              onTap: onImportPack,
            ),
            const SizedBox(height: 8),
            _SidebarActionButton(
              icon: FluentIcons.folder_open_24_regular,
              label: t.translationEditor.toolbar.openLocalFolder,
              onTap: onOpenModFolder,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: t.translationEditor.toolbar.sectionWorkflow, tokens: tokens),
            const SizedBox(height: 10),
            // Workflow pipeline — same layout pattern as the main navigation
            // sidebar's Workflow group: a single vertical timeline rail
            // threads three numbered waypoints (Translate · Validate ·
            // Generate pack), rendered as one continuous stroke.
            pipelineRow(
              rail: const TimelineRail(
                step: 1,
                primary: true,
                lineAbove: false,
              ),
              child: Consumer(
                builder: (context, ref, _) {
                  final selection = ref.watch(editorSelectionProvider);
                  final hasSelection = selection.hasSelection;
                  final label = hasSelection
                      ? t.translationEditor.sidebar.translateSelection
                      : t.translationEditor.sidebar.translateAll;
                  final button = _SidebarActionButton(
                    icon: FluentIcons.translate_24_regular,
                    label: label,
                    primary: true,
                    onTap:
                        hasSelection ? onTranslateSelected : onTranslateAll,
                  );

                  // Pick the count that matches the button's current mode:
                  //   - Selection mode → show how many rows are selected.
                  //   - Translate-all mode → show the pending total (only
                  //     once editorStats has resolved, to avoid a flicker).
                  final int count;
                  if (hasSelection) {
                    count = selection.selectedCount;
                  } else {
                    final statsAsync =
                        ref.watch(editorStatsProvider(projectId, languageId));
                    count = statsAsync.asData?.value.pendingCount ?? 0;
                  }
                  if (count <= 0) return button;

                  final unitLabel = count == 1
                      ? t.translationEditor.sidebar.unitSingular
                      : t.translationEditor.sidebar.unitPlural;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      button,
                      const SizedBox(height: 4),
                      Text(
                        '$count $unitLabel',
                        textAlign: TextAlign.center,
                        style: tokens.fontBody.copyWith(
                          fontSize: 10.5,
                          color: tokens.textDim,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            pipelineRow(
              rail: const TimelineRail(),
              child: const SizedBox(height: 12),
            ),
            // Single unified entry point: `handleValidate` rescans all
            // translated rows then filters the grid down to `needsReview`.
            pipelineRow(
              rail: const TimelineRail(step: 2),
              child: Consumer(
                builder: (context, ref, _) {
                  final button = _SidebarActionButton(
                    icon: FluentIcons.checkmark_circle_24_regular,
                    label: t.translationEditor.sidebar.review,
                    onTap: onValidate,
                  );

                  final statsAsync =
                      ref.watch(editorStatsProvider(projectId, languageId));
                  final needsReview =
                      statsAsync.asData?.value.needsReviewCount ?? 0;
                  if (needsReview <= 0) return button;

                  final reviewLabel = needsReview == 1
                      ? t.translationEditor.sidebar.unitSingular
                      : t.translationEditor.sidebar.unitPlural;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      button,
                      const SizedBox(height: 4),
                      Text(
                        '$needsReview $reviewLabel',
                        textAlign: TextAlign.center,
                        style: tokens.fontBody.copyWith(
                          fontSize: 10.5,
                          color: tokens.textDim,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            pipelineRow(
              rail: const TimelineRail(),
              child: const SizedBox(height: 12),
            ),
            pipelineRow(
              rail: const TimelineRail(step: 3, lineBelow: false),
              child: _SidebarActionButton(
                icon: FluentIcons.box_24_regular,
                label: t.translationEditor.sidebar.generatePack,
                onTap: onExport,
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
    return Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: tokens.fontDisplay.copyWith(
        fontStyle: tokens.fontDisplayStyle,
        fontSize: 13,
        color: tokens.accent,
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _SidebarActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
