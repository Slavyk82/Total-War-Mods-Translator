import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../models/import_conflict.dart';
import '../models/import_export_settings.dart';
import '../models/import_preview.dart';
import 'utils/import_file_integrity.dart';
import 'utils/import_file_reader.dart';

/// Service responsible for detecting conflicts during import
class ImportConflictDetector {
  final ImportFileReader _fileReader;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _projectLanguageRepository;

  const ImportConflictDetector(
    this._fileReader,
    this._unitRepository,
    this._versionRepository,
    this._projectLanguageRepository,
  );

  /// Detect conflicts between import data and existing translations
  Future<Result<List<ImportConflict>, ServiceException>> detectConflicts(
    ImportPreview preview,
    ImportSettings settings,
  ) async {
    try {
      final conflicts = <ImportConflict>[];

      // Integrity guard: this stage re-reads the file from disk. If the
      // content no longer matches what the preview showed, conflicts computed
      // here would describe data the user never reviewed.
      if (preview.contentHash != null) {
        final currentHash =
            await ImportFileIntegrity.computeContentHash(preview.filePath);
        if (currentHash != preview.contentHash) {
          return Err(
            ServiceException(
              'Import file changed on disk since preview; '
              'please re-open the import dialog and preview the file again.',
            ),
          );
        }
      }

      final fileDataResult = await _fileReader.readFile(
        preview.filePath,
        settings,
      );

      if (fileDataResult.isErr) {
        return Err(fileDataResult.error);
      }

      final rows = fileDataResult.value.rows;

      final keyColumn = _findColumn(settings.columnMapping, ImportColumn.key);
      if (keyColumn.isEmpty) {
        return Ok(conflicts);
      }

      final sourceColumn = _findColumn(
        settings.columnMapping,
        ImportColumn.sourceText,
      );
      final targetColumn = _findColumn(
        settings.columnMapping,
        ImportColumn.targetText,
      );

      // Resolve the target language's project_languages row id so conflicts
      // are compared against the SAME language being imported (not an
      // arbitrary sibling language returned by getByUnit(...).first).
      // findByProjectAndLanguage distinguishes "not in project" (Ok(null))
      // from a real DB failure (Err): a real failure must fail detection,
      // since silently reporting "no conflict" would let the import
      // overwrite data unchecked.
      final projectLanguageResult =
          await _projectLanguageRepository.findByProjectAndLanguage(
        settings.projectId,
        settings.targetLanguageId,
      );
      if (projectLanguageResult.isErr) {
        return Err(projectLanguageResult.error);
      }
      final projectLanguage = projectLanguageResult.value;
      if (projectLanguage == null) {
        // Target language is not part of the project yet: nothing to conflict
        // with (every imported row will create a fresh version).
        return Ok(conflicts);
      }
      final projectLanguageId = projectLanguage.id;

      for (final row in rows) {
        final key = row[keyColumn];
        if (key == null || key.isEmpty) continue;

        final conflictResult = await _checkRowForConflict(
          key: key,
          row: row,
          sourceColumn: sourceColumn,
          targetColumn: targetColumn,
          projectId: settings.projectId,
          projectLanguageId: projectLanguageId,
        );

        // A real DB failure must fail detection: silently reporting
        // "no conflict" would let the import overwrite data unchecked.
        if (conflictResult.isErr) {
          return Err(conflictResult.error);
        }

        final conflict = conflictResult.value;
        if (conflict != null) {
          conflicts.add(conflict);
        }
      }

      return Ok(conflicts);
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Failed to detect conflicts: $e', stackTrace: stackTrace),
      );
    }
  }

  /// Check a single row for conflicts with existing data.
  ///
  /// Returns Ok(null) when the row genuinely cannot conflict (unknown key or
  /// no version for the target language yet) and Err when a repository
  /// lookup fails for real — the caller must surface that failure instead of
  /// treating it as "no conflict".
  Future<Result<ImportConflict?, ServiceException>> _checkRowForConflict({
    required String key,
    required Map<String, String> row,
    required String sourceColumn,
    required String targetColumn,
    required String projectId,
    required String projectLanguageId,
  }) async {
    // findByKey distinguishes "not found" (Ok(null)) from a real DB error
    // (Err). Only a genuinely missing unit means "no conflict".
    final unitResult = await _unitRepository.findByKey(projectId, key);
    if (unitResult.isErr) {
      return Err(unitResult.error);
    }

    final unit = unitResult.value;
    if (unit == null) {
      return const Ok(null);
    }

    // Compare against the version for the SAME target language only.
    // findByUnitAndProjectLanguage returns Ok(null) when no version exists
    // yet (no conflict) and Err only on a real DB failure.
    final versionResult = await _versionRepository.findByUnitAndProjectLanguage(
      unitId: unit.id,
      projectLanguageId: projectLanguageId,
    );
    if (versionResult.isErr) {
      return Err(versionResult.error);
    }

    final version = versionResult.value;
    if (version == null) {
      return const Ok(null);
    }

    final importedSourceText = sourceColumn.isNotEmpty ? row[sourceColumn] : null;
    final importedTargetText = targetColumn.isNotEmpty ? row[targetColumn] : null;

    final sourceTextDiffers = importedSourceText != null &&
        importedSourceText != unit.sourceText;

    return Ok(ImportConflict(
      key: key,
      existingData: ConflictTranslation(
        sourceText: unit.sourceText,
        translatedText: version.translatedText,
        status: version.status.name,
        updatedAt: version.updatedAt,
        changedBy: version.isManuallyEdited ? 'User' : 'LLM',
      ),
      importedData: ConflictTranslation(
        sourceText: importedSourceText,
        translatedText: importedTargetText,
      ),
      sourceTextDiffers: sourceTextDiffers,
    ));
  }

  /// Find column name for a specific import column type
  String _findColumn(
    Map<String, ImportColumn> mapping,
    ImportColumn columnType,
  ) {
    return mapping.entries
        .firstWhere(
          (e) => e.value == columnType,
          orElse: () => const MapEntry('', ImportColumn.skip),
        )
        .key;
  }
}
