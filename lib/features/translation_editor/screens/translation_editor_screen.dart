import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_action_sidebar.dart';
import '../widgets/editor_datagrid.dart';
import '../widgets/editor_inspector_panel.dart';
import '../widgets/editor_language_switcher.dart';
import '../widgets/editor_status_bar.dart';
import '../widgets/validation_edit_dialog.dart';
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
    final statsAsync = ref.watch(
      editorStatsProvider(widget.projectId, widget.languageId),
    );
    final filter = ref.watch(editorFilterProvider);
    final severityCountsAsync = ref.watch(
      visibleSeverityCountsProvider(widget.projectId, widget.languageId),
    );
    final severityCounts =
        severityCountsAsync.asData?.value ?? (errors: 0, warnings: 0);
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';

    final stats = statsAsync.asData?.value;

    // Pre-compute selected rows for the inspector's multi-select bulk
    // actions. Accept operates only on `needsReview` rows (accepting already-
    // translated rows is a no-op, accepting a pending row would mark it
    // translated with no text). Retranslate operates on every selected row —
    // `rejectBatch` clears `translatedText` and resets `status = pending` for
    // any row id, so applying it to already-empty rows is a safe no-op.
    final rowsAsync = ref.watch(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final visibleRows = rowsAsync.asData?.value ?? const <TranslationRow>[];
    final selection = ref.watch(editorSelectionProvider);
    final allSelectedRows = visibleRows
        .where((r) => selection.selectedUnitIds.contains(r.id))
        .toList();
    final selectedNeedsReviewRows = allSelectedRows
        .where((r) => r.status == TranslationVersionStatus.needsReview)
        .toList();

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
                  CrumbSegment(projectName),
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
                  trailing: [
                    EditorLanguageSwitcher(
                      projectId: widget.projectId,
                      currentLanguageId: widget.languageId,
                    ),
                  ],
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
                  if (filter.statusFilters
                      .contains(TranslationVersionStatus.needsReview))
                    _buildSeverityGroup(filter, severityCounts),
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
                      onAcceptIssue: (issue) =>
                          _getActions().handleAcceptTranslation(issue),
                      onRejectIssue: (issue) =>
                          _getActions().handleRejectTranslation(issue),
                      onEditIssue: (issue) async {
                        final newText = await showDialog<String>(
                          context: context,
                          builder: (_) => ValidationEditDialog(issue: issue),
                        );
                        if (newText != null) {
                          await _getActions()
                              .handleEditTranslation(issue, newText);
                        }
                      },
                      onBulkAccept: selectedNeedsReviewRows.isEmpty
                          ? null
                          : () async {
                              await _getActions()
                                  .handleBulkAcceptTranslation(
                                      selectedNeedsReviewRows);
                            },
                      // Gated by the presence of any `needsReview` row but
                      // rejects the full selection — the reject handler wipes
                      // every selected translation once the user confirms.
                      onBulkRetranslate: selectedNeedsReviewRows.isEmpty
                          ? null
                          : () async {
                              await _getActions()
                                  .handleBulkRejectTranslation(
                                      allSelectedRows);
                            },
                      onBulkDeselect: selection.selectedCount == 0
                          ? null
                          : () => ref
                              .read(editorSelectionProvider.notifier)
                              .clearSelection(),
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

  FilterPillGroup _buildSeverityGroup(
    EditorFilterState filter,
    ({int errors, int warnings}) counts,
  ) {
    FilterPill pill(
      String label,
      ValidationSeverity severity,
      int count,
    ) {
      final active = filter.severityFilters.contains(severity);
      return FilterPill(
        label: label,
        selected: active,
        count: count,
        onToggle: () {
          final updated =
              Set<ValidationSeverity>.from(filter.severityFilters);
          if (active) {
            updated.remove(severity);
          } else {
            updated.add(severity);
          }
          ref
              .read(editorFilterProvider.notifier)
              .setSeverityFilters(updated);
        },
      );
    }

    return FilterPillGroup(
      label: 'SEVERITY',
      clearLabel: 'Clear',
      onClear: () => ref
          .read(editorFilterProvider.notifier)
          .setSeverityFilters(const {}),
      pills: [
        pill('Errors', ValidationSeverity.error, counts.errors),
        pill('Warnings', ValidationSeverity.warning, counts.warnings),
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
