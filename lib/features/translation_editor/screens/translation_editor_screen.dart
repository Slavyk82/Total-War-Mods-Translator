import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../providers/editor_providers.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/editor_sidebar.dart';
import '../widgets/editor_datagrid.dart';
import '../widgets/editor_bottom_panel.dart';
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
  double _bottomPanelHeight = 250;
  String? _selectedUnitId;
  bool _isBottomPanelVisible = true;

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
    final undoRedoManager = ref.watch(undoRedoManagerProvider);

    return FluentScaffold(
      header: FluentHeader(
        title: 'Translation Editor',
        leading: FluentIconButton(
          icon: FluentIcons.arrow_left_24_regular,
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        actions: [
          // Toggle bottom panel
          FluentIconButton(
            icon: _isBottomPanelVisible
                ? FluentIcons.text_description_24_regular
                : FluentIcons.text_description_24_filled,
            tooltip: _isBottomPanelVisible
              ? 'Hide bottom panel'
              : 'Show bottom panel',
            onPressed: () {
              setState(() {
                _isBottomPanelVisible = !_isBottomPanelVisible;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top toolbar
          EditorToolbar(
            projectId: widget.projectId,
            languageId: widget.languageId,
            onTranslateAll: () => _getActions().handleTranslateAll(),
            onTranslateSelected: () => _getActions().handleTranslateSelected(),
            onValidate: () => _getActions().handleValidate(),
            onExport: () => _getActions().handleExport(),
            onUndo: () => _getActions().handleUndo(),
            onRedo: () => _getActions().handleRedo(),
            canUndo: undoRedoManager.canUndo,
            canRedo: undoRedoManager.canRedo,
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Calculate max bottom panel height (60% of viewport)
                      final maxBottomPanelHeight = constraints.maxHeight * 0.6;
                      final clampedBottomPanelHeight = _bottomPanelHeight.clamp(
                        150.0,
                        maxBottomPanelHeight,
                      );

                      return Column(
                        children: [
                          // DataGrid
                          Expanded(
                            child: EditorDataGrid(
                              projectId: widget.projectId,
                              languageId: widget.languageId,
                              onCellEdit: (unitId, newText) =>
                                _getActions().handleCellEdit(unitId, newText),
                              onRowDoubleTap: (unitId) {
                                setState(() {
                                  _selectedUnitId = unitId;
                                });
                              },
                            ),
                          ),

                          // Bottom panel (resizable)
                          if (_isBottomPanelVisible)
                            Column(
                              children: [
                                // Resize handle
                                MouseRegion(
                                  cursor: SystemMouseCursors.resizeUpDown,
                                  child: GestureDetector(
                                    onVerticalDragUpdate: (details) {
                                      setState(() {
                                        _bottomPanelHeight -= details.delta.dy;
                                        // Clamp between 150 and 60% of viewport
                                        _bottomPanelHeight = _bottomPanelHeight
                                          .clamp(150.0, maxBottomPanelHeight);
                                      });
                                    },
                                    child: Container(
                                      height: 4,
                                      color: Theme.of(context).dividerColor,
                                      child: Center(
                                        child: Container(
                                          width: 40,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Bottom panel content
                                SizedBox(
                                  height: clampedBottomPanelHeight,
                                  child: EditorBottomPanel(
                                    selectedUnitId: _selectedUnitId,
                                    sourceLanguageCode: 'en',
                                    targetLanguageCode: 'en',
                                    onApplySuggestion: (unitId, targetText) =>
                                      _getActions().handleApplySuggestion(unitId, targetText),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      );
                    },
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
