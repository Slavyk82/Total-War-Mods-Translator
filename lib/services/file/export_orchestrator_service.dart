import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/export_data_collector.dart';
import 'package:twmt/services/file/export_history_recorder.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/pack_export_utils.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

/// Export progress callback
typedef ExportProgressCallback = void Function(
  String step,
  double progress, {
  String? currentLanguage,
  int? currentIndex,
  int? total,
});

/// Export result data
class ExportResult {
  final String outputPath;
  final int entryCount;
  final int fileSize;
  final List<String> languageCodes;

  const ExportResult({
    required this.outputPath,
    required this.entryCount,
    required this.fileSize,
    required this.languageCodes,
  });
}

/// Service for orchestrating the complete export process
///
/// Coordinates all export operations including:
/// - .loc file generation
/// - .pack file creation
/// - Alternative format exports (CSV, Excel, TMX)
/// - Export history tracking
class ExportOrchestratorService {
  final ILocFileService _locFileService;
  final IRpfmService _rpfmService;
  final FileImportExportService _fileImportExportService;
  final TmxService _tmxService;
  final ProjectRepository _projectRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final ExportDataCollector _dataCollector;
  final ExportHistoryRecorder _historyRecorder;
  final PackExportUtils _packUtils;
  final LoggingService _logger;

  ExportOrchestratorService({
    required ILocFileService locFileService,
    required IRpfmService rpfmService,
    required FileImportExportService fileImportExportService,
    required TmxService tmxService,
    required ExportHistoryRepository exportHistoryRepository,
    required GameInstallationRepository gameInstallationRepository,
    required ProjectRepository projectRepository,
    required ProjectLanguageRepository projectLanguageRepository,
    required TranslationUnitRepository translationUnitRepository,
    required TranslationVersionRepository translationVersionRepository,
    LoggingService? logger,
  })  : _locFileService = locFileService,
        _rpfmService = rpfmService,
        _fileImportExportService = fileImportExportService,
        _tmxService = tmxService,
        _projectRepository = projectRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _dataCollector = ExportDataCollector(
          projectLanguageRepository: projectLanguageRepository,
          translationUnitRepository: translationUnitRepository,
          translationVersionRepository: translationVersionRepository,
          logger: logger,
        ),
        _historyRecorder = ExportHistoryRecorder(
          exportHistoryRepository: exportHistoryRepository,
          logger: logger,
        ),
        _packUtils = PackExportUtils(logger: logger),
        _logger = logger ?? LoggingService.instance;

  /// Export translations to .pack file
  ///
  /// This is the main export method for Total War mods.
  /// It generates .loc files and packages them into a .pack file.
  Future<Result<ExportResult, FileServiceException>> exportToPack({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    ExportProgressCallback? onProgress,
  }) async {
    Directory? tempDir;

    try {
      _logger.info('Starting .pack export', {
        'projectId': projectId,
        'languages': languageCodes,
        'outputPath': outputPath,
        'validatedOnly': validatedOnly,
      });

      onProgress?.call('preparingData', 0.0);
      await _historyRecorder.ensureTableExists();

      // Validate project and get game installation
      final validationResult = await _validateProjectAndGame(projectId);
      if (validationResult.isErr) {
        return Err(validationResult.unwrapErr());
      }

      final (project, gameInstallation) = validationResult.unwrap();
      final gameDataPath =
          path.join(gameInstallation.installationPath!, 'data');

      // Create temporary directory for TSV files
      tempDir = await _packUtils.createTempDirectory('twmt_pack_export');

      // Generate TSV files for each language
      onProgress?.call('generatingLocFiles', 0.1);
      int totalEntries = 0;

      for (var i = 0; i < languageCodes.length; i++) {
        final languageCode = languageCodes[i];
        onProgress?.call(
          'generatingLocFiles',
          0.1 + (0.5 * (i / languageCodes.length)),
          currentLanguage: languageCode,
          currentIndex: i,
          total: languageCodes.length,
        );

        final result = await _locFileService.generateLocFilesGroupedBySource(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: validatedOnly,
        );

        if (result is Err) {
          return Err(result.error);
        }

        final generatedTsvPaths =
            (result as Ok<List<String>, FileServiceException>).value;

        // Copy TSV files to pack structure directory
        await _packUtils.copyTsvFilesToPackStructure(generatedTsvPaths, tempDir);

        // Count entries
        final countResult = await _locFileService.countExportableTranslations(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: validatedOnly,
        );
        if (countResult is Ok) {
          totalEntries += (countResult as Ok<int, FileServiceException>).value;
        }
      }

      // Create .pack file using RPFM
      onProgress?.call('creatingPack', 0.6);
      await Directory(gameDataPath).create(recursive: true);

      final packFileName = _packUtils.buildPackFileName(
        languageCodes.first,
        project.sourceFilePath,
      );
      final packPath = path.join(gameDataPath, packFileName);

      // Progress range for pack creation: 0.6 to 0.85
      const packProgressStart = 0.6;
      const packProgressEnd = 0.85;
      const packProgressRange = packProgressEnd - packProgressStart;

      final packResult = await _rpfmService.createPack(
        inputDirectory: tempDir.path,
        outputPackPath: packPath,
        languageCode: languageCodes.first,
        onProgress: (currentFile, totalFiles, fileName) {
          if (totalFiles > 0) {
            final fileProgress = currentFile / totalFiles;
            final overallProgress = packProgressStart + (packProgressRange * fileProgress);
            onProgress?.call(
              'creatingPack',
              overallProgress,
              currentLanguage: fileName.isNotEmpty ? fileName : null,
              currentIndex: currentFile,
              total: totalFiles,
            );
          }
        },
      );

      if (packResult is Err) {
        return Err(FileServiceException(
          'Failed to create .pack file: ${packResult.error}',
        ));
      }

      final fileSize = await File(packPath).length();

      onProgress?.call('finalizing', 0.9);

      await _historyRecorder.recordExport(
        projectId: projectId,
        languageCodes: languageCodes,
        format: ExportFormat.pack,
        validatedOnly: validatedOnly,
        outputPath: packPath,
        fileSize: fileSize,
        entryCount: totalEntries,
      );

      onProgress?.call('completed', 1.0);

      _logger.info('.pack export completed', {
        'outputPath': packPath,
        'entries': totalEntries,
        'fileSize': fileSize,
      });

      return Ok(ExportResult(
        outputPath: packPath,
        entryCount: totalEntries,
        fileSize: fileSize,
        languageCodes: languageCodes,
      ));
    } catch (e, stackTrace) {
      _logger.error('Failed to export .pack', e, stackTrace);
      return Err(FileServiceException(
        'Failed to export .pack: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    } finally {
      await _packUtils.cleanupTempDirectory(tempDir);
    }
  }

  /// Export translations to CSV file
  Future<Result<ExportResult, FileServiceException>> exportToCsv({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    ExportProgressCallback? onProgress,
  }) async {
    return _exportToTabular(
      projectId: projectId,
      languageCodes: languageCodes,
      outputPath: outputPath,
      validatedOnly: validatedOnly,
      format: ExportFormat.csv,
      onProgress: onProgress,
    );
  }

  /// Export translations to Excel file
  Future<Result<ExportResult, FileServiceException>> exportToExcel({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    ExportProgressCallback? onProgress,
  }) async {
    return _exportToTabular(
      projectId: projectId,
      languageCodes: languageCodes,
      outputPath: outputPath,
      validatedOnly: validatedOnly,
      format: ExportFormat.excel,
      onProgress: onProgress,
    );
  }

  /// Export translations to TMX file
  Future<Result<ExportResult, FileServiceException>> exportToTmx({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    ExportProgressCallback? onProgress,
  }) async {
    try {
      _logger.info('Starting TMX export', {
        'projectId': projectId,
        'languages': languageCodes,
        'outputPath': outputPath,
        'validatedOnly': validatedOnly,
      });

      onProgress?.call('preparingData', 0.0);
      await _historyRecorder.ensureTableExists();

      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return Err(FileServiceException(
          'Project not found: ${projectResult.unwrapErr()}',
        ));
      }

      final project = projectResult.unwrap();

      if (languageCodes.isEmpty) {
        return Err(FileServiceException(
          'TMX export requires at least one target language',
        ));
      }

      onProgress?.call('collectingData', 0.1);

      const sourceLanguage = 'en';
      int totalEntries = 0;
      final outputPaths = <String>[];

      for (var i = 0; i < languageCodes.length; i++) {
        final targetLanguage = languageCodes[i];
        onProgress?.call(
          'collectingData',
          0.1 + (0.7 * (i / languageCodes.length)),
          currentLanguage: targetLanguage,
          currentIndex: i,
          total: languageCodes.length,
        );

        final translations = await _dataCollector.fetchTranslationsForLanguage(
          projectId: projectId,
          languageCode: targetLanguage,
          validatedOnly: validatedOnly,
        );

        if (translations.isEmpty) {
          _logger.warning('No translations found for language', {
            'language': targetLanguage,
          });
          continue;
        }

        final tmxEntries = translations
            .map((t) =>
                t.toTmxEntry(targetLanguageId: targetLanguage))
            .toList();

        final tmxPath = languageCodes.length == 1
            ? outputPath
            : outputPath.replaceAll('.tmx', '_$targetLanguage.tmx');

        final exportResult = await _tmxService.exportToTmx(
          filePath: tmxPath,
          entries: tmxEntries,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );

        if (exportResult.isErr) {
          _logger.error('Failed to export TMX for language', {
            'language': targetLanguage,
            'error': exportResult.error.toString(),
          });
          continue;
        }

        outputPaths.add(tmxPath);
        totalEntries += tmxEntries.length;

        final tmxFile = File(tmxPath);
        if (await tmxFile.exists()) {
          await _historyRecorder.recordExport(
            projectId: projectId,
            languageCodes: [targetLanguage],
            format: ExportFormat.tmx,
            validatedOnly: validatedOnly,
            outputPath: tmxPath,
            fileSize: await tmxFile.length(),
            entryCount: tmxEntries.length,
          );
        }
      }

      if (outputPaths.isEmpty) {
        return Err(FileServiceException(
          'No TMX files were successfully exported',
        ));
      }

      onProgress?.call('completed', 1.0);

      _logger.info('TMX export completed', {
        'outputPaths': outputPaths,
        'totalEntries': totalEntries,
      });

      return Ok(ExportResult(
        outputPath: outputPaths.first,
        entryCount: totalEntries,
        fileSize: await File(outputPaths.first).length(),
        languageCodes: languageCodes,
      ));
    } catch (e, stackTrace) {
      _logger.error('Failed to export TMX', e, stackTrace);
      return Err(FileServiceException(
        'Failed to export TMX: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Common implementation for CSV and Excel exports
  Future<Result<ExportResult, FileServiceException>> _exportToTabular({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    required ExportFormat format,
    ExportProgressCallback? onProgress,
  }) async {
    try {
      final formatName = format == ExportFormat.csv ? 'CSV' : 'Excel';
      _logger.info('Starting $formatName export', {
        'projectId': projectId,
        'languages': languageCodes,
        'outputPath': outputPath,
        'validatedOnly': validatedOnly,
      });

      onProgress?.call('preparingData', 0.0);
      await _historyRecorder.ensureTableExists();

      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return Err(FileServiceException(
          'Project not found: ${projectResult.unwrapErr()}',
        ));
      }

      onProgress?.call('collectingData', 0.1);

      final translationsByLanguage =
          await _dataCollector.collectTranslationsForLanguages(
        projectId: projectId,
        languageCodes: languageCodes,
        validatedOnly: validatedOnly,
        onLanguageProgress: (lang, i, total) {
          onProgress?.call(
            'collectingData',
            0.1 + (0.6 * (i / total)),
            currentLanguage: lang,
            currentIndex: i,
            total: total,
          );
        },
      );

      final data = _dataCollector.flattenForTabularExport(translationsByLanguage);
      final totalEntries = data.length;

      if (data.isEmpty) {
        return Err(FileServiceException('No translations found to export'));
      }

      onProgress?.call('writingFile', 0.7);
      await File(outputPath).parent.create(recursive: true);

      final headers = [
        'key',
        'source_text',
        ...languageCodes.map((code) => 'translated_text_$code'),
        'status',
        'language',
      ];

      Result<String, ExportException> writeResult;
      if (format == ExportFormat.csv) {
        writeResult = await _fileImportExportService.exportToCsv(
          data: data,
          filePath: outputPath,
          headers: headers,
        );
      } else {
        writeResult = await _fileImportExportService.exportToExcel(
          data: data,
          filePath: outputPath,
          sheetName: 'Translations',
          headers: headers,
        );
      }

      if (writeResult.isErr) {
        return Err(FileServiceException(
          'Failed to write $formatName file: ${writeResult.unwrapErr().message}',
        ));
      }

      final fileSize = await File(outputPath).length();

      onProgress?.call('finalizing', 0.9);

      await _historyRecorder.recordExport(
        projectId: projectId,
        languageCodes: languageCodes,
        format: format,
        validatedOnly: validatedOnly,
        outputPath: outputPath,
        fileSize: fileSize,
        entryCount: totalEntries,
      );

      onProgress?.call('completed', 1.0);

      _logger.info('$formatName export completed', {
        'outputPath': outputPath,
        'entries': totalEntries,
        'fileSize': fileSize,
      });

      return Ok(ExportResult(
        outputPath: outputPath,
        entryCount: totalEntries,
        fileSize: fileSize,
        languageCodes: languageCodes,
      ));
    } catch (e, stackTrace) {
      final formatName = format == ExportFormat.csv ? 'CSV' : 'Excel';
      _logger.error('Failed to export $formatName', e, stackTrace);
      return Err(FileServiceException(
        'Failed to export $formatName: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Validate project exists and get associated game installation
  Future<Result<(dynamic project, dynamic gameInstallation), FileServiceException>>
      _validateProjectAndGame(String projectId) async {
    final projectResult = await _projectRepository.getById(projectId);
    if (projectResult.isErr) {
      return Err(FileServiceException(
        'Project not found: ${projectResult.unwrapErr()}',
      ));
    }

    final project = projectResult.unwrap();

    final gameInstallationResult =
        await _gameInstallationRepository.getById(project.gameInstallationId);
    if (gameInstallationResult.isErr) {
      return Err(FileServiceException(
        'Game installation not found: ${gameInstallationResult.unwrapErr()}',
      ));
    }

    final gameInstallation = gameInstallationResult.unwrap();
    if (gameInstallation.installationPath == null ||
        gameInstallation.installationPath!.isEmpty) {
      return Err(FileServiceException(
        'Game installation path not configured for ${gameInstallation.gameName}',
      ));
    }

    return Ok((project, gameInstallation));
  }
}
