import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/export_history_repository.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

/// Export progress callback
typedef ExportProgressCallback = void Function(
  String step,
  double progress,
  {String? currentLanguage, int? currentIndex, int? total}
);

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
  final ExportHistoryRepository _exportHistoryRepository;
  final GameInstallationRepository _gameInstallationRepository;
  final ProjectRepository _projectRepository;
  final ProjectLanguageRepository _projectLanguageRepository;
  final TranslationUnitRepository _translationUnitRepository;
  final TranslationVersionRepository _translationVersionRepository;
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
        _exportHistoryRepository = exportHistoryRepository,
        _gameInstallationRepository = gameInstallationRepository,
        _projectRepository = projectRepository,
        _projectLanguageRepository = projectLanguageRepository,
        _translationUnitRepository = translationUnitRepository,
        _translationVersionRepository = translationVersionRepository,
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

      // Ensure export history table exists
      await _exportHistoryRepository.ensureTableExists();

      // Get project
      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return Err(FileServiceException(
          'Project not found: ${projectResult.unwrapErr()}',
        ));
      }

      final project = projectResult.unwrap();

      // Get game installation to determine data folder path
      final gameInstallationResult = await _gameInstallationRepository.getById(
        project.gameInstallationId,
      );
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

      // Export to game's data folder
      final gameDataPath = path.join(gameInstallation.installationPath!, 'data');

      // Create temporary directory for TSV files
      final systemTempDir = Directory.systemTemp;
      final tempDirPath = path.join(
        systemTempDir.path,
        'twmt_pack_export_${DateTime.now().millisecondsSinceEpoch}',
      );
      tempDir = await Directory(tempDirPath).create(recursive: true);

      // Generate TSV files grouped by source .loc file for each language
      // TSV format is used because RPFM-CLI can convert it to binary .loc
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

        // Generate multiple TSV files grouped by source .loc file
        final result = await _locFileService.generateLocFilesGroupedBySource(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: validatedOnly,
        );

        if (result is Err) {
          return Err(result.error);
        }

        final generatedTsvPaths = (result as Ok<List<String>, FileServiceException>).value;

        // Copy each TSV file to pack structure directory
        // The TSV filename encodes the internal pack path (with __ as separator)
        // e.g.: text__db__!!!!!!!!!!_FR_something.loc.tsv
        for (final generatedTsvPath in generatedTsvPaths) {
          final tsvFile = File(generatedTsvPath);
          final tsvFileName = path.basename(generatedTsvPath);
          
          // Reconstruct the directory structure from the filename
          // text__db__!!!!!!!!!!_FR_something.loc.tsv -> text/db/!!!!!!!!!!_FR_something.loc.tsv
          final internalPath = tsvFileName.replaceAll('__', '/');
          final targetDir = path.dirname(internalPath);
          final targetDirPath = path.join(tempDir.path, targetDir);
          await Directory(targetDirPath).create(recursive: true);
          
          final targetPath = path.join(tempDir.path, internalPath);
          await tsvFile.copy(targetPath);

          _logger.info('TSV file prepared for pack', {
            'source': generatedTsvPath,
            'target': targetPath,
            'internalPath': internalPath,
          });
        }

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

      // Ensure game data directory exists
      final dataDir = Directory(gameDataPath);
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }

      // Generate pack file name with prefix for load order priority
      // Use the original pack filename from source_file_path instead of project name
      // Format: !!!!!!!!!!_{LANG}_{original_pack_name}.pack
      final languageCode = languageCodes.first.toUpperCase();
      final originalPackName = _extractOriginalPackName(project.sourceFilePath);
      final packFileName =
          '!!!!!!!!!!_${languageCode}_$originalPackName.pack';
      final packPath = path.join(gameDataPath, packFileName);

      // Create pack (RPFM requires the first language code)
      final packResult = await _rpfmService.createPack(
        inputDirectory: tempDir.path,
        outputPackPath: packPath,
        languageCode: languageCodes.first,
      );

      if (packResult is Err) {
        return Err(FileServiceException(
          'Failed to create .pack file: ${packResult.error}',
        ));
      }

      // Get file size
      final packFile = File(packPath);
      final fileSize = await packFile.length();

      onProgress?.call('finalizing', 0.9);

      // Record export history
      await _recordExportHistory(
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
      // Clean up temporary directory
      if (tempDir != null && await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (e) {
          _logger.warning('Failed to delete temporary directory', {
            'path': tempDir.path,
            'error': e.toString(),
          });
        }
      }
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
    try {
      _logger.info('Starting CSV export', {
        'projectId': projectId,
        'languages': languageCodes,
        'outputPath': outputPath,
        'validatedOnly': validatedOnly,
      });

      onProgress?.call('preparingData', 0.0);

      // Ensure export history table exists
      await _exportHistoryRepository.ensureTableExists();

      // Validate project exists
      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return Err(FileServiceException(
          'Project not found: ${projectResult.unwrapErr()}',
        ));
      }

      // Prepare data for CSV export
      final data = <Map<String, String>>[];
      int totalEntries = 0;

      onProgress?.call('collectingData', 0.1);

      // For each language, get translations
      for (var i = 0; i < languageCodes.length; i++) {
        final languageCode = languageCodes[i];

        onProgress?.call(
          'collectingData',
          0.1 + (0.6 * (i / languageCodes.length)),
          currentLanguage: languageCode,
          currentIndex: i,
          total: languageCodes.length,
        );

        // Get translations for this language via FileImportExportService
        final translations = await _fetchTranslationsForLanguage(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: validatedOnly,
        );

        for (final translation in translations) {
          data.add({
            'key': translation['key'] ?? '',
            'source_text': translation['source_text'] ?? '',
            'translated_text_$languageCode': translation['translated_text'] ?? '',
            'status': translation['status'] ?? '',
            'language': languageCode,
          });
          totalEntries++;
        }
      }

      if (data.isEmpty) {
        return Err(FileServiceException(
          'No translations found to export',
        ));
      }

      onProgress?.call('writingFile', 0.7);

      // Ensure output directory exists
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);

      // Export to CSV using FileImportExportService
      final csvResult = await _fileImportExportService.exportToCsv(
        data: data,
        filePath: outputPath,
        headers: ['key', 'source_text', ...languageCodes.map((code) => 'translated_text_$code'), 'status', 'language'],
      );

      if (csvResult.isErr) {
        return Err(FileServiceException(
          'Failed to write CSV file: ${csvResult.unwrapErr()}',
        ));
      }

      // Get file size
      final file = File(outputPath);
      final fileSize = await file.length();

      onProgress?.call('finalizing', 0.9);

      // Record export history
      await _recordExportHistory(
        projectId: projectId,
        languageCodes: languageCodes,
        format: ExportFormat.csv,
        validatedOnly: validatedOnly,
        outputPath: outputPath,
        fileSize: fileSize,
        entryCount: totalEntries,
      );

      onProgress?.call('completed', 1.0);

      _logger.info('CSV export completed', {
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
      _logger.error('Failed to export CSV', e, stackTrace);

      return Err(FileServiceException(
        'Failed to export CSV: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Export translations to Excel file
  Future<Result<ExportResult, FileServiceException>> exportToExcel({
    required String projectId,
    required List<String> languageCodes,
    required String outputPath,
    required bool validatedOnly,
    ExportProgressCallback? onProgress,
  }) async {
    try {
      _logger.info('Starting Excel export', {
        'projectId': projectId,
        'languages': languageCodes,
        'outputPath': outputPath,
        'validatedOnly': validatedOnly,
      });

      onProgress?.call('preparingData', 0.0);

      // Ensure export history table exists
      await _exportHistoryRepository.ensureTableExists();

      // Validate project exists
      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return Err(FileServiceException(
          'Project not found: ${projectResult.unwrapErr()}',
        ));
      }

      // Prepare data for Excel export
      final data = <Map<String, String>>[];
      int totalEntries = 0;

      onProgress?.call('collectingData', 0.1);

      // For each language, get translations
      for (var i = 0; i < languageCodes.length; i++) {
        final languageCode = languageCodes[i];

        onProgress?.call(
          'collectingData',
          0.1 + (0.6 * (i / languageCodes.length)),
          currentLanguage: languageCode,
          currentIndex: i,
          total: languageCodes.length,
        );

        // Get translations for this language
        final translations = await _fetchTranslationsForLanguage(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: validatedOnly,
        );

        for (final translation in translations) {
          data.add({
            'key': translation['key'] ?? '',
            'source_text': translation['source_text'] ?? '',
            'translated_text_$languageCode': translation['translated_text'] ?? '',
            'status': translation['status'] ?? '',
            'language': languageCode,
          });
          totalEntries++;
        }
      }

      if (data.isEmpty) {
        return Err(FileServiceException(
          'No translations found to export',
        ));
      }

      onProgress?.call('writingFile', 0.7);

      // Ensure output directory exists
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);

      // Export to Excel using FileImportExportService
      final excelResult = await _fileImportExportService.exportToExcel(
        data: data,
        filePath: outputPath,
        sheetName: 'Translations',
        headers: ['key', 'source_text', ...languageCodes.map((code) => 'translated_text_$code'), 'status', 'language'],
      );

      if (excelResult.isErr) {
        return Err(FileServiceException(
          'Failed to write Excel file: ${excelResult.unwrapErr()}',
        ));
      }

      // Get file size
      final file = File(outputPath);
      final fileSize = await file.length();

      onProgress?.call('finalizing', 0.9);

      // Record export history
      await _recordExportHistory(
        projectId: projectId,
        languageCodes: languageCodes,
        format: ExportFormat.excel,
        validatedOnly: validatedOnly,
        outputPath: outputPath,
        fileSize: fileSize,
        entryCount: totalEntries,
      );

      onProgress?.call('completed', 1.0);

      _logger.info('Excel export completed', {
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
      _logger.error('Failed to export Excel', e, stackTrace);

      return Err(FileServiceException(
        'Failed to export Excel: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
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

      // Ensure export history table exists
      await _exportHistoryRepository.ensureTableExists();

      // Get project
      final projectResult = await _projectRepository.getById(projectId);
      if (projectResult.isErr) {
        return Err(FileServiceException(
          'Project not found: ${projectResult.unwrapErr()}',
        ));
      }

      final project = projectResult.unwrap();

      // TMX requires exactly 2 languages (source and target)
      if (languageCodes.isEmpty) {
        return Err(FileServiceException(
          'TMX export requires at least one target language',
        ));
      }

      onProgress?.call('collectingData', 0.1);

      // Get source language (Total War mods are typically in English)
      final sourceLanguage = 'en';

      // For each target language, create a separate TMX file
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

        // Get translations for this language pair
        final translations = await _fetchTranslationsForLanguage(
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

        // Convert to TMX entries
        final tmxEntries = translations.map((t) {
          return TranslationMemoryEntry(
            id: t['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
            sourceText: t['source_text'] ?? '',
            translatedText: t['translated_text'] ?? '',
            targetLanguageId: targetLanguage,
            sourceHash: (t['source_text'] ?? '').hashCode.toString(),
            qualityScore: null,
            usageCount: 0,
            gameContext: project.name,
            translationProviderId: null,
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            lastUsedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }).toList();

        // Determine output path for this language
        final tmxPath = languageCodes.length == 1
            ? outputPath
            : outputPath.replaceAll('.tmx', '_$targetLanguage.tmx');

        // Export to TMX using TmxService
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

        // Get file size
        final tmxFile = File(tmxPath);
        if (await tmxFile.exists()) {
          // Record export history for this language
          await _recordExportHistory(
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

  /// Record export operation in history
  Future<void> _recordExportHistory({
    required String projectId,
    required List<String> languageCodes,
    required ExportFormat format,
    required bool validatedOnly,
    required String outputPath,
    required int fileSize,
    required int entryCount,
  }) async {
    try {
      final history = ExportHistory(
        id: const Uuid().v4(),
        projectId: projectId,
        languages: jsonEncode(languageCodes),
        format: format,
        validatedOnly: validatedOnly,
        outputPath: outputPath,
        fileSize: fileSize,
        entryCount: entryCount,
        exportedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await _exportHistoryRepository.insert(history);

      _logger.info('Export history recorded', {
        'id': history.id,
        'format': format.toString(),
      });
    } catch (e, stackTrace) {
      _logger.error('Failed to record export history', e, stackTrace);
      // Don't fail the export if history recording fails
    }
  }

  /// Extract original pack filename from source file path
  ///
  /// Extracts just the pack name (without extension) from the full path.
  /// Example: "C:\Games\Steam\...\something.pack" -> "something"
  String _extractOriginalPackName(String? sourceFilePath) {
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      return 'translation';
    }
    
    // Get just the filename
    final fileName = path.basename(sourceFilePath);
    
    // Remove .pack extension if present
    if (fileName.toLowerCase().endsWith('.pack')) {
      return fileName.substring(0, fileName.length - 5);
    }
    
    return fileName;
  }

  /// Fetch translations for a specific language from the database
  ///
  /// Returns a list of maps containing translation data suitable for export.
  Future<List<Map<String, String>>> _fetchTranslationsForLanguage({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  }) async {
    try {
      // Get project language entity
      final projectLanguageResult =
          await _projectLanguageRepository.getByProjectAndLanguage(
        projectId,
        languageCode,
      );

      if (projectLanguageResult.isErr) {
        _logger.warning('Project language not found', {
          'projectId': projectId,
          'languageCode': languageCode,
        });
        return [];
      }

      final projectLanguage = projectLanguageResult.unwrap();

      // Get all translation units for the project
      final unitsResult = await _translationUnitRepository.getActive(projectId);

      if (unitsResult.isErr) {
        _logger.error('Failed to fetch translation units', unitsResult.unwrapErr());
        return [];
      }

      final units = unitsResult.unwrap();
      final translations = <Map<String, String>>[];

      // For each unit, get its translation version
      for (final unit in units) {
        final versionResult =
            await _translationVersionRepository.getByUnitAndProjectLanguage(
          unitId: unit.id,
          projectLanguageId: projectLanguage.id,
        );

        if (versionResult.isErr) {
          // No translation for this unit, skip
          continue;
        }

        final version = versionResult.unwrap();

        // If validatedOnly is true, only include validated translations
        if (validatedOnly && !version.isApproved && !version.isReviewed) {
          continue;
        }

        // Skip if no translated text
        if (version.translatedText == null || version.translatedText!.isEmpty) {
          continue;
        }

        translations.add({
          'id': version.id,
          'key': unit.key,
          'source_text': unit.sourceText,
          'translated_text': version.translatedText!,
          'status': version.status.toString().split('.').last,
        });
      }

      return translations;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch translations for language', e, stackTrace);
      return [];
    }
  }
}
