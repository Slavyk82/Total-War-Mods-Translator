import 'package:flutter/material.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/localization_parser_impl.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
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
      rpfmService: ServiceLocator.get<IRpfmService>(),
      localizationParser: LocalizationParserImpl(),
      unitRepository: ServiceLocator.get<TranslationUnitRepository>(),
      versionRepository: ServiceLocator.get<TranslationVersionRepository>(),
      projectLanguageRepository: ServiceLocator.get<ProjectLanguageRepository>(),
      logger: ServiceLocator.get<LoggingService>(),
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
