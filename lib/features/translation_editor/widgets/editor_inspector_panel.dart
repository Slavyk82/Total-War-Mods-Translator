import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_validation_panel.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Callback fired when the user commits a target text edit (Ctrl+Enter).
typedef OnInspectorSave = void Function(String unitId, String text);

/// Callback fired when the user applies a TM suggestion or auto-fix.
typedef OnInspectorApplySuggestion =
    void Function(String unitId, String text);

/// 320px right inspector panel of the translation editor.
///
/// Three render branches based on `editorSelectionProvider.selectedCount`:
/// - 0 -> empty placeholder.
/// - 1 -> full inspector (key + Source + Target + Suggestions + Validation).
/// - N>1 -> multi-select header with batch hints.
class EditorInspectorPanel extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final OnInspectorSave onSave;
  final OnInspectorApplySuggestion onApplySuggestion;

  const EditorInspectorPanel({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onSave,
    required this.onApplySuggestion,
  });

  @override
  ConsumerState<EditorInspectorPanel> createState() =>
      _EditorInspectorPanelState();
}

class _EditorInspectorPanelState extends ConsumerState<EditorInspectorPanel> {
  final _targetController = TextEditingController();
  String? _boundUnitId;

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selection = ref.watch(editorSelectionProvider);
    final rowsAsync = ref.watch(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final rows = rowsAsync.value ?? const <TranslationRow>[];

    Widget body;
    if (selection.selectedCount == 0 || rows.isEmpty) {
      body = _EmptyState(tokens: tokens);
    } else if (selection.selectedCount > 1) {
      body = _MultiSelectHeader(
        count: selection.selectedCount,
        tokens: tokens,
      );
    } else {
      final selectedId = selection.selectedUnitIds.first;
      final idx = rows.indexWhere((r) => r.id == selectedId);
      if (idx < 0) {
        body = _EmptyState(tokens: tokens);
      } else {
        final row = rows[idx];
        _bindControllerForUnit(row);
        body = _SingleSelectionBody(
          row: row,
          index: idx + 1,
          total: rows.length,
          controller: _targetController,
          onSave: (text) => widget.onSave(row.id, text),
          onApplySuggestion: (text) => widget.onApplySuggestion(row.id, text),
          tokens: tokens,
          projectId: widget.projectId,
          languageId: widget.languageId,
        );
      }
    }

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      padding: const EdgeInsets.all(20),
      child: body,
    );
  }

  /// Sync the target controller text with the currently selected row.
  ///
  /// Called from `build` (tolerated because it only mutates the controller
  /// when the bound unit ID changes; `_boundUnitId` guards the assignment).
  void _bindControllerForUnit(TranslationRow row) {
    if (_boundUnitId != row.id) {
      _boundUnitId = row.id;
      _targetController.text = row.translatedText ?? '';
    }
  }
}

class _EmptyState extends StatelessWidget {
  final TwmtThemeTokens tokens;
  const _EmptyState({required this.tokens});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.info_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'Sélectionnez une unité pour voir les détails',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMid, fontSize: 13),
            ),
          ],
        ),
      );
}

class _MultiSelectHeader extends StatelessWidget {
  final int count;
  final TwmtThemeTokens tokens;
  const _MultiSelectHeader({required this.count, required this.tokens});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count unités sélectionnées',
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontSize: 16,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 16),
          _Hint(label: 'Ctrl+T', text: 'translate selected', tokens: tokens),
          _Hint(label: 'Ctrl+R', text: 'retranslate selected', tokens: tokens),
          _Hint(
            label: 'Ctrl+Shift+V',
            text: 'validate selected',
            tokens: tokens,
          ),
        ],
      );
}

class _SingleSelectionBody extends ConsumerWidget {
  final TranslationRow row;
  final int index;
  final int total;
  final TextEditingController controller;
  final void Function(String) onSave;
  final void Function(String) onApplySuggestion;
  final TwmtThemeTokens tokens;
  final String projectId;
  final String languageId;

  const _SingleSelectionBody({
    required this.row,
    required this.index,
    required this.total,
    required this.controller,
    required this.onSave,
    required this.onApplySuggestion,
    required this.tokens,
    required this.projectId,
    required this.languageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider(projectId)).value;
    final language = ref.watch(currentLanguageProvider(languageId)).value;
    final sourceCode = project?.sourceLanguageCode ?? 'en';
    final targetCode = language?.code ?? 'fr';

    final suggestionsAsync = ref.watch(
      tmSuggestionsForUnitProvider(row.id, sourceCode, targetCode),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(index: index, total: total, tokens: tokens),
          const SizedBox(height: 10),
          _KeyChip(
            text: '${row.sourceLocFile ?? ''} / ${row.key}',
            tokens: tokens,
          ),
          const SizedBox(height: 14),
          _SourceBlock(
            text: row.sourceText,
            lang: sourceCode,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
          _TargetBlock(
            controller: controller,
            lang: targetCode,
            onSave: onSave,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
          _SuggestionsSection(
            async: suggestionsAsync,
            onApply: onApplySuggestion,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
          EditorValidationPanel(
            sourceText: row.sourceText,
            translatedText: row.translatedText,
            onApplyFix: (fixed) => onApplySuggestion(fixed),
            onValidate: () {},
          ),
          const SizedBox(height: 14),
          _FooterHints(tokens: tokens),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int index;
  final int total;
  final TwmtThemeTokens tokens;
  const _Header({
    required this.index,
    required this.total,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Unité',
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontSize: 14,
              color: tokens.accent,
            ),
          ),
          Text(
            '$index / $total',
            style: tokens.fontMono.copyWith(
              fontSize: 10.5,
              color: tokens.textFaint,
            ),
          ),
        ],
      );
}

class _KeyChip extends StatelessWidget {
  final String text;
  final TwmtThemeTokens tokens;
  const _KeyChip({required this.text, required this.tokens});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.panel2,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: tokens.fontMono.copyWith(
            fontSize: 11,
            color: tokens.textMid,
          ),
        ),
      );
}

class _SourceBlock extends StatelessWidget {
  final String text;
  final String lang;
  final TwmtThemeTokens tokens;
  const _SourceBlock({
    required this.text,
    required this.lang,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(text: 'Source · $lang', tokens: tokens),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textMid,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
}

class _TargetBlock extends StatelessWidget {
  final TextEditingController controller;
  final String lang;
  final void Function(String) onSave;
  final TwmtThemeTokens tokens;
  const _TargetBlock({
    required this.controller,
    required this.lang,
    required this.onSave,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            text: 'Cible · $lang — édition',
            tokens: tokens,
            withBullet: true,
          ),
          const SizedBox(height: 6),
          Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  const _SaveIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SaveIntent: CallbackAction<_SaveIntent>(
                  onInvoke: (_) {
                    onSave(controller.text);
                    return null;
                  },
                ),
              },
              child: TextField(
                key: const Key('editor-inspector-target-field'),
                controller: controller,
                maxLines: null,
                minLines: 3,
                style: TextStyle(
                  fontSize: 13.5,
                  color: tokens.text,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: tokens.accentBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: tokens.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _SuggestionsSection extends StatelessWidget {
  final AsyncValue<List<TmMatch>> async;
  final void Function(String) onApply;
  final TwmtThemeTokens tokens;
  const _SuggestionsSection({
    required this.async,
    required this.onApply,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final children = async.when(
      data: (matches) {
        if (matches.isEmpty) {
          return [
            Text(
              'Aucune correspondance',
              style: TextStyle(color: tokens.textFaint, fontSize: 12),
            ),
          ];
        }
        return matches
            .map((m) => _SuggestionRow(
                  match: m,
                  onTap: () => onApply(m.targetText),
                  tokens: tokens,
                ))
            .toList();
      },
      loading: () => [
        Text('· · ·', style: TextStyle(color: tokens.textFaint)),
      ],
      error: (_, _) => [
        Text(
          'Erreur de chargement TM',
          style: TextStyle(color: tokens.err, fontSize: 12),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(text: 'Suggestions', tokens: tokens),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final TmMatch match;
  final VoidCallback onTap;
  final TwmtThemeTokens tokens;
  const _SuggestionRow({
    required this.match,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final pct = match.matchType == TmMatchType.exact
        ? 'TM 100%'
        : 'TM ${(match.similarityScore * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    match.targetText,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tokens.textMid),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  pct,
                  style: tokens.fontMono.copyWith(
                    fontSize: 10,
                    color: tokens.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final TwmtThemeTokens tokens;
  final bool withBullet;
  const _Label({
    required this.text,
    required this.tokens,
    this.withBullet = false,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (withBullet) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text.toUpperCase(),
            style: tokens.fontMono.copyWith(
              fontSize: 9.5,
              color: tokens.textFaint,
              letterSpacing: 1.5,
            ),
          ),
        ],
      );
}

class _Hint extends StatelessWidget {
  final String label;
  final String text;
  final TwmtThemeTokens tokens;
  const _Hint({
    required this.label,
    required this.text,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        // `Wrap` instead of `Row` so the kbd chip + label can flow onto two
        // lines when the host width is tight (multi-select column @ 280px) and
        // still lay out as a single line inside the footer `Wrap` parent.
        child: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                label,
                style: tokens.fontMono.copyWith(
                  fontSize: 9.5,
                  color: tokens.textMid,
                ),
              ),
            ),
            Text(
              text,
              style: TextStyle(fontSize: 12, color: tokens.textMid),
            ),
          ],
        ),
      );
}

class _FooterHints extends StatelessWidget {
  final TwmtThemeTokens tokens;
  const _FooterHints({required this.tokens});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _Hint(label: 'Ctrl+Enter', text: 'save', tokens: tokens),
          _Hint(label: '↓', text: 'next', tokens: tokens),
          _Hint(label: 'Ctrl+R', text: 'retranslate', tokens: tokens),
          _Hint(label: 'Ctrl+Shift+V', text: 'validate', tokens: tokens),
        ],
      );
}
