import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_action_bar.dart';
import '../widgets/editor_filter_panel.dart';
import '../widgets/editor_datagrid.dart';
import '../widgets/editor_inspector_panel.dart';
import '../widgets/editor_status_bar.dart';
import 'translation_editor_actions.dart';

/// Translation editor screen.
///
/// Main editing interface for translating mod content. Three-panel body
/// (filter sidebar, read-only Syncfusion DataGrid, inspector) sandwiched
/// between a stacked header (`DetailScreenToolbar` + `EditorActionBar`)
/// and `EditorStatusBar`.
///
/// Screen responsibilities:
/// - Layout and navigation structure (back button + crumb via DetailScreenToolbar).
/// - Coordinate between the two header bars, filter panel, datagrid, inspector
///   and status bar.
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
    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';

    return Material(
      color: context.tokens.bg,
      child: Column(
        children: [
          DetailScreenToolbar(
            crumb: 'Work › Projects › $projectName › $languageName',
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          EditorActionBar(
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

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EditorFilterPanel(
                  projectId: widget.projectId,
                  languageId: widget.languageId,
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
                  onApplySuggestion: (unitId, text) =>
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
    );
  }
}
