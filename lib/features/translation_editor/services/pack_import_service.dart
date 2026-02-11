import 'dart:async';
import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/localization_parser_impl.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Result of a pack import preview operation
class PackImportPreview {
  /// Entries that can be imported (key exists in project)
  final List<PackImportEntry> matchingEntries;

  /// Entries that cannot be imported (key not found in project)
  final List<LocalizationEntry> unmatchedEntries;

  /// Total entries found in the pack
  final int totalEntriesInPack;

  /// Path to the source pack file
  final String packFilePath;

  const PackImportPreview({
    required this.matchingEntries,
    required this.unmatchedEntries,
    required this.totalEntriesInPack,
    required this.packFilePath,
  });

  int get matchingCount => matchingEntries.length;
  int get unmatchedCount => unmatchedEntries.length;

  /// Entries that will overwrite existing translations
  List<PackImportEntry> get entriesWithConflicts =>
      matchingEntries.where((e) => e.hasExistingTranslation).toList();

  /// Entries that will be added as new translations
  List<PackImportEntry> get entriesWithoutConflicts =>
      matchingEntries.where((e) => !e.hasExistingTranslation).toList();
}

/// A single entry that can be imported from a pack
class PackImportEntry {
  /// The translation unit this entry matches
  final TranslationUnit unit;

  /// The existing translation version (if any)
  final TranslationVersion? existingVersion;

  /// The value from the pack file
  final String importedValue;

  /// The key from the pack file
  final String key;

  const PackImportEntry({
    required this.unit,
    required this.existingVersion,
    required this.importedValue,
    required this.key,
  });

  bool get hasExistingTranslation =>
      existingVersion?.translatedText != null &&
      existingVersion!.translatedText!.isNotEmpty;

  String? get existingTranslation => existingVersion?.translatedText;

  /// Whether the imported value is different from existing
  bool get valuesDiffer =>
      hasExistingTranslation && existingTranslation != importedValue;
}

/// Result of a pack import execution
class PackImportResult {
  final int importedCount;
  final int skippedCount;
  final int errorCount;
  final List<String> errors;

  const PackImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.errorCount,
    required this.errors,
  });

  bool get hasErrors => errorCount > 0;
  int get totalProcessed => importedCount + skippedCount + errorCount;
}

/// Service for importing translations from .pack files
class PackImportService {
  final IRpfmService _rpfmService;
  final LocalizationParserImpl _localizationParser;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _projectLanguageRepository;
  final LoggingService _logger;

  PackImportService({
    required IRpfmService rpfmService,
    required LocalizationParserImpl localizationParser,
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required ProjectLanguageRepository projectLanguageRepository,
    required LoggingService logger,
  })  : _rpfmService = rpfmService,
        _localizationParser = localizationParser,
        _unitRepository = unitRepository,
        _versionRepository = versionRepository,
        _projectLanguageRepository = projectLanguageRepository,
        _logger = logger;

  /// Preview what can be imported from a pack file
  ///
  /// Extracts localization files from the pack and matches entries
  /// against the project's translation units.
  Future<Result<PackImportPreview, String>> previewImport({
    required String packFilePath,
    required String projectId,
    required String languageId,
  }) async {
    try {
      _logger.info('Starting pack import preview from: $packFilePath');

      // Validate pack file exists
      if (!await File(packFilePath).exists()) {
        return const Err('Pack file does not exist');
      }

      // Get project language ID
      final projectLanguageResult =
          await _projectLanguageRepository.getByProject(projectId);
      if (projectLanguageResult.isErr) {
        return Err(
            'Failed to retrieve project languages: ${projectLanguageResult.unwrapErr()}');
      }

      final projectLanguages = projectLanguageResult.unwrap();
      final projectLanguage = projectLanguages
          .where((pl) => pl.languageId == languageId)
          .firstOrNull;

      if (projectLanguage == null) {
        return const Err('Project language not found');
      }

      // Extract localization files from pack as TSV (same format used for project initialization)
      _logger.info('Extracting localization files from pack...');
      final extractResult =
          await _rpfmService.extractLocalizationFilesAsTsv(packFilePath);

      if (extractResult.isErr) {
        return Err(
            'Failed to extract pack: ${extractResult.unwrapErr().message}');
      }

      final extractInfo = extractResult.unwrap();

      if (extractInfo.extractedFiles.isEmpty) {
        return const Err(
            'No localization files found in the pack');
      }

      // Parse all extracted localization files
      final allEntries = <LocalizationEntry>[];

      for (final filePath in extractInfo.extractedFiles) {
        final parseResult = await _localizationParser.parseFile(
          filePath: filePath,
        );

        if (parseResult.isOk) {
          allEntries.addAll(parseResult.unwrap().entries);
        } else {
          _logger.warning('Failed to parse file: $filePath');
        }
      }

      if (allEntries.isEmpty) {
        return const Err(
            'No localization entries found in the pack');
      }

      _logger.info('Found ${allEntries.length} entries in pack');

      // Get all translation units for the project
      final unitsResult = await _unitRepository.getByProject(projectId);
      if (unitsResult.isErr) {
        return Err(
            'Failed to retrieve translation units: ${unitsResult.unwrapErr()}');
      }

      final units = unitsResult.unwrap();
      final unitsByKey = {for (var u in units) u.key: u};

      _logger.info('Project has ${units.length} translation units');

      // Get existing versions for this language
      final versionsResult =
          await _versionRepository.getByProjectLanguage(projectLanguage.id);
      final existingVersions = versionsResult.isOk ? versionsResult.unwrap() : <TranslationVersion>[];
      final versionsByUnitId = {for (var v in existingVersions) v.unitId: v};

      // Match entries with project units
      final matchingEntries = <PackImportEntry>[];
      final unmatchedEntries = <LocalizationEntry>[];

      for (final entry in allEntries) {
        final unit = unitsByKey[entry.key];

        if (unit != null) {
          matchingEntries.add(PackImportEntry(
            unit: unit,
            existingVersion: versionsByUnitId[unit.id],
            importedValue: entry.value,
            key: entry.key,
          ));
        } else {
          unmatchedEntries.add(entry);
        }
      }

      _logger.info(
          'Matched ${matchingEntries.length} entries, ${unmatchedEntries.length} unmatched');

      // Cleanup temp directory
      try {
        await Directory(extractInfo.outputDirectory).delete(recursive: true);
      } catch (e) {
        _logger.warning('Failed to cleanup temp directory: $e');
      }

      return Ok(PackImportPreview(
        matchingEntries: matchingEntries,
        unmatchedEntries: unmatchedEntries,
        totalEntriesInPack: allEntries.length,
        packFilePath: packFilePath,
      ));
    } catch (e, stackTrace) {
      _logger.error('Pack import preview failed: $e', e, stackTrace);
      return Err('Unexpected error: $e');
    }
  }

  /// Execute the import of selected entries
  ///
  /// [entriesToImport] - List of entries to import
  /// [overwriteExisting] - Whether to overwrite existing translations
  /// [onProgress] - Callback for progress updates (current, total, message)
  /// [isCancelled] - Function to check if import should be cancelled
  Future<Result<PackImportResult, String>> executeImport({
    required List<PackImportEntry> entriesToImport,
    required String projectId,
    required String languageId,
    bool overwriteExisting = true,
    void Function(int current, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      _logger.info('Executing pack import for ${entriesToImport.length} entries');

      // Get project language ID
      final projectLanguageResult =
          await _projectLanguageRepository.getByProject(projectId);
      if (projectLanguageResult.isErr) {
        return Err(
            'Failed to retrieve project languages: ${projectLanguageResult.unwrapErr()}');
      }

      final projectLanguages = projectLanguageResult.unwrap();
      final projectLanguage = projectLanguages
          .where((pl) => pl.languageId == languageId)
          .firstOrNull;

      if (projectLanguage == null) {
        return const Err('Project language not found');
      }

      onProgress?.call(0, entriesToImport.length, 'Preparing import...');

      // Filter entries based on overwriteExisting option
      final entriesToProcess = overwriteExisting
          ? entriesToImport
          : entriesToImport.where((e) => !e.hasExistingTranslation).toList();

      final skippedCount = entriesToImport.length - entriesToProcess.length;

      if (entriesToProcess.isEmpty) {
        _logger.info('No entries to import after filtering');
        return Ok(PackImportResult(
          importedCount: 0,
          skippedCount: skippedCount,
          errorCount: 0,
          errors: [],
        ));
      }

      // Build TranslationVersion entities and existingVersionIds map
      final now = DateTime.now().millisecondsSinceEpoch;
      final entities = <TranslationVersion>[];
      final existingVersionIds = <String, String>{};

      for (final entry in entriesToProcess) {
        if (entry.existingVersion != null) {
          // Update existing version
          existingVersionIds[entry.unit.id] = entry.existingVersion!.id;
          entities.add(entry.existingVersion!.copyWith(
            translatedText: entry.importedValue,
            status: TranslationVersionStatus.translated,
            translationSource: TranslationSource.manual,
            isManuallyEdited: true,
            updatedAt: now,
          ));
        } else {
          // Create new version
          entities.add(TranslationVersion(
            id: '${now}_${entry.unit.id}',
            unitId: entry.unit.id,
            projectLanguageId: projectLanguage.id,
            translatedText: entry.importedValue,
            status: TranslationVersionStatus.translated,
            translationSource: TranslationSource.manual,
            isManuallyEdited: true,
            createdAt: now,
            updatedAt: now,
          ));
        }
      }

      // Use optimized batch import
      final importResult = await _versionRepository.importTranslations(
        entities: entities,
        existingVersionIds: existingVersionIds,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

      if (importResult.isErr) {
        return Err('Import failed: ${importResult.unwrapErr()}');
      }

      final result = importResult.unwrap();
      final importedCount = result.inserted + result.updated;
      final totalSkipped = skippedCount + result.skipped;

      onProgress?.call(
        entriesToImport.length,
        entriesToImport.length,
        'Import complete!',
      );

      _logger.info(
          'Import complete: $importedCount imported (${result.inserted} new, ${result.updated} updated), $totalSkipped skipped');

      return Ok(PackImportResult(
        importedCount: importedCount,
        skippedCount: totalSkipped,
        errorCount: 0,
        errors: [],
      ));
    } catch (e, stackTrace) {
      _logger.error('Pack import execution failed: $e', e, stackTrace);
      return Err('Unexpected error: $e');
    }
  }
}
