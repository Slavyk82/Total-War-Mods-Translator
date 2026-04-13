import 'package:flutter/material.dart';
import 'package:twmt/services/file/localization_parser_impl.dart';
import '../../../../providers/shared/logging_providers.dart';
import '../../../../providers/shared/repository_providers.dart' as shared_repo;
import '../../../../providers/shared/service_providers.dart' as shared_svc;
import '../../providers/editor_providers.dart';
import '../../services/pack_import_service.dart';
import '../../widgets/pack_import_dialog.dart';
import 'editor_actions_base.dart';

/// Mixin providing import operations for the translation editor
mixin EditorActionsImport on EditorActionsBase {
  /// Handle import from pack file
  void handleImportPack() {
    // Create the import service
    final importService = PackImportService(
      rpfmService: ref.read(shared_svc.rpfmServiceProvider),
      localizationParser: LocalizationParserImpl(),
      unitRepository: ref.read(shared_repo.translationUnitRepositoryProvider),
      versionRepository: ref.read(shared_repo.translationVersionRepositoryProvider),
      projectLanguageRepository: ref.read(shared_repo.projectLanguageRepositoryProvider),
      logger: ref.read(loggingServiceProvider),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PackImportDialog(
        projectId: projectId,
        languageId: languageId,
        importService: importService,
        onImportComplete: () {
          // Refresh all providers after import (translation rows, stats, project details, etc.)
          refreshProviders();
          // Also invalidate editor stats which is not in refreshProviders
          ref.invalidate(editorStatsProvider(projectId, languageId));
        },
      ),
    );
  }
}
