import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/glossary_providers.dart';
import '../widgets/glossary_list.dart';
import '../widgets/glossary_datagrid.dart';
import '../widgets/glossary_statistics_panel.dart';
import '../widgets/glossary_entry_editor.dart';
import '../widgets/glossary_import_dialog.dart';
import '../widgets/glossary_export_dialog.dart';
import '../widgets/glossary_new_dialog.dart';
import '../widgets/glossary_screen_components.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/models/domain/game_installation.dart';

/// Main screen for Glossary management.
class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  final _searchController = TextEditingController();
  Map<String, GameInstallation> _gameInstallations = {};

  @override
  void initState() {
    super.initState();
    _loadGameInstallations();
  }

  Future<void> _loadGameInstallations() async {
    final repository = ServiceLocator.get<GameInstallationRepository>();
    final result = await repository.getAll();
    result.when(
      ok: (games) {
        if (mounted) {
          setState(() {
            _gameInstallations = {for (var g in games) g.id: g};
          });
        }
      },
      err: (_) {},
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedGlossary = ref.watch(selectedGlossaryProvider);

    return FluentScaffold(
      body: selectedGlossary == null
          ? _buildGlossaryListView(context)
          : _buildGlossaryEditorView(context, selectedGlossary),
    );
  }

  Widget _buildGlossaryListView(BuildContext context) {
    final glossariesAsync = ref.watch(glossariesProvider());

    return Column(
      children: [
        GlossaryListHeader(onNewGlossary: _showNewGlossaryDialog),
        const Divider(height: 1),
        Expanded(
          child: glossariesAsync.when(
            data: (glossaries) {
              if (glossaries.isEmpty) {
                return GlossaryEmptyState(onNewGlossary: _showNewGlossaryDialog);
              }
              return GlossaryList(
                glossaries: glossaries,
                gameInstallations: _gameInstallations,
                onGlossaryTap: (glossary) {
                  ref.read(selectedGlossaryProvider.notifier).select(glossary);
                },
                onDeleteGlossary: (glossary) => _confirmDeleteGlossary(glossary),
              );
            },
            loading: () => const Center(child: FluentInlineSpinner()),
            error: (error, stack) => Center(
              child: Text(
                'Error loading glossaries: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ),
      ],
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
                      searchController: _searchController,
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

  void _showEntryEditor(dynamic entry, Glossary glossary) async {
    String? targetLanguageCode;
    if (glossary.targetLanguageId != null) {
      try {
        final languageRepo = ServiceLocator.get<LanguageRepository>();
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
            foregroundColor: Theme.of(context).colorScheme.error,
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ServiceLocator.get<IGlossaryService>();
        await service.deleteGlossary(glossary.id);

        if (mounted) {
          final selected = ref.read(selectedGlossaryProvider);
          if (selected?.id == glossary.id) {
            ref.read(selectedGlossaryProvider.notifier).clear();
          }
          ref.invalidate(glossariesProvider);

          FluentToast.success(
            context,
            'Glossary "${glossary.name}" deleted successfully',
          );
        }
      } catch (e) {
        if (mounted) {
          FluentToast.error(context, 'Error deleting glossary: $e');
        }
      }
    }
  }
}
