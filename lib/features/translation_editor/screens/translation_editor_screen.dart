import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/service_locator.dart';
import '../providers/editor_providers.dart';
import '../providers/translation_settings_provider.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/editor_sidebar.dart';
import '../widgets/editor_datagrid.dart';
import 'translation_editor_actions.dart';

/// Translation editor screen
///
/// Main editing interface for translating mod content
/// Complex 3-panel layout with Syncfusion DataGrid
///
/// Screen responsibilities:
/// - Layout and navigation structure
/// - Coordinate between toolbar, sidebar, datagrid, and bottom panel
/// - Handle high-level translation workflow coordination
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
    final projectRepo = ServiceLocator.get<ProjectRepository>();
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
    final subtitle = projectName.isNotEmpty && languageName.isNotEmpty
        ? ' — $languageName — $projectName'
        : '';

    return FluentScaffold(
      header: FluentHeader(
        title: 'Translation Editor$subtitle',
        leading: FluentIconButton(
          icon: FluentIcons.arrow_left_24_regular,
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        actions: const [],
      ),
      body: Column(
        children: [
          // Top toolbar
          EditorToolbar(
            projectId: widget.projectId,
            languageId: widget.languageId,
            onTranslationSettings: () => _getActions().handleTranslationSettings(),
            onTranslateAll: () => _getActions().handleTranslateAll(),
            onTranslateSelected: () => _getActions().handleTranslateSelected(),
            onValidate: () => _getActions().handleValidate(),
            onExport: () => _getActions().handleExport(),
            onImportPack: () => _getActions().handleImportPack(),
          ),

          // Main content area
          Expanded(
            child: Row(
              children: [
                // Left sidebar
                EditorSidebar(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
