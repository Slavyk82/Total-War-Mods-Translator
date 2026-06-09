import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../models/import_conflict.dart';
import '../models/import_export_settings.dart';
import '../models/import_preview.dart';
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
      final projectLanguageResult =
          await _projectLanguageRepository.getByProjectAndLanguage(
        settings.projectId,
        settings.targetLanguageId,
      );
      if (projectLanguageResult.isErr) {
        // Target language is not part of the project yet: nothing to conflict
        // with (every imported row will create a fresh version).
        return Ok(conflicts);
      }
      final projectLanguageId = projectLanguageResult.value.id;

      for (final row in rows) {
        final key = row[keyColumn];
        if (key == null || key.isEmpty) continue;

        final conflict = await _checkRowForConflict(
          key: key,
          row: row,
          sourceColumn: sourceColumn,
          targetColumn: targetColumn,
          projectId: settings.projectId,
          projectLanguageId: projectLanguageId,
        );

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

  /// Check a single row for conflicts with existing data
  Future<ImportConflict?> _checkRowForConflict({
    required String key,
    required Map<String, String> row,
    required String sourceColumn,
    required String targetColumn,
    required String projectId,
    required String projectLanguageId,
  }) async {
    try {
      final unitResult = await _unitRepository.findByKey(projectId, key);

      // A real DB error or a genuinely missing unit both mean "no conflict to
      // report for this row"; only a found unit can conflict.
      if (unitResult.isErr) {
        return null;
      }

      final unit = unitResult.value;
      if (unit == null) {
        return null;
      }

      // Compare against the version for the SAME target language only.
      final versionResult = await _versionRepository.getByUnitAndProjectLanguage(
        unitId: unit.id,
        projectLanguageId: projectLanguageId,
      );
      if (versionResult.isErr) {
        return null;
      }

      final version = versionResult.value;

      final importedSourceText = sourceColumn.isNotEmpty ? row[sourceColumn] : null;
      final importedTargetText = targetColumn.isNotEmpty ? row[targetColumn] : null;

      final sourceTextDiffers = importedSourceText != null &&
          importedSourceText != unit.sourceText;

      return ImportConflict(
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
      );
    } catch (e) {
      return null;
    }
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
