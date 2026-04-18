import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_filter_notifier.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
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
