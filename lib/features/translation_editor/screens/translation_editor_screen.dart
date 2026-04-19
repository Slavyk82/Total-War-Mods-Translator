import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/workflow/next_step_cta.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_action_sidebar.dart';
import '../widgets/editor_datagrid.dart';
import '../widgets/editor_inspector_panel.dart';
import '../widgets/editor_status_bar.dart';
import 'translation_editor_actions.dart';

/// Translation editor screen.
///
/// Three-panel body (action sidebar · DataGrid · inspector) sandwiched between
/// a stacked header (`DetailScreenToolbar` + `FilterToolbar`) and
/// `EditorStatusBar`. The top-bar `EditorActionBar` was retired — all its
/// controls (search · model · skip-tm · rules · action buttons · settings)
/// now live in `EditorActionSidebar`. Filters became pills in `FilterToolbar`.
class TranslationEditorScreen extends ConsumerStatefulWidget {
  const TranslationEditorScreen({
    super.key,
    required this.projectId,
    required this.languageId,
  });

  final String projectId;
  final String languageId;

  @override
  ConsumerState<TranslationEditorScreen> createState() =>
      _TranslationEditorScreenState();
}

class _TranslationEditorScreenState
    extends ConsumerState<TranslationEditorScreen> {
  final FocusNode _searchFocus = FocusNode(debugLabel: 'editor-search');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(translationSettingsProvider.notifier)
          .setSkipTranslationMemory(false);
      _clearModUpdateImpact();
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _clearModUpdateImpact() async {
    final projectRepo = ref.read(shared_repo.projectRepositoryProvider);
    await projectRepo.clearModUpdateImpact(widget.projectId);
  }

  TranslationEditorActions _getActions() {
    return TranslationEditorActions(
      ref: ref,
      context: context,
      projectId: widget.projectId,
      languageId: widget.languageId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final statsAsync = ref.watch(
      editorStatsProvider(widget.projectId, widget.languageId),
    );
    final filter = ref.watch(editorFilterProvider);
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';

    final stats = statsAsync.asData?.value;
    final isFullyTranslated = stats != null &&
        stats.totalUnits > 0 &&
        stats.completionPercentage >= 100.0;

    final shortcuts = <ShortcutActivator, Intent>{
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
          const _FocusSearchIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyT):
          const _TranslateAllIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyT): const _TranslateSelectedIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyV): const _ValidateIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
        onInvoke: (_) {
          _searchFocus.requestFocus();
          return null;
        },
      ),
      _TranslateAllIntent: CallbackAction<_TranslateAllIntent>(
        onInvoke: (_) {
          _getActions().handleTranslateAll();
          return null;
        },
      ),
      _TranslateSelectedIntent: CallbackAction<_TranslateSelectedIntent>(
        onInvoke: (_) {
          _getActions().handleTranslateSelected();
          return null;
        },
      ),
      _ValidateIntent: CallbackAction<_ValidateIntent>(
        onInvoke: (_) {
          _getActions().handleValidate();
          return null;
        },
      ),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Material(
          color: context.tokens.bg,
          child: Column(
            children: [
              DetailScreenToolbar(
                crumbs: [
                  const CrumbSegment('Work'),
                  const CrumbSegment('Projects', route: AppRoutes.projects),
                  CrumbSegment(
                    projectName,
                    route: AppRoutes.projectDetail(widget.projectId),
                  ),
                  CrumbSegment(languageName),
                ],
                trailing: [
                  if (isFullyTranslated)
                    NextStepCta(
                      label: 'Compile this pack',
                      icon: FluentIcons.box_multiple_24_regular,
                      onTap: () => context.goPackCompilation(),
                    ),
                ],
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              FilterToolbar(
                leading: ListToolbarLeading(
                  icon: FluentIcons.folder_24_regular,
                  title: projectName,
                  countLabel: languageName,
                ),
                pillGroups: [
                  _buildStatusGroup(filter, stats),
                  _buildTmSourceGroup(filter),
                ],
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorActionSidebar(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                      searchFocusNode: _searchFocus,
                      onTranslationSettings: () =>
                          _getActions().handleTranslationSettings(),
                      onTranslateAll: () => _getActions().handleTranslateAll(),
                      onTranslateSelected: () =>
                          _getActions().handleTranslateSelected(),
                      onValidate: () => _getActions().handleValidate(),
                      onRescanValidation: () =>
                          _getActions().handleRescanValidation(),
                      onExport: () => _getActions().handleExport(),
                      onImportPack: () => _getActions().handleImportPack(),
                    ),
                    Expanded(
                      child: EditorDataGrid(
                        projectId: widget.projectId,
                        languageId: widget.languageId,
                        onCellEdit: (unitId, newText) =>
                            _getActions().handleCellEdit(unitId, newText),
                        onForceRetranslate: () =>
                            _getActions().handleForceRetranslateSelected(),
                      ),
                    ),
                    EditorInspectorPanel(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                      onSave: (unitId, text) =>
                          _getActions().handleCellEdit(unitId, text),
                    ),
                  ],
                ),
              ),
              EditorStatusBar(
                projectId: widget.projectId,
                languageId: widget.languageId,
              ),
            ],
          ),
        ),
      ),
    );
  }

  FilterPillGroup _buildStatusGroup(EditorFilterState filter, EditorStats? stats) {
    FilterPill pill(
      String label,
      TranslationVersionStatus status,
      int? count,
    ) {
      final active = filter.statusFilters.contains(status);
      return FilterPill(
        label: label,
        selected: active,
        count: count,
        onToggle: () {
          final updated =
              Set<TranslationVersionStatus>.from(filter.statusFilters);
          if (active) {
            updated.remove(status);
          } else {
            updated.add(status);
          }
          ref.read(editorFilterProvider.notifier).setStatusFilters(updated);
        },
      );
    }

    return FilterPillGroup(
      label: 'STATUS',
      clearLabel: 'Clear',
      onClear: () => ref
          .read(editorFilterProvider.notifier)
          .setStatusFilters(const {}),
      pills: [
        pill('Pending', TranslationVersionStatus.pending, stats?.pendingCount),
        pill('Translated', TranslationVersionStatus.translated,
            stats?.translatedCount),
        pill('Needs review', TranslationVersionStatus.needsReview,
            stats?.needsReviewCount),
      ],
    );
  }

  FilterPillGroup _buildTmSourceGroup(EditorFilterState filter) {
    FilterPill pill(String label, TmSourceType type) {
      final active = filter.tmSourceFilters.contains(type);
      return FilterPill(
        label: label,
        selected: active,
        onToggle: () {
          final updated = Set<TmSourceType>.from(filter.tmSourceFilters);
          if (active) {
            updated.remove(type);
          } else {
            updated.add(type);
          }
          ref.read(editorFilterProvider.notifier).setTmSourceFilters(updated);
        },
      );
    }

    return FilterPillGroup(
      label: 'TM SOURCE',
      clearLabel: 'Clear',
      onClear: () => ref
          .read(editorFilterProvider.notifier)
          .setTmSourceFilters(const {}),
      pills: [
        pill('Exact match', TmSourceType.exactMatch),
        pill('Fuzzy match', TmSourceType.fuzzyMatch),
        pill('LLM', TmSourceType.llm),
        pill('Manual', TmSourceType.manual),
        pill('None', TmSourceType.none),
      ],
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _TranslateAllIntent extends Intent {
  const _TranslateAllIntent();
}

class _TranslateSelectedIntent extends Intent {
  const _TranslateSelectedIntent();
}

class _ValidateIntent extends Intent {
  const _ValidateIntent();
}
