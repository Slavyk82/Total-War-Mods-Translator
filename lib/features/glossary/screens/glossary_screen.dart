import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/utils/game_label.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/detail/home_back_toolbar.dart';

import '../providers/glossary_providers.dart';
import '../widgets/glossary_datagrid.dart';
import '../widgets/glossary_entry_editor.dart';
import '../widgets/glossary_export_dialog.dart';
import '../widgets/glossary_import_dialog.dart';
import '../widgets/glossary_language_switcher.dart';

/// Main screen for per-game glossary management.
///
/// Glossaries are auto-provisioned per `(gameCode, targetLanguageId)` pair
/// and cannot be created manually any more. The screen walks through four
/// precondition states before showing the editor:
///
/// 1. No game selected in the sidebar → prompt to select one.
/// 2. Game selected but it has zero projects → explain that a glossary will
///    be generated when the first project is created.
/// 3. Game with projects but no target languages configured → explain that
///    a glossary will be generated when a project language is added.
/// 4. Game + language selected, glossary empty → soft empty state inside
///    the entries grid.
/// 5. Nominal — the entries grid with search + import/export + add entry.
class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  final _entrySearchController = TextEditingController();

  @override
  void dispose() {
    _entrySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gameAsync = ref.watch(selectedGameProvider);

    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(
            leading: ListToolbarLeading(
              icon: FluentIcons.book_24_regular,
              title: t.glossary.labels.title,
            ),
          ),
          Expanded(
            child: gameAsync.when(
              loading: () => const Center(child: FluentInlineSpinner()),
              error: (error, _) => _buildError(context, error),
              data: (game) {
                if (game == null) {
                  return _buildCenteredMessage(
                    context,
                    t.glossary.messages.selectGameForGlossary,
                  );
                }
                return _buildForGame(context, game);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForGame(BuildContext context, ConfiguredGame game) {
    final hasProjectsAsync =
        ref.watch(hasProjectsForGameProvider(game.code));

    return hasProjectsAsync.when(
      loading: () => const Center(child: FluentInlineSpinner()),
      error: (error, _) => _buildError(context, error),
      data: (hasProjects) {
        if (!hasProjects) {
          return _buildCenteredMessage(
            context,
            t.glossary.messages.noProjectsYet(game: gameLabel(game.name)),
          );
        }
        return _buildWithProjects(context, game);
      },
    );
  }

  Widget _buildWithProjects(BuildContext context, ConfiguredGame game) {
    final langsAsync =
        ref.watch(glossaryAvailableLanguagesProvider(game.code));

    return langsAsync.when(
      loading: () => const Center(child: FluentInlineSpinner()),
      error: (error, _) => _buildError(context, error),
      data: (languages) {
        if (languages.isEmpty) {
          return _buildCenteredMessage(
            context,
            t.glossary.messages.noTargetLanguages(game: gameLabel(game.name)),
          );
        }
        return _buildEditor(context, game, languages);
      },
    );
  }

  Widget _buildEditor(
    BuildContext context,
    ConfiguredGame game,
    List<Language> languages,
  ) {
    final tokens = context.tokens;
    final selectedLangAsync =
        ref.watch(selectedGlossaryLanguageProvider(game.code));
    final selectedLangId = selectedLangAsync.asData?.value;
    final glossaryAsync = ref.watch(currentGlossaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top bar: language switcher chip (the screen title now lives in
        // `HomeBackToolbar` above).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: tokens.panel,
            border: Border(
              bottom: BorderSide(color: tokens.border),
            ),
          ),
          child: Row(
            children: [
              GlossaryLanguageSwitcher(
                gameCode: game.code,
                currentLanguageId: selectedLangId,
              ),
            ],
          ),
        ),
        Expanded(
          child: glossaryAsync.when(
            loading: () => const Center(child: FluentInlineSpinner()),
            error: (error, _) => _buildError(context, error),
            data: (glossary) {
              if (glossary == null) {
                // Either the language isn't picked yet or the per-game
                // auto-provisioning hasn't fired — either way, prompt the
                // user to pick from the switcher.
                return _buildCenteredMessage(
                  context,
                  t.glossary.messages.selectTargetLanguage,
                );
              }
              return _buildEditorBody(context, glossary, languages);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditorBody(
    BuildContext context,
    Glossary glossary,
    List<Language> languages,
  ) {
    final tokens = context.tokens;
    String? targetLanguageCode;
    for (final language in languages) {
      if (language.id == glossary.targetLanguageId) {
        targetLanguageCode = language.code;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ListSearchField(
                      value: _entrySearchController.text,
                      hintText: t.glossary.hints.searchEntries,
                      onChanged: (value) {
                        setState(() {
                          _entrySearchController.text = value;
                        });
                        ref
                            .read(glossaryFilterStateProvider.notifier)
                            .setSearchText(value);
                      },
                      onClear: () {
                        setState(_entrySearchController.clear);
                        ref
                            .read(glossaryFilterStateProvider.notifier)
                            .setSearchText('');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmallTextButton(
                    label: t.glossary.actions.addEntry,
                    icon: FluentIcons.add_24_regular,
                    onTap: () => _showEntryEditor(glossary, targetLanguageCode),
                  ),
                  const SizedBox(width: 6),
                  SmallTextButton(
                    label: t.glossary.actions.import,
                    icon: FluentIcons.arrow_import_24_regular,
                    onTap: () => _showImportDialog(glossary),
                  ),
                  const SizedBox(width: 6),
                  SmallTextButton(
                    label: t.glossary.actions.export,
                    icon: FluentIcons.arrow_export_24_regular,
                    onTap: () => _showExportDialog(glossary),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: tokens.border),
            Expanded(
              child: glossary.entryCount == 0
                  ? _buildSoftEmpty(context)
                  : GlossaryDataGrid(glossaryId: glossary.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoftEmpty(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.book_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              t.glossary.messages.noEntriesYet,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenteredMessage(BuildContext context, String message) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Text(
          message,
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: tokens.err,
            ),
            const SizedBox(height: 12),
            Text(
              t.glossary.messages.errorLoadingGlossary,
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle: tokens.fontDisplayStyle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showEntryEditor(
    Glossary glossary,
    String? targetLanguageCode, {
    GlossaryEntry? existing,
  }) {
    if (targetLanguageCode == null) {
      FluentToast.error(
        context,
        t.glossary.messages.unableToResolveLanguage,
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => GlossaryEntryEditorDialog(
        glossaryId: glossary.id,
        targetLanguageCode: targetLanguageCode,
        entry: existing,
      ),
    );
  }

  void _showImportDialog(Glossary glossary) {
    showDialog<void>(
      context: context,
      builder: (_) => GlossaryImportDialog(glossaryId: glossary.id),
    );
  }

  void _showExportDialog(Glossary glossary) {
    showDialog<void>(
      context: context,
      builder: (_) => GlossaryExportDialog(glossaryId: glossary.id),
    );
  }
}
