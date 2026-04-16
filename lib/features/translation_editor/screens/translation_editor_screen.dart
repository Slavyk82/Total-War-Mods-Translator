import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/editor_providers.dart';
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_intents.dart';
import '../widgets/editor_top_bar.dart';
import '../widgets/editor_filter_panel.dart';
import '../widgets/editor_datagrid.dart';
import '../widgets/editor_inspector_panel.dart';
import '../widgets/editor_status_bar.dart';
import 'translation_editor_actions.dart';

/// Translation editor screen.
///
/// Main editing interface for translating mod content.
/// Three-panel layout: filter sidebar, Syncfusion DataGrid, inspector (Task 5).
///
/// Screen responsibilities:
/// - Layout and navigation structure (top bar replaces the old FluentHeader).
/// - Coordinate between top bar, filter panel, datagrid and status bar.
/// - Handle high-level translation workflow coordination.
/// - Own the screen-scoped keyboard shortcuts (Ctrl+F focus search,
///   Ctrl+T translate selected, Ctrl+Shift+T translate all,
///   Ctrl+Shift+V validate) so they fire from any focus context, not just
///   when the top bar holds focus.
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

  /// Owned by the screen so the screen-level [FocusSearchIntent] can target
  /// it (and so the top bar doesn't need to expose a static handle).
  final FocusNode _searchFocus = FocusNode(debugLabel: 'editor-search');

  @override
  void initState() {
    super.initState();
    // Reset skipTranslationMemory to false when entering the editor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(translationSettingsProvider.notifier).setSkipTranslationMemory(false);
      // Clear mod update impact flag - user has reviewed the project
      _clearModUpdateImpact();
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  /// Clear the mod update impact flag when user opens the editor.
  /// This indicates the user has acknowledged the mod update.
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
    return Material(
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyF, control: true):
              FocusSearchIntent(),
          SingleActivator(LogicalKeyboardKey.keyT, control: true):
              TranslateSelectedIntent(),
          SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true):
              TranslateAllIntent(),
          SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
              ValidateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            FocusSearchIntent: CallbackAction<FocusSearchIntent>(
              onInvoke: (_) {
                _searchFocus.requestFocus();
                return null;
              },
            ),
            TranslateSelectedIntent: CallbackAction<TranslateSelectedIntent>(
              onInvoke: (_) {
                // Selection guard lives at screen scope so the top bar stays
                // a dumb view of the action callbacks.
                final hasSelection =
                    ref.read(editorSelectionProvider).hasSelection;
                if (hasSelection) {
                  _getActions().handleTranslateSelected();
                }
                return null;
              },
            ),
            TranslateAllIntent: CallbackAction<TranslateAllIntent>(
              onInvoke: (_) {
                _getActions().handleTranslateAll();
                return null;
              },
            ),
            ValidateIntent: CallbackAction<ValidateIntent>(
              onInvoke: (_) {
                _getActions().handleValidate();
                return null;
              },
            ),
          },
          child: Column(
            children: [
              EditorTopBar(
                projectId: widget.projectId,
                languageId: widget.languageId,
                searchFocus: _searchFocus,
                onTranslationSettings: () => _getActions().handleTranslationSettings(),
                onTranslateAll: () => _getActions().handleTranslateAll(),
                onTranslateSelected: () => _getActions().handleTranslateSelected(),
                onValidate: () => _getActions().handleValidate(),
                onRescanValidation: () => _getActions().handleRescanValidation(),
                onExport: () => _getActions().handleExport(),
                onImportPack: () => _getActions().handleImportPack(),
              ),

              // Main content area
              Expanded(
                child: Row(
                  children: [
                    // Left filter panel
                    EditorFilterPanel(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                    ),

                    // Main DataGrid area
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

                    // Right inspector panel (320px) — selection details +
                    // Source/Target editor + TM suggestions + Validation.
                    EditorInspectorPanel(
                      projectId: widget.projectId,
                      languageId: widget.languageId,
                      onSave: (unitId, text) =>
                        _getActions().handleCellEdit(unitId, text),
                      onApplySuggestion: (unitId, text) =>
                        _getActions().handleCellEdit(unitId, text),
                    ),
                  ],
                ),
              ),

              // Bottom statusbar with live editor metrics.
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
}
