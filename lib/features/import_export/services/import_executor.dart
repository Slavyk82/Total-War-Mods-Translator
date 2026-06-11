import 'package:uuid/uuid.dart';
import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../models/domain/translation_unit.dart';
import '../../../models/domain/translation_version.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/history/i_history_service.dart';
import '../../../services/translation/utils/translation_text_utils.dart';
import '../models/import_conflict.dart';
import '../models/import_export_settings.dart';
import '../models/import_result.dart';
import 'utils/import_file_integrity.dart';
import 'utils/import_file_reader.dart';

/// Callback for progress updates
typedef ProgressCallback = void Function(int current, int total);

/// Service responsible for executing import operations
class ImportExecutor {
  final ImportFileReader _fileReader;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final IHistoryService _historyService;
  final ProjectLanguageRepository _projectLanguageRepository;
  final Uuid _uuid = const Uuid();

  ImportExecutor(
    this._fileReader,
    this._unitRepository,
    this._versionRepository,
    this._historyService,
    this._projectLanguageRepository,
  );

  /// Execute import with conflict resolution.
  ///
  /// When [expectedContentHash] is provided (the sha256 stored on
  /// `ImportPreview.contentHash` at preview time), the file content is
  /// re-verified right before importing and the import aborts if the file
  /// changed on disk since the preview — otherwise the conflicts the user
  /// reviewed would not match the data actually imported.
  Future<Result<ImportResult, ServiceException>> executeImport(
    String filePath,
    ImportSettings settings,
    ConflictResolutions resolutions, {
    String? expectedContentHash,
    ProgressCallback? onProgress,
  }) async {
    final startTime = DateTime.now();

    try {
      // Integrity guard: the preview/conflict stages and this executor each
      // re-read the file from disk. Verify the content is still what the user
      // previewed BEFORE writing anything, otherwise the reviewed conflicts
      // were computed on different data than the import would apply.
      if (expectedContentHash != null) {
        final currentHash =
            await ImportFileIntegrity.computeContentHash(filePath);
        if (currentHash != expectedContentHash) {
          return Err(
            ServiceException(
              'Import file changed on disk since preview; '
              'please re-open the import dialog and preview the file again.',
            ),
          );
        }
      }

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

      // Resolve the project_languages row id ONCE. settings.targetLanguageId
      // is a language id, NOT a project_languages.id; writing it straight into
      // translation_versions.project_language_id would orphan every imported
      // version (invisible to the editor and excluded from export).
      // findByProjectAndLanguage distinguishes "not in project" (Ok(null))
      // from a real DB failure (Err): a real failure must surface as-is, not
      // be mislabeled as a missing language.
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
        return Err(
          ServiceException(
            'Target language is not part of this project. '
            'Add it to the project before importing.',
          ),
        );
      }
      final projectLanguageId = projectLanguage.id;

      final sourceColumn = _findColumn(
        settings.columnMapping,
        ImportColumn.sourceText,
      );
      final targetColumn = _findColumn(
        settings.columnMapping,
        ImportColumn.targetText,
      );

      // Keys created/updated earlier in THIS import run. A second row for the
      // same key is a within-file duplicate, not a pre-existing DB conflict the
      // user reviewed, so it must apply last-wins rather than erroring on a
      // missing resolution.
      final processedKeys = <String>{};

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
            projectLanguageId: projectLanguageId,
            duplicateWithinRun: processedKeys.contains(key),
          );

          if (result.isSuccess) {
            successCount++;
            processedKeys.add(key);
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
    required String projectLanguageId,
    required bool duplicateWithinRun,
  }) async {
    try {
      // findByKey distinguishes "not found" (Ok(null)) from a real DB error
      // (Err). A transient DB error must NOT be misread as "create a new
      // unit", which could attempt a duplicate (project_id, key) insert.
      final unitResult = await _unitRepository.findByKey(
        settings.projectId,
        key,
      );

      if (unitResult.isErr) {
        return _RowProcessResult.error(unitResult.error.message);
      }

      TranslationUnit? processedUnit = unitResult.value;

      // Track whether THIS row created the unit, so that if the subsequent
      // version write fails we can roll the orphan unit back (see below).
      //
      // NOTE on atomicity: the import is NOT wrapped in a single DB transaction.
      // Each row performs independent repository writes (insert unit, insert/
      // update version, recordChange), so a mid-import crash can leave earlier
      // rows applied and later ones not. SQLite makes each statement atomic and
      // history is only recorded after the version write succeeds, so the worst
      // realistic outcome is an incomplete-but-not-corrupt import (reported per
      // row via ImportResult.errors). A fully atomic import would require
      // cross-repository transaction support; that refactor is intentionally
      // out of scope for this low-severity fix. The orphan-unit rollback below
      // is the minimal safe guard against the one observable inconsistency
      // (a unit with no version).
      final bool createdUnitThisRow = processedUnit == null;

      if (processedUnit == null) {
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
      }

      final versionResult = await _processVersion(
        unit: processedUnit,
        row: row,
        targetColumn: targetColumn,
        settings: settings,
        resolutions: resolutions,
        key: key,
        projectLanguageId: projectLanguageId,
        duplicateWithinRun: duplicateWithinRun,
      );

      // If we created the unit in this row but the version write failed, delete
      // the freshly-created unit so we don't leave a keyed-but-empty orphan that
      // the user can neither see nor easily clean up. Best-effort: a delete
      // failure must not mask the original version error.
      if (createdUnitThisRow &&
          !versionResult.isSuccess &&
          !versionResult.isSkipped) {
        await _unitRepository.delete(processedUnit.id);
      }

      return versionResult;
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
    required String projectLanguageId,
    required bool duplicateWithinRun,
  }) async {
    // Scope the lookup to the target language's project_languages row. Using
    // getByUnit(...).first would pick an arbitrary sibling language's version
    // (all share the same created_at) and overwrite/merge the wrong language.
    //
    // findByUnitAndProjectLanguage distinguishes "not found" (Ok(null)) from
    // a real DB failure (Err). A real failure must NOT be misread as "no
    // version exists": the create path would then hit the
    // UNIQUE(unit_id, project_language_id) constraint or silently duplicate.
    final versionResult =
        await _versionRepository.findByUnitAndProjectLanguage(
      unitId: unit.id,
      projectLanguageId: projectLanguageId,
    );

    if (versionResult.isErr) {
      return _RowProcessResult.error(versionResult.error.message);
    }

    final existingVersion = versionResult.value;
    if (existingVersion != null) {
      return await _updateExistingVersion(
        existingVersion: existingVersion,
        row: row,
        targetColumn: targetColumn,
        resolutions: resolutions,
        key: key,
        duplicateWithinRun: duplicateWithinRun,
      );
    } else {
      return await _createNewVersion(
        unit: unit,
        row: row,
        targetColumn: targetColumn,
        projectLanguageId: projectLanguageId,
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
    required bool duplicateWithinRun,
  }) async {
    var resolution = resolutions.getResolution(key);

    // A conflicting row with NO resolution (key absent from the map and no
    // default) must be surfaced to the user, not silently folded into
    // skippedCount where it is indistinguishable from an explicit
    // keepExisting decision.
    //
    // Exception: when the "existing" version was itself created/updated earlier
    // in THIS import run (a within-file duplicate key), there is no pre-existing
    // DB conflict for the user to have reviewed — detectConflicts saw nothing
    // because the unit did not exist at preview time. Apply last-wins instead
    // of erroring and dropping the row.
    if (resolution == null) {
      if (duplicateWithinRun) {
        resolution = ConflictResolution.useImported;
      } else {
        return _RowProcessResult.error(
          'Unresolved conflict: no resolution provided for this key',
        );
      }
    }

    if (resolution == ConflictResolution.keepExisting) {
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
        // Record history entry for import update
        await _historyService.recordChange(
          versionId: updated.id,
          translatedText: translatedText ?? '',
          status: updated.status.name,
          changedBy: 'import',
          changeReason: 'Import replaced existing translation',
        );
        return _RowProcessResult.success(updated.id);
      } else {
        return _RowProcessResult.error('Failed to update version');
      }
    } else if (resolution == ConflictResolution.merge) {
      // Keep the existing translation only when it actually has content:
      // '' is non-null, so `existing ?? imported` would let an empty or
      // whitespace-only existing translation discard the imported text.
      final existingText = existingVersion.translatedText;
      final mergedText =
          (existingText != null && existingText.trim().isNotEmpty)
              ? existingText
              : translatedText;
      final updated = existingVersion.copyWith(
        translatedText: mergedText,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await _versionRepository.update(updated);
      if (updateResult.isOk) {
        // Record history entry for import merge
        await _historyService.recordChange(
          versionId: updated.id,
          translatedText: mergedText ?? '',
          status: updated.status.name,
          changedBy: 'import',
          changeReason: 'Import merged with existing translation',
        );
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
    required String projectLanguageId,
  }) async {
    final rawText = targetColumn.isNotEmpty ? row[targetColumn] : null;
    // Normalize: \\n → \n
    final translatedText = rawText != null
        ? TranslationTextUtils.normalizeTranslation(rawText)
        : null;

    final newVersion = TranslationVersion(
      id: _uuid.v4(),
      unitId: unit.id,
      projectLanguageId: projectLanguageId,
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
      // Record initial history entry
      await _historyService.recordChange(
        versionId: newVersion.id,
        translatedText: translatedText ?? '',
        status: newVersion.status.name,
        changedBy: 'import',
        changeReason: 'Initial import',
      );
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
