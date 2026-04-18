import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

import 'editor_toolbar_mod_rule.dart';
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';

/// Left sidebar of the translation editor (240 px).
///
/// Replaces the ex-`EditorFilterPanel`. Filters moved to the top
/// `FilterToolbar` (STATUS + TM SOURCE pill groups). This panel now hosts
/// every control previously in `EditorActionBar`, organised into 4 labelled
/// sections: §SEARCH · §CONTEXT · §ACTIONS · §SETTINGS.
class EditorActionSidebar extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final FocusNode searchFocusNode;
  final VoidCallback onTranslationSettings;
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
    required this.searchFocusNode,
    required this.onTranslationSettings,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onRescanValidation,
    required this.onExport,
    required this.onImportPack,
  });

  @override
  ConsumerState<EditorActionSidebar> createState() =>
      _EditorActionSidebarState();
}

class _EditorActionSidebarState extends ConsumerState<EditorActionSidebar> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      ref.read(editorFilterProvider.notifier).setSearchQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
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
            _SectionHeader(label: 'Search', tokens: tokens),
            const SizedBox(height: 10),
            TokenTextField(
              controller: _searchController,
              focusNode: widget.searchFocusNode,
              hint: 'Search · filter · run',
              enabled: true,
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Context', tokens: tokens),
            const SizedBox(height: 10),
            const EditorToolbarModelSelector(compact: true),
            const SizedBox(height: 10),
            const EditorToolbarSkipTm(compact: true),
            const SizedBox(height: 10),
            EditorToolbarModRule(
              compact: true,
              projectId: widget.projectId,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Actions', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.translate_24_regular,
              label: 'Translate all',
              primary: true,
              onTap: widget.onTranslateAll,
            ),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final selection = ref.watch(editorSelectionProvider);
                return _SidebarActionButton(
                  icon: FluentIcons.translate_24_filled,
                  label: 'Selection',
                  onTap: selection.hasSelection
                      ? widget.onTranslateSelected
                      : null,
                );
              },
            ),
            const SizedBox(height: 16),
            _SidebarActionButton(
              icon: FluentIcons.checkmark_circle_24_regular,
              label: 'Validate selected',
              onTap: widget.onValidate,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SmallTextButton(
                label: 'Rescan all',
                onTap: widget.onRescanValidation,
              ),
            ),
            const SizedBox(height: 16),
            _SidebarActionButton(
              icon: FluentIcons.box_24_regular,
              label: 'Generate pack',
              onTap: widget.onExport,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: SmallTextButton(
                label: 'Import pack',
                onTap: widget.onImportPack,
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Settings', tokens: tokens),
            const SizedBox(height: 10),
            _SidebarActionButton(
              icon: FluentIcons.settings_24_regular,
              label: 'Translation settings',
              onTap: widget.onTranslationSettings,
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
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
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
