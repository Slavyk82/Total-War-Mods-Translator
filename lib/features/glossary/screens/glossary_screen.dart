import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/service_providers.dart';
import '../providers/glossary_providers.dart';
import '../widgets/glossary_datagrid.dart';
import '../widgets/glossary_entry_editor.dart';
import '../widgets/glossary_export_dialog.dart';
import '../widgets/glossary_import_dialog.dart';
import '../widgets/glossary_list.dart';
import '../widgets/glossary_new_dialog.dart';
import '../widgets/glossary_screen_components.dart';
import '../widgets/glossary_statistics_panel.dart';
import '../widgets/glossary_toolbar.dart';

/// Main screen for Glossary management.
///
/// List view uses the §7.1 filterable-list archetype ([GlossaryToolbar]
/// on top of a tokenised [SfDataGrid]). Selecting a row swaps in the
/// inline entry editor view — preserved untouched from the legacy
/// implementation per Plan 5a Task 5 scope.
class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  final _entrySearchController = TextEditingController();
  Map<String, GameInstallation> _gameInstallations = {};
  String _listSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadGameInstallations();
  }

  Future<void> _loadGameInstallations() async {
    final repository = ref.read(gameInstallationRepositoryProvider);
    final result = await repository.getAll();
    result.when(
      ok: (games) {
        if (mounted) {
          setState(() {
            _gameInstallations = {for (final g in games) g.id: g};
          });
        }
      },
      err: (_) {},
    );
  }

  @override
  void dispose() {
    _entrySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selectedGlossary = ref.watch(selectedGlossaryProvider);

    return Material(
      color: tokens.bg,
      child: selectedGlossary == null
          ? _buildGlossaryListView(context)
          : _buildGlossaryEditorView(context, selectedGlossary),
    );
  }

  Widget _buildGlossaryListView(BuildContext context) {
    final glossariesAsync = ref.watch(glossariesProvider());
    // Compute the filtered list ONCE per rebuild. The toolbar and the
    // grid body both need it; running `_applyListSearch` twice would be
    // wasteful on the larger datasets Translation Memory will mirror.
    final all = glossariesAsync.asData?.value ?? const <Glossary>[];
    final filtered = _applyListSearch(all);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildListToolbar(totalCount: all.length, filteredCount: filtered.length),
        Expanded(
          child: glossariesAsync.when(
            data: (glossaries) {
              if (glossaries.isEmpty) {
                return GlossaryEmptyState(
                  onNewGlossary: _showNewGlossaryDialog,
                );
              }
              if (filtered.isEmpty) {
                return _buildNoMatchesState(context);
              }
              return GlossaryList(
                glossaries: filtered,
                gameInstallations: _gameInstallations,
                onGlossaryTap: (glossary) {
                  ref.read(selectedGlossaryProvider.notifier).select(glossary);
                },
                onDeleteGlossary: _confirmDeleteGlossary,
              );
            },
            loading: () => const Center(child: FluentInlineSpinner()),
            error: (error, stack) => _buildError(error),
          ),
        ),
      ],
    );
  }

  Widget _buildListToolbar({required int totalCount, required int filteredCount}) {
    return GlossaryToolbar(
      totalCount: totalCount,
      filteredCount: filteredCount,
      searchQuery: _listSearchQuery,
      onSearchChanged: (value) => setState(() => _listSearchQuery = value),
      onNewGlossary: _showNewGlossaryDialog,
    );
  }

  List<Glossary> _applyListSearch(List<Glossary> source) {
    final query = _listSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((g) {
      if (g.name.toLowerCase().contains(query)) return true;
      final description = g.description;
      if (description != null && description.toLowerCase().contains(query)) {
        return true;
      }
      return false;
    }).toList();
  }

  Widget _buildNoMatchesState(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.search_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              'No glossaries match the current search',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.text,
                fontStyle: tokens.fontDisplayItalic
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
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
              'Error loading glossaries',
              style: tokens.fontDisplay.copyWith(
                fontSize: 16,
                color: tokens.err,
                fontStyle: tokens.fontDisplayItalic
                    ? FontStyle.italic
                    : FontStyle.normal,
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

  Widget _buildGlossaryEditorView(BuildContext context, Glossary glossary) {
    return Column(
      children: [
        GlossaryEditorHeader(
          glossary: glossary,
          gameInstallations: _gameInstallations,
          onImport: _showImportDialog,
          onExport: _showExportDialog,
          onDelete: () => _confirmDeleteGlossary(glossary),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 280,
                child: GlossaryStatisticsPanel(glossaryId: glossary.id),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    GlossaryEditorToolbar(
                      glossary: glossary,
                      searchController: _entrySearchController,
                      onAddEntry: () => _showEntryEditor(null, glossary),
                    ),
                    const Divider(height: 1),
                    Expanded(child: GlossaryDataGrid(glossaryId: glossary.id)),
                    const Divider(height: 1),
                    GlossaryEditorFooter(
                      glossary: glossary,
                      gameInstallations: _gameInstallations,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showNewGlossaryDialog() {
    showDialog(
      context: context,
      builder: (context) => const NewGlossaryDialog(),
    );
  }

  void _showEntryEditor(GlossaryEntry? entry, Glossary glossary) async {
    String? targetLanguageCode;
    if (glossary.targetLanguageId != null) {
      try {
        final languageRepo = ref.read(languageRepositoryProvider);
        final langResult = await languageRepo.getById(glossary.targetLanguageId!);
        langResult.when(
          ok: (language) {
            targetLanguageCode = language.code;
          },
          err: (_) {},
        );
      } catch (_) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => GlossaryEntryEditorDialog(
        glossaryId: glossary.id,
        targetLanguageCode: targetLanguageCode,
        entry: entry,
      ),
    );
  }

  void _showImportDialog() {
    final selectedGlossary = ref.read(selectedGlossaryProvider);
    if (selectedGlossary == null) return;

    showDialog(
      context: context,
      builder: (context) => GlossaryImportDialog(glossaryId: selectedGlossary.id),
    );
  }

  void _showExportDialog() {
    final selectedGlossary = ref.read(selectedGlossaryProvider);
    if (selectedGlossary == null) return;

    showDialog(
      context: context,
      builder: (context) => GlossaryExportDialog(glossaryId: selectedGlossary.id),
    );
  }

  Future<void> _confirmDeleteGlossary(Glossary glossary) async {
    final tokens = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Glossary'),
        content: Text(
          'Are you sure you want to delete "${glossary.name}"? '
          'This will permanently delete all ${glossary.entryCount} entries.',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(true),
            foregroundColor: tokens.err,
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ref.read(glossaryServiceProvider);
        await service.deleteGlossary(glossary.id);

        if (!mounted) return;
        final selected = ref.read(selectedGlossaryProvider);
        if (selected?.id == glossary.id) {
          ref.read(selectedGlossaryProvider.notifier).clear();
        }
        ref.invalidate(glossariesProvider);

        FluentToast.success(
          context,
          'Glossary "${glossary.name}" deleted successfully',
        );
      } catch (e) {
        if (!mounted) return;
        FluentToast.error(context, 'Error deleting glossary: $e');
      }
    }
  }
}
