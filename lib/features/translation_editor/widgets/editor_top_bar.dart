import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'editor_toolbar_mod_rule.dart';
import 'editor_toolbar_model_selector.dart';
import 'editor_toolbar_skip_tm.dart';

/// Top bar of the translation editor (56px).
///
/// Replaces the previous EditorToolbar + FluentScaffold header.
/// Contains: clickable crumb, model selector, skip-tm, 5 actions, Settings, search.
class EditorTopBar extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final VoidCallback onTranslationSettings;
  final VoidCallback onTranslateAll;
  final VoidCallback onTranslateSelected;
  final VoidCallback onValidate;
  final VoidCallback onRescanValidation;
  final VoidCallback onExport;
  final VoidCallback onImportPack;

  const EditorTopBar({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onTranslationSettings,
    required this.onTranslateAll,
    required this.onTranslateSelected,
    required this.onValidate,
    required this.onRescanValidation,
    required this.onExport,
    required this.onImportPack,
  });

  @override
  ConsumerState<EditorTopBar> createState() => _EditorTopBarState();
}

class _EditorTopBarState extends ConsumerState<EditorTopBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selection = ref.watch(editorSelectionProvider);
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _TranslateSelectedIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true):
            _TranslateAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
            _ValidateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              _searchFocus.requestFocus();
              return null;
            },
          ),
          _TranslateSelectedIntent: CallbackAction<_TranslateSelectedIntent>(
            onInvoke: (_) {
              if (selection.hasSelection) widget.onTranslateSelected();
              return null;
            },
          ),
          _TranslateAllIntent: CallbackAction<_TranslateAllIntent>(
            onInvoke: (_) {
              widget.onTranslateAll();
              return null;
            },
          ),
          _ValidateIntent: CallbackAction<_ValidateIntent>(
            onInvoke: (_) {
              widget.onValidate();
              return null;
            },
          ),
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: tokens.panel,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              // Fixed-width left side: clickable crumb + separator.
              _Crumb(projectName: projectName, languageName: languageName),
              const _Sep(),

              // Scrollable middle: model selector, skip-tm, rules chip and
              // the 4 action buttons. Wrapped in a horizontal scroll view so
              // narrow viewports (down to the 1280px min-width) never trigger
              // a layout overflow.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const EditorToolbarModelSelector(compact: false),
                      const SizedBox(width: 14),
                      const EditorToolbarSkipTm(compact: false),
                      const _Sep(),
                      EditorToolbarModRule(
                        compact: false,
                        projectId: widget.projectId,
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: FluentIcons.translate_24_filled,
                        label: 'Selection',
                        kbd: 'Ctrl+T',
                        onTap: selection.hasSelection
                            ? widget.onTranslateSelected
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: FluentIcons.translate_24_regular,
                        label: 'Translate all',
                        kbd: 'Ctrl+Shift+T',
                        primary: true,
                        onTap: widget.onTranslateAll,
                      ),
                      const SizedBox(width: 8),
                      _SplitButton(
                        icon: FluentIcons.checkmark_circle_24_regular,
                        label: 'Validate',
                        kbd: 'Ctrl+Shift+V',
                        onTap: widget.onValidate,
                        menuItems: [
                          _MenuEntry('Validate selected', widget.onValidate),
                          _MenuEntry('Rescan all', widget.onRescanValidation),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _SplitButton(
                        icon: FluentIcons.box_24_regular,
                        label: 'Pack',
                        onTap: widget.onExport,
                        menuItems: [
                          _MenuEntry('Generate pack', widget.onExport),
                          _MenuEntry('Import pack', widget.onImportPack),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Fixed-width right side: Settings + separator + search field.
              IconButton(
                icon: const Icon(FluentIcons.settings_24_regular, size: 18),
                onPressed: widget.onTranslationSettings,
                tooltip: 'Translation settings',
                color: tokens.textMid,
              ),
              const _Sep(),
              _SearchField(
                controller: _searchController,
                focus: _searchFocus,
                onChanged: (v) => ref
                    .read(editorFilterProvider.notifier)
                    .setSearchQuery(v),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _TranslateSelectedIntent extends Intent {
  const _TranslateSelectedIntent();
}

class _TranslateAllIntent extends Intent {
  const _TranslateAllIntent();
}

class _ValidateIntent extends Intent {
  const _ValidateIntent();
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: context.tokens.border,
      );
}

class _Crumb extends StatelessWidget {
  final String projectName;
  final String languageName;
  const _Crumb({required this.projectName, required this.languageName});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              'Projects',
              style: TextStyle(fontSize: 13.5, color: tokens.textMid),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('›', style: TextStyle(color: tokens.border)),
        ),
        if (projectName.isNotEmpty)
          Text(
            projectName,
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontSize: 18,
              color: tokens.text,
            ),
          ),
        if (languageName.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('›', style: TextStyle(color: tokens.border)),
          ),
          Text(
            languageName,
            style: TextStyle(
              fontSize: 13.5,
              color: tokens.accent,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? kbd;
  final VoidCallback? onTap;
  final bool primary;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.kbd,
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
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              color: primary ? tokens.accent : tokens.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (kbd != null) ...[
                const SizedBox(width: 8),
                _KbdChip(label: kbd!, primary: primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KbdChip extends StatelessWidget {
  final String label;
  final bool primary;
  const _KbdChip({required this.label, required this.primary});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = primary
        ? tokens.accentFg.withValues(alpha: 0.7)
        : tokens.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: tokens.fontMono.copyWith(
          fontSize: 9.5,
          color: color,
        ),
      ),
    );
  }
}

class _MenuEntry {
  final String label;
  final VoidCallback onTap;
  _MenuEntry(this.label, this.onTap);
}

class _SplitButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? kbd;
  final VoidCallback onTap;
  final List<_MenuEntry> menuItems;

  const _SplitButton({
    required this.icon,
    required this.label,
    this.kbd,
    required this.onTap,
    required this.menuItems,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(icon: icon, label: label, kbd: kbd, onTap: onTap),
        const SizedBox(width: 2),
        PopupMenuButton<int>(
          tooltip: 'More $label actions',
          padding: EdgeInsets.zero,
          icon: Icon(
            FluentIcons.chevron_down_24_regular,
            size: 14,
            color: tokens.textMid,
          ),
          itemBuilder: (_) => [
            for (var i = 0; i < menuItems.length; i++)
              PopupMenuItem(value: i, child: Text(menuItems[i].label)),
          ],
          onSelected: (i) => menuItems[i].onTap(),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: 240,
      child: TextField(
        controller: controller,
        focusNode: focus,
        onChanged: onChanged,
        style: tokens.fontMono.copyWith(
          fontSize: 12.5,
          color: tokens.text,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: tokens.panel2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: tokens.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: tokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: tokens.accent),
          ),
          hintText: 'Search · filter · run',
          hintStyle: tokens.fontMono.copyWith(
            color: tokens.textFaint,
            fontSize: 12.5,
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Container(
              alignment: Alignment.center,
              constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.textFaint),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'Ctrl+F',
                style: tokens.fontMono.copyWith(
                  fontSize: 9.5,
                  color: tokens.textFaint,
                ),
              ),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(maxHeight: 24),
        ),
      ),
    );
  }
}
