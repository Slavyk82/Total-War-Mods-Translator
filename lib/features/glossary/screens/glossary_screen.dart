import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/utils/string_initials.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
import 'package:twmt/widgets/detail/detail_cover.dart';
import 'package:twmt/widgets/detail/detail_meta_banner.dart';
import 'package:twmt/widgets/detail/detail_overview_layout.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/detail/stats_rail.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/relative_date.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

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
                fontStyle: tokens.fontDisplayStyle,
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

  Widget _buildGlossaryEditorView(BuildContext context, Glossary glossary) {
    final tokens = context.tokens;
    final statsAsync = ref.watch(glossaryStatisticsProvider(glossary.id));
    final now = ref.watch(clockProvider)();
    final gameName = _gameInstallations[glossary.gameInstallationId]?.gameName ??
        (glossary.isGlobal ? 'Universal' : (glossary.gameInstallationId ?? '—'));
    final relative = formatRelativeSince(
      DateTime.fromMillisecondsSinceEpoch(glossary.updatedAt),
      now: now,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailScreenToolbar(
          crumbs: [
            const CrumbSegment('Resources'),
            const CrumbSegment('Glossary', route: AppRoutes.glossary),
            CrumbSegment(glossary.name),
          ],
          onBack: () =>
              ref.read(selectedGlossaryProvider.notifier).clear(),
        ),
        DetailMetaBanner(
          cover: DetailCover(
            imageUrl: null,
            monogramFallback: initials(glossary.name),
          ),
          title: glossary.name,
          subtitle: [
            Text(gameName),
            if (glossary.targetLanguageId != null)
              Text('target: ${glossary.targetLanguageId!.toUpperCase()}'),
            statsAsync.maybeWhen(
              data: (s) => Text('${s.totalEntries} entries'),
              orElse: () => const Text('— entries'),
            ),
            if (relative != null) Text('updated $relative'),
          ],
          description: glossary.description,
          actions: [
            SmallTextButton(
              label: '+ Entry',
              icon: FluentIcons.add_24_regular,
              onTap: () => _showEntryEditor(null, glossary),
            ),
            SmallTextButton(
              label: 'Import',
              icon: FluentIcons.arrow_import_24_regular,
              onTap: _showImportDialog,
            ),
            SmallTextButton(
              label: 'Export',
              icon: FluentIcons.arrow_export_24_regular,
              onTap: _showExportDialog,
            ),
            SmallIconButton(
              icon: FluentIcons.delete_24_regular,
              tooltip: 'Delete glossary',
              onTap: () => _confirmDeleteGlossary(glossary),
              foreground: tokens.err,
              background: tokens.errBg,
              borderColor: tokens.err.withValues(alpha: 0.3),
            ),
          ],
        ),
        Expanded(
          child: DetailOverviewLayout(
            main: Container(
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
                    child: ListSearchField(
                      value: _entrySearchController.text,
                      hintText: 'Search entries...',
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
                  Container(height: 1, color: tokens.border),
                  Expanded(
                    child: GlossaryDataGrid(glossaryId: glossary.id),
                  ),
                ],
              ),
            ),
            rail: statsAsync.when(
              data: (s) => _GlossaryStatsRail(stats: s),
              loading: () => const Center(child: FluentInlineSpinner()),
              error: (err, _) => Text(
                'Stats error: $err',
                style: tokens.fontBody.copyWith(color: tokens.err),
              ),
            ),
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

/// Right-column stats rail for the Glossary detail view. Mirrors the
/// Project detail `_ProjectStatsRail` structure: Overview / Usage / Quality.
class _GlossaryStatsRail extends StatelessWidget {
  final GlossaryStatistics stats;
  const _GlossaryStatsRail({required this.stats});

  @override
  Widget build(BuildContext context) {
    return StatsRail(
      sections: [
        StatsRailSection(
          label: 'Overview',
          rows: [
            StatsRailRow(
              label: 'Total entries',
              value: stats.totalEntries.toString(),
            ),
          ],
        ),
        StatsRailSection(
          label: 'Usage',
          rows: [
            StatsRailRow(
              label: 'Used in translations',
              value: stats.usedInTranslations.toString(),
              semantics: StatsSemantics.ok,
            ),
            StatsRailRow(
              label: 'Unused',
              value: stats.unusedEntries.toString(),
            ),
            StatsRailRow(
              label: 'Usage rate',
              value: '${(stats.usageRate * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
        StatsRailSection(
          label: 'Quality',
          rows: [
            StatsRailRow(
              label: 'Duplicates',
              value: stats.duplicatesDetected.toString(),
              semantics: stats.duplicatesDetected > 0
                  ? StatsSemantics.warn
                  : StatsSemantics.neutral,
            ),
            StatsRailRow(
              label: 'Missing translations',
              value: stats.missingTranslations.toString(),
              semantics: stats.missingTranslations > 0
                  ? StatsSemantics.warn
                  : StatsSemantics.neutral,
            ),
          ],
        ),
      ],
      hint: _computeHint(stats),
    );
  }

  StatsRailHint? _computeHint(GlossaryStatistics stats) {
    if (stats.missingTranslations > 0) {
      return StatsRailHint(
        kicker: 'NEXT',
        message: '${stats.missingTranslations} entries to complete',
        semantics: StatsSemantics.warn,
      );
    }
    if (stats.duplicatesDetected > 0) {
      return StatsRailHint(
        kicker: 'NEXT',
        message: '${stats.duplicatesDetected} duplicates to review',
        semantics: StatsSemantics.warn,
      );
    }
    return null;
  }
}
