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
import 'package:twmt/widgets/lists/list_search_field.dart';
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
/// `EditorStatusBar`. The `FilterToolbar` carries the project title, the
/// search field (key/source/target) and the STATUS filter pill group.
/// `EditorActionSidebar` hosts context controls and primary actions.
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

  /// Ctrl+A handler: toggle selection over every row currently visible in
  /// the DataGrid (after filters + search apply).
  ///
  /// - No selection → select every filtered row.
  /// - Partial selection → expand to every filtered row.
  /// - Every filtered row already selected → clear — giving Ctrl+A a familiar
  ///   toggle feel.
  ///
  /// The focus-aware guard in [_SelectAllRowsAction.consumesKey] lets native
  /// Ctrl+A "select all text" keep working when a TextField (search, inline
  /// editor) is focused.
  void _selectAllFilteredRows() {
    final rowsAsync = ref.read(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final rows = rowsAsync.asData?.value ?? const <TranslationRow>[];
    if (rows.isEmpty) return;

    final filteredIds = rows.map((r) => r.id).toList();
    final selection = ref.read(editorSelectionProvider);
    final allFilteredSelected = filteredIds
        .every((id) => selection.selectedUnitIds.contains(id));

    final notifier = ref.read(editorSelectionProvider.notifier);
    if (allFilteredSelected) {
      notifier.clearSelection();
    } else {
      notifier.selectAll(filteredIds);
    }
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
      // Ctrl+T mirrors the sidebar's smart button: translate the current grid
      // selection when one exists, otherwise translate every row.
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyT):
          const _TranslateIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyV): const _ValidateIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
          const _SelectAllRowsIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
        onInvoke: (_) {
          _searchFocus.requestFocus();
          return null;
        },
      ),
      _TranslateIntent: CallbackAction<_TranslateIntent>(
        onInvoke: (_) {
          final hasSelection =
              ref.read(editorSelectionProvider).hasSelection;
          if (hasSelection) {
            _getActions().handleTranslateSelected();
          } else {
            _getActions().handleTranslateAll();
          }
          return null;
        },
      ),
      _ValidateIntent: CallbackAction<_ValidateIntent>(
        onInvoke: (_) {
          _getActions().handleValidate();
          return null;
        },
      ),
      _SelectAllRowsIntent: _SelectAllRowsAction(_selectAllFilteredRows),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        // Autofocus anchor so the Shortcuts map is live the moment the screen
        // mounts. Without it, `Shortcuts` only fires after the user clicks a
        // focusable child (e.g. a grid row), which made Ctrl+A silently
        // no-op on first landing. `skipTraversal: true` keeps this node out
        // of Tab focus traversal.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
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
                ),
                trailing: [
                  ListSearchField(
                    value: filter.searchQuery,
                    focusNode: _searchFocus,
                    hintText: 'Search key · source · target',
                    onChanged: (value) => ref
                        .read(editorFilterProvider.notifier)
                        .setSearchQuery(value),
                    onClear: () => ref
                        .read(editorFilterProvider.notifier)
                        .setSearchQuery(''),
                  ),
                ],
                pillGroups: [
                  _buildStatusGroup(filter, stats),
                ],
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EditorActionSidebar(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
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

}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// Ctrl+T intent. Routes to `handleTranslateSelected` when the grid has any
/// rows selected, otherwise falls through to `handleTranslateAll` — matching
/// the sidebar's smart Translate button.
class _TranslateIntent extends Intent {
  const _TranslateIntent();
}

class _ValidateIntent extends Intent {
  const _ValidateIntent();
}

class _SelectAllRowsIntent extends Intent {
  const _SelectAllRowsIntent();
}

/// Action for [_SelectAllRowsIntent] that declines the key event when focus
/// sits inside an [EditableText]. Returning `false` from [consumesKey] makes
/// the enclosing `Shortcuts` widget report `KeyEventResult.ignored`, so the
/// native Ctrl+A "select all text" behaviour keeps working while the user is
/// typing in the search field or an inline cell editor.
class _SelectAllRowsAction extends Action<_SelectAllRowsIntent> {
  _SelectAllRowsAction(this._onInvoke);

  final VoidCallback _onInvoke;

  static bool _focusIsInTextInput() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool consumesKey(_SelectAllRowsIntent intent) => !_focusIsInTextInput();

  @override
  Object? invoke(_SelectAllRowsIntent intent) {
    if (_focusIsInTextInput()) return null;
    _onInvoke();
    return null;
  }
}
