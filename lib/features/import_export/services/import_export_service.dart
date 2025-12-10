import 'dart:io';
import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../models/domain/translation_version.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/file/i_file_service.dart';
import '../../../services/file/models/file_exceptions.dart';
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

  late final ImportFileReader _fileReader;
  late final ImportPreviewService _previewService;
  late final ImportConflictDetector _conflictDetector;
  late final ImportExecutor _executor;

  ImportExportService(
    this._fileService,
    this._unitRepository,
    this._versionRepository,
  ) {
    _fileReader = ImportFileReader(_fileService);
    _previewService = ImportPreviewService(_fileReader);
    _conflictDetector = ImportConflictDetector(
      _fileReader,
      _unitRepository,
      _versionRepository,
    );
    _executor = ImportExecutor(
      _fileReader,
      _unitRepository,
      _versionRepository,
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

  /// Execute import with conflict resolution
  Future<Result<ImportResult, ServiceException>> executeImport(
    String filePath,
    ImportSettings settings,
    ConflictResolutions resolutions, {
    ProgressCallback? onProgress,
  }) async {
    return await _executor.executeImport(
      filePath,
      settings,
      resolutions,
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
      final versionsResult = await _versionRepository.getAll();

      if (versionsResult.isErr) {
        return Err(
          ServiceException('Failed to fetch translations: ${versionsResult.error}'),
        );
      }

      final versions = versionsResult.value;
      final data = <Map<String, String>>[];

      for (int i = 0; i < versions.length; i++) {
        onProgress?.call(i + 1, versions.length);

        final version = versions[i];
        final unitResult = await _unitRepository.getById(version.unitId);
        if (unitResult.isErr) continue;

        final unit = unitResult.value;
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
      final versionsResult = await _versionRepository.getAll();

      if (versionsResult.isErr) {
        return Err(
          ServiceException('Failed to fetch data: ${versionsResult.error}'),
        );
      }

      final versions = versionsResult.value;
      final previewRows = <Map<String, String>>[];
      final headers = _buildExportHeaders(settings.columns);

      for (int i = 0; i < versions.length && i < 10; i++) {
        final version = versions[i];
        final unitResult = await _unitRepository.getById(version.unitId);

        if (unitResult.isErr) continue;

        final unit = unitResult.value;
        final row = _buildExportRow(version, unit, settings.columns);
        previewRows.add(row);
      }

      final avgRowSize = previewRows.isEmpty
          ? 100
          : previewRows.first.values.join(',').length;
      final estimatedSize = avgRowSize * versions.length;

      return Ok(
        ExportPreview(
          previewRows: previewRows,
          totalRows: versions.length,
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
