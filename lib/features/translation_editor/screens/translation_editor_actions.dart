import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/app_router.dart';
import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../providers/editor_row_models.dart';
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

  /// Clears the selected `needsReview` rows and immediately retranslates
  /// them with TM lookup disabled. The review flag exists precisely because
  /// the prior translation is suspect, so an exact TM match would just hand
  /// us back the same suspect text — defeating the user's intent.
  ///
  /// If the clear step fails, the LLM is NOT called: we'd be retranslating
  /// rows whose review state never actually transitioned in the database.
  Future<void> handleBulkRetranslateNeedsReview(
      List<TranslationRow> rows) async {
    if (rows.isEmpty) return;

    final versionRepo =
        ref.read(shared_repo.translationVersionRepositoryProvider);
    final versionIds = rows.map((r) => r.version.id).toSet().toList();

    final clearResult = await versionRepo.rejectBatch(versionIds);
    if (clearResult.isErr) {
      ref.read(loggingServiceProvider).error(
        'Failed to clear translations before retranslate',
        {'count': versionIds.length, 'error': clearResult.error},
      );
      return;
    }

    refreshProviders();

    final unitIds = rows.map((r) => r.unit.id).toSet().toList();
    await createAndStartBatch(unitIds, forceSkipTM: true);
  }
}
