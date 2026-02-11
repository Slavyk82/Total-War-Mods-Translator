import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/app_router.dart';
import '../widgets/provider_setup_dialog.dart';
import 'actions/editor_actions_base.dart';
import 'actions/editor_actions_cell_edit.dart';
import 'actions/editor_actions_export.dart';
import 'actions/editor_actions_import.dart';
import 'actions/editor_actions_translation.dart';
import 'actions/editor_actions_undo_redo.dart';
import 'actions/editor_actions_validation.dart';

/// Translation editor business logic actions
///
/// Handles all business operations for the translation editor:
/// - Cell editing and TM suggestion application
/// - Translation workflow (translate all/selected)
/// - Validation orchestration
/// - Export operations
/// - Import operations
/// - Undo/redo management
/// - Batch creation and orchestration
class TranslationEditorActions
    with
        EditorActionsBase,
        EditorActionsCellEdit,
        EditorActionsTranslation,
        EditorActionsBatch,
        EditorActionsValidation,
        EditorActionsExport,
        EditorActionsImport,
        EditorActionsUndoRedo {
  TranslationEditorActions({
    required this.ref,
    required this.context,
    required this.projectId,
    required this.languageId,
  });

  @override
  final WidgetRef ref;

  @override
  final BuildContext context;

  @override
  final String projectId;

  @override
  final String languageId;

  @override
  void showProviderSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => ProviderSetupDialog(
        onGoToSettings: () => context.go(AppRoutes.settings),
      ),
    );
  }

  @override
  Future<void> createAndStartBatch(List<String> unitIds, {bool forceSkipTM = false}) async {
    await createAndStartBatchImpl(unitIds, forceSkipTM: forceSkipTM);
  }
}
