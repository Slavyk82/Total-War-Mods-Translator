import 'dart:io';
import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../models/domain/translation_version.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/file/i_file_service.dart';
import '../../../services/file/models/file_exceptions.dart';
import '../../../services/history/i_history_service.dart';
import '../models/import_conflict.dart';
import '../models/import_export_settings.dart';
import '../models/import_preview.dart';
import '../models/import_result.dart';
import '../models/export_result.dart';
import 'import_conflict_detector.dart';
import 'import_executor.dart';
import 'import_preview_service.dart';
import 'utils/import_file_reader.dart';

/// Callback for progress updates
typedef ProgressCallback = void Function(int current, int total);

/// Service for coordinating import/export operations
class ImportExportService {
  final IFileService _fileService;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final IHistoryService _historyService;
  final ProjectLanguageRepository _projectLanguageRepository;

  late final ImportFileReader _fileReader;
  late final ImportPreviewService _previewService;
  late final ImportConflictDetector _conflictDetector;
  late final ImportExecutor _executor;

  ImportExportService(
    this._fileService,
    this._unitRepository,
    this._versionRepository,
    this._historyService,
    this._projectLanguageRepository,
  ) {
    _fileReader = ImportFileReader(_fileService);
    _previewService = ImportPreviewService(_fileReader);
    _conflictDetector = ImportConflictDetector(
      _fileReader,
      _unitRepository,
      _versionRepository,
      _projectLanguageRepository,
    );
    _executor = ImportExecutor(
      _fileReader,
      _unitRepository,
      _versionRepository,
      _historyService,
      _projectLanguageRepository,
    );
  }

  /// Parse import file and return preview
  Future<Result<ImportPreview, ServiceException>> previewImport(
    String filePath,
    ImportSettings settings,
  ) async {
    return await _previewService.previewImport(filePath, settings);
  }

  /// Detect conflicts between import data and existing translations
  Future<Result<List<ImportConflict>, ServiceException>> detectConflicts(
    ImportPreview preview,
    ImportSettings settings,
  ) async {
    return await _conflictDetector.detectConflicts(preview, settings);
  }

  /// Execute import with conflict resolution.
  ///
  /// Pass the previewed file's `ImportPreview.contentHash` as
  /// [expectedContentHash] so the executor can abort if the file changed on
  /// disk between preview and import.
  Future<Result<ImportResult, ServiceException>> executeImport(
    String filePath,
    ImportSettings settings,
    ConflictResolutions resolutions, {
    String? expectedContentHash,
    ProgressCallback? onProgress,
  }) async {
    return await _executor.executeImport(
      filePath,
      settings,
      resolutions,
      expectedContentHash: expectedContentHash,
      onProgress: onProgress,
    );
  }

  /// Validate import data
  Future<Result<ImportValidationResult, ServiceException>> validateImport(
    ImportPreview preview,
    ImportSettings settings,
  ) async {
    return await _previewService.validateImport(preview, settings);
  }

  /// Auto-detect column mapping from headers
  Map<String, String> detectColumnMapping(List<String> headers) {
    return _fileReader.detectColumnMapping(headers);
  }

  /// Execute export with progress tracking
  Future<Result<ExportResult, ServiceException>> executeExport(
    ExportSettings settings,
    String outputPath, {
    ProgressCallback? onProgress,
  }) async {
    final startTime = DateTime.now();

    try {
      final versionsResult = await _loadFilteredVersions(settings);

      if (versionsResult.isErr) {
        return Err(versionsResult.error);
      }

      final versions = versionsResult.value;
      final data = <Map<String, String>>[];

      for (int i = 0; i < versions.length; i++) {
        onProgress?.call(i + 1, versions.length);

        final version = versions[i];
        final unitResult = await _unitRepository.getById(version.unitId);
        if (unitResult.isErr) continue;

        final unit = unitResult.value;
        if (!_unitPassesFilter(unit, settings.filterOptions)) continue;

        final row = _buildExportRow(version, unit, settings.columns);
        data.add(row);
      }

      final exportResult = await _exportData(data, settings, outputPath);

      if (exportResult.isErr) {
        return Err(
          ServiceException('Export failed: ${exportResult.error}'),
        );
      }

      final file = File(outputPath);
      final fileSize = await file.length();
      final duration = DateTime.now().difference(startTime).inMilliseconds;

      return Ok(
        ExportResult(
          filePath: outputPath,
          rowCount: data.length,
          fileSize: fileSize,
          durationMs: duration,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Export failed: $e', stackTrace: stackTrace),
      );
    }
  }

  /// Generate export preview
  Future<Result<ExportPreview, ServiceException>> previewExport(
    ExportSettings settings,
  ) async {
    try {
      final versionsResult = await _loadFilteredVersions(settings);

      if (versionsResult.isErr) {
        return Err(versionsResult.error);
      }

      final allVersions = versionsResult.value;
      final previewRows = <Map<String, String>>[];
      final headers = _buildExportHeaders(settings.columns);

      // Apply the unit-level (context) filter while building the matching set so
      // the reported totalRows reflects the real export size, not the raw
      // version count.
      var matchedRows = 0;
      for (final version in allVersions) {
        final unitResult = await _unitRepository.getById(version.unitId);
        if (unitResult.isErr) continue;

        final unit = unitResult.value;
        if (!_unitPassesFilter(unit, settings.filterOptions)) continue;

        matchedRows++;
        if (previewRows.length < 10) {
          previewRows.add(_buildExportRow(version, unit, settings.columns));
        }
      }

      final avgRowSize = previewRows.isEmpty
          ? 100
          : previewRows.first.values.join(',').length;
      final estimatedSize = avgRowSize * matchedRows;

      return Ok(
        ExportPreview(
          previewRows: previewRows,
          totalRows: matchedRows,
          estimatedSize: estimatedSize,
          headers: headers,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        ServiceException('Failed to generate preview: $e', stackTrace: stackTrace),
      );
    }
  }

  /// Load the translation versions that belong to the export's project +
  /// target language, applying the version-level filter options.
  ///
  /// Previously this used `getAll()` which returned EVERY version of EVERY
  /// project/language, ignoring [ExportSettings.projectId] /
  /// [ExportSettings.targetLanguageId] / [ExportSettings.filterOptions] — a
  /// cross-project data leak and an enormous, wrong export.
  Future<Result<List<TranslationVersion>, ServiceException>>
      _loadFilteredVersions(ExportSettings settings) async {
    final projectLanguageResult =
        await _projectLanguageRepository.getByProjectAndLanguage(
      settings.projectId,
      settings.targetLanguageId,
    );

    if (projectLanguageResult.isErr) {
      return Err(ServiceException(
        'Failed to resolve project language: ${projectLanguageResult.error}',
      ));
    }

    final projectLanguage = projectLanguageResult.value;

    final versionsResult =
        await _versionRepository.getByProjectLanguage(projectLanguage.id);

    if (versionsResult.isErr) {
      return Err(ServiceException(
        'Failed to fetch translations: ${versionsResult.error}',
      ));
    }

    final filtered = versionsResult.value
        .where((v) => _versionPassesFilter(v, settings.filterOptions))
        .toList();

    return Ok(filtered);
  }

  /// Whether a version satisfies the version-level filter options.
  bool _versionPassesFilter(TranslationVersion version, ExportFilterOptions f) {
    if (f.validatedOnly &&
        version.status != TranslationVersionStatus.translated) {
      return false;
    }
    if (f.translationsOnly &&
        (version.translatedText == null || version.translatedText!.isEmpty)) {
      return false;
    }
    if (f.statusFilter != null &&
        f.statusFilter!.isNotEmpty &&
        !f.statusFilter!.contains(version.status.toDbValue)) {
      return false;
    }
    if (f.createdAfter != null && version.createdAt < f.createdAfter!) {
      return false;
    }
    if (f.updatedAfter != null && version.updatedAt < f.updatedAfter!) {
      return false;
    }
    return true;
  }

  /// Whether a unit satisfies the unit-level (context) filter.
  bool _unitPassesFilter(dynamic unit, ExportFilterOptions f) {
    final contextFilter = f.contextFilter;
    if (contextFilter != null && contextFilter.isNotEmpty) {
      final context = (unit.context as String?) ?? '';
      if (!context.toLowerCase().contains(contextFilter.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  /// Build export row data from version and unit
  Map<String, String> _buildExportRow(
    TranslationVersion version,
    dynamic unit,
    List<ExportColumn> columns,
  ) {
    final row = <String, String>{};

    for (final column in columns) {
      final (key, value) = switch (column) {
        ExportColumn.key => ('key', unit.key),
        ExportColumn.sourceText => ('source_text', unit.sourceText),
        ExportColumn.targetText => ('target_text', version.translatedText ?? ''),
        ExportColumn.status => ('status', version.statusDisplay),
        ExportColumn.notes => ('notes', unit.notes ?? ''),
        ExportColumn.context => ('context', unit.context ?? ''),
        ExportColumn.createdAt => ('created_at', DateTime.fromMillisecondsSinceEpoch(
            version.createdAt * 1000,
          ).toIso8601String()),
        ExportColumn.updatedAt => ('updated_at', DateTime.fromMillisecondsSinceEpoch(
            version.updatedAt * 1000,
          ).toIso8601String()),
        ExportColumn.changedBy => ('changed_by', version.isManuallyEdited ? 'User' : 'LLM'),
      };
      row[key] = value;
    }

    return row;
  }

  /// Build export headers from column list
  List<String> _buildExportHeaders(List<ExportColumn> columns) {
    return columns.map((col) => switch (col) {
      ExportColumn.key => 'key',
      ExportColumn.sourceText => 'source_text',
      ExportColumn.targetText => 'target_text',
      ExportColumn.status => 'status',
      ExportColumn.notes => 'notes',
      ExportColumn.context => 'context',
      ExportColumn.createdAt => 'created_at',
      ExportColumn.updatedAt => 'updated_at',
      ExportColumn.changedBy => 'changed_by',
    }).toList();
  }

  /// Export data to file based on format
  Future<Result<String, ExportException>> _exportData(
    List<Map<String, String>> data,
    ExportSettings settings,
    String outputPath,
  ) async {
    return switch (settings.format) {
      ExportFormat.csv => await _fileService.exportToCsv(
          data: data,
          filePath: outputPath,
        ),
      ExportFormat.json => await _fileService.exportToJson(
          data: data,
          filePath: outputPath,
          prettyPrint: settings.formatOptions.prettyPrint,
        ),
      ExportFormat.excel => await _fileService.exportToExcel(
          data: data,
          filePath: outputPath,
        ),
      ExportFormat.loc => Err(
          ExportException(
            '.loc format export not yet implemented',
            outputPath,
            'loc',
            entriesExported: 0,
          ),
        ),
    };
  }
}
