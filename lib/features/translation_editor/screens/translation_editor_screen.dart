import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/translation_settings_provider.dart';
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
      color: context.tokens.bg,
      child: Column(
        children: [
          EditorTopBar(
            projectId: widget.projectId,
            languageId: widget.languageId,
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
              // Stretch all three columns to the full Row height so the
              // filter panel (sized to content via SingleChildScrollView)
              // does not get vertically centered inside the available
              // space and instead aligns its content to the top edge.
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
    );
  }
}
