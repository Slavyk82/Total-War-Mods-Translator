import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
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

  const ImportConflictDetector(
    this._fileReader,
    this._unitRepository,
    this._versionRepository,
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

      for (final row in rows) {
        final key = row[keyColumn];
        if (key == null || key.isEmpty) continue;

        final conflict = await _checkRowForConflict(
          key: key,
          row: row,
          sourceColumn: sourceColumn,
          targetColumn: targetColumn,
          projectId: settings.projectId,
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
  }) async {
    try {
      final unitsResult = await _unitRepository.getByKey(projectId, key);

      if (unitsResult.isErr) {
        return null;
      }

      final unit = unitsResult.value;

      final versionsResult = await _versionRepository.getByUnit(unit.id);
      if (versionsResult.isErr || versionsResult.value.isEmpty) {
        return null;
      }

      final version = versionsResult.value.first;

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
