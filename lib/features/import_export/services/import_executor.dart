import 'package:uuid/uuid.dart';
import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../models/domain/translation_unit.dart';
import '../../../models/domain/translation_version.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/translation/utils/translation_text_utils.dart';
import '../models/import_conflict.dart';
import '../models/import_export_settings.dart';
import '../models/import_result.dart';
import 'utils/import_file_reader.dart';

/// Callback for progress updates
typedef ProgressCallback = void Function(int current, int total);

/// Service responsible for executing import operations
class ImportExecutor {
  final ImportFileReader _fileReader;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final Uuid _uuid = const Uuid();

  const ImportExecutor(
    this._fileReader,
    this._unitRepository,
    this._versionRepository,
  );

  /// Execute import with conflict resolution
  Future<Result<ImportResult, ServiceException>> executeImport(
    String filePath,
    ImportSettings settings,
    ConflictResolutions resolutions, {
    ProgressCallback? onProgress,
  }) async {
    final startTime = DateTime.now();

    try {
      int totalProcessed = 0;
      int successCount = 0;
      int skippedCount = 0;
      int errorCount = 0;
      final errors = <String, String>{};
      final importedIds = <String>[];

      final fileDataResult = await _fileReader.readFile(filePath, settings);

      if (fileDataResult.isErr) {
        return Err(fileDataResult.error);
      }

      final rows = fileDataResult.value.rows;

      final keyColumn = _findColumn(settings.columnMapping, ImportColumn.key);
      if (keyColumn.isEmpty) {
        return Err(
          ServiceException('Key column mapping is required'),
        );
      }

      final sourceColumn = _findColumn(
        settings.columnMapping,
        ImportColumn.sourceText,
      );
      final targetColumn = _findColumn(
        settings.columnMapping,
        ImportColumn.targetText,
      );

      for (int i = 0; i < rows.length; i++) {
        totalProcessed++;
        onProgress?.call(i + 1, rows.length);

        final row = rows[i];
        final key = row[keyColumn];

        if (key == null || key.isEmpty) {
          errorCount++;
          errors[i.toString()] = 'Missing key';
          continue;
        }

        try {
          final result = await _processRow(
            key: key,
            row: row,
            sourceColumn: sourceColumn,
            targetColumn: targetColumn,
            settings: settings,
            resolutions: resolutions,
          );

          if (result.isSuccess) {
            successCount++;
            if (result.value != null) {
              importedIds.add(result.value!);
            }
          } else if (result.isSkipped) {
            skippedCount++;
          } else {
            errorCount++;
            errors[key] = result.errorMessage ?? 'Unknown error';
          }
        } catch (e) {
          errorCount++;
          errors[key] = e.toString();
        }
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      return Ok(
        ImportResult(
          totalProcessed: totalProcessed,
          successCount: successCount,
          skippedCount: skippedCount,
          errorCount: errorCount,
          errors: errors,
          importedIds: importedIds,
          durationMs: duration,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Import failed: $e', stackTrace: stackTrace),
      );
    }
  }

  /// Process a single row import
  Future<_RowProcessResult> _processRow({
    required String key,
    required Map<String, String> row,
    required String sourceColumn,
    required String targetColumn,
    required ImportSettings settings,
    required ConflictResolutions resolutions,
  }) async {
    try {
      final unitsResult = await _unitRepository.getByKey(
        settings.projectId,
        key,
      );

      TranslationUnit? processedUnit;

      if (unitsResult.isErr) {
        final createResult = await _createNewUnit(
          key: key,
          row: row,
          sourceColumn: sourceColumn,
          projectId: settings.projectId,
        );

        if (createResult.isErr) {
          return _RowProcessResult.error(createResult.error.message);
        }

        processedUnit = createResult.value;
      } else {
        processedUnit = unitsResult.value;
      }

      return await _processVersion(
        unit: processedUnit,
        row: row,
        targetColumn: targetColumn,
        settings: settings,
        resolutions: resolutions,
        key: key,
      );
    } catch (e) {
      return _RowProcessResult.error(e.toString());
    }
  }

  /// Create a new translation unit
  Future<Result<TranslationUnit, ServiceException>> _createNewUnit({
    required String key,
    required Map<String, String> row,
    required String sourceColumn,
    required String projectId,
  }) async {
    final sourceText = sourceColumn.isNotEmpty ? (row[sourceColumn] ?? '') : '';

    if (sourceText.isEmpty) {
      return Err(
        ServiceException('Source text is required for new units'),
      );
    }

    final newUnit = TranslationUnit(
      id: _uuid.v4(),
      projectId: projectId,
      key: key,
      sourceText: sourceText,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    return await _unitRepository.insert(newUnit);
  }

  /// Process translation version (create or update)
  Future<_RowProcessResult> _processVersion({
    required TranslationUnit unit,
    required Map<String, String> row,
    required String targetColumn,
    required ImportSettings settings,
    required ConflictResolutions resolutions,
    required String key,
  }) async {
    final versionsResult = await _versionRepository.getByUnit(unit.id);

    if (versionsResult.isOk && versionsResult.value.isNotEmpty) {
      return await _updateExistingVersion(
        existingVersion: versionsResult.value.first,
        row: row,
        targetColumn: targetColumn,
        resolutions: resolutions,
        key: key,
      );
    } else {
      return await _createNewVersion(
        unit: unit,
        row: row,
        targetColumn: targetColumn,
        settings: settings,
      );
    }
  }

  /// Update existing translation version based on conflict resolution
  Future<_RowProcessResult> _updateExistingVersion({
    required TranslationVersion existingVersion,
    required Map<String, String> row,
    required String targetColumn,
    required ConflictResolutions resolutions,
    required String key,
  }) async {
    final resolution = resolutions.getResolution(key);

    if (resolution == null || resolution == ConflictResolution.keepExisting) {
      return _RowProcessResult.skipped();
    }

    final rawText = targetColumn.isNotEmpty ? row[targetColumn] : null;
    // Normalize: \\n → \n
    final translatedText = rawText != null
        ? TranslationTextUtils.normalizeTranslation(rawText)
        : null;

    if (resolution == ConflictResolution.useImported) {
      final updated = existingVersion.copyWith(
        translatedText: translatedText,
        isManuallyEdited: true,
        status: TranslationVersionStatus.translated,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await _versionRepository.update(updated);
      if (updateResult.isOk) {
        return _RowProcessResult.success(updated.id);
      } else {
        return _RowProcessResult.error('Failed to update version');
      }
    } else if (resolution == ConflictResolution.merge) {
      final mergedText = existingVersion.translatedText ?? translatedText;
      final updated = existingVersion.copyWith(
        translatedText: mergedText,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await _versionRepository.update(updated);
      if (updateResult.isOk) {
        return _RowProcessResult.success(updated.id);
      } else {
        return _RowProcessResult.error('Failed to merge version');
      }
    }

    return _RowProcessResult.skipped();
  }

  /// Create new translation version
  Future<_RowProcessResult> _createNewVersion({
    required TranslationUnit unit,
    required Map<String, String> row,
    required String targetColumn,
    required ImportSettings settings,
  }) async {
    final rawText = targetColumn.isNotEmpty ? row[targetColumn] : null;
    // Normalize: \\n → \n
    final translatedText = rawText != null
        ? TranslationTextUtils.normalizeTranslation(rawText)
        : null;

    final newVersion = TranslationVersion(
      id: _uuid.v4(),
      unitId: unit.id,
      projectLanguageId: settings.targetLanguageId,
      translatedText: translatedText,
      isManuallyEdited: true,
      status: translatedText != null && translatedText.isNotEmpty
          ? TranslationVersionStatus.translated
          : TranslationVersionStatus.pending,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final insertResult = await _versionRepository.insert(newVersion);
    if (insertResult.isOk) {
      return _RowProcessResult.success(newVersion.id);
    } else {
      return _RowProcessResult.error('Failed to create version');
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

/// Result of processing a single row
class _RowProcessResult {
  final bool isSuccess;
  final bool isSkipped;
  final String? value;
  final String? errorMessage;

  const _RowProcessResult._({
    required this.isSuccess,
    required this.isSkipped,
    this.value,
    this.errorMessage,
  });

  factory _RowProcessResult.success(String id) => _RowProcessResult._(
        isSuccess: true,
        isSkipped: false,
        value: id,
      );

  factory _RowProcessResult.skipped() => const _RowProcessResult._(
        isSuccess: false,
        isSkipped: true,
      );

  factory _RowProcessResult.error(String message) => _RowProcessResult._(
        isSuccess: false,
        isSkipped: false,
        errorMessage: message,
      );
}
