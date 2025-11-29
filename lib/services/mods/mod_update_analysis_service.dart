import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Data for a unit extracted from pack file
class _PackUnitData {
  final String key;
  final String sourceText;
  final String? sourceLocFile;

  const _PackUnitData({
    required this.key,
    required this.sourceText,
    this.sourceLocFile,
  });
}

/// Result of applying mod update changes
class ModUpdateApplyResult {
  /// Number of source texts updated in translation units
  final int sourceTextsUpdated;

  /// Number of translation versions reset to pending status
  final int translationsReset;

  const ModUpdateApplyResult({
    required this.sourceTextsUpdated,
    required this.translationsReset,
  });
}

/// Service for analyzing changes between a mod's pack file and existing project translations
class ModUpdateAnalysisService {
  final IRpfmService _rpfmService;
  final ILocalizationParser _locParser;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _languageRepository;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  ModUpdateAnalysisService({
    required IRpfmService rpfmService,
    required ILocalizationParser locParser,
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required ProjectLanguageRepository languageRepository,
  })  : _rpfmService = rpfmService,
        _locParser = locParser,
        _unitRepository = unitRepository,
        _versionRepository = versionRepository,
        _languageRepository = languageRepository;

  /// Analyze changes between pack file and existing project translations
  ///
  /// Returns analysis of:
  /// - New keys added in the pack
  /// - Keys removed from the pack
  /// - Keys with modified source text
  Future<Result<ModUpdateAnalysis, ServiceException>> analyzeChanges({
    required String projectId,
    required String packFilePath,
  }) async {
    try {
      // Step 1: Get existing translation units from database
      final existingUnitsResult = await _unitRepository.getActive(projectId);
      if (existingUnitsResult.isErr) {
        return Err(ServiceException(
          'Failed to get existing translation units: ${existingUnitsResult.error}',
        ));
      }

      final existingUnits = existingUnitsResult.value;
      final existingUnitsMap = <String, TranslationUnit>{};
      for (final unit in existingUnits) {
        existingUnitsMap[unit.key] = unit;
      }

      // Step 2: Extract and parse pack file
      final packUnitsResult = await _extractPackUnits(packFilePath);
      if (packUnitsResult.isErr) {
        return Err(packUnitsResult.error);
      }

      final packUnits = packUnitsResult.value;

      // Step 3: Compare and analyze
      final newUnitKeys = <String>[];
      final newUnitsData = <NewUnitData>[];
      final modifiedUnitKeys = <String>[];
      final modifiedSourceTexts = <String, String>{};
      final packKeys = <String>{};

      for (final unitData in packUnits) {
        final key = unitData.key;
        final packSourceText = unitData.sourceText;
        packKeys.add(key);

        final existingUnit = existingUnitsMap[key];
        if (existingUnit == null) {
          // New key - collect complete data
          newUnitKeys.add(key);
          newUnitsData.add(NewUnitData(
            key: key,
            sourceText: packSourceText,
            sourceLocFile: unitData.sourceLocFile,
          ));
        } else if (existingUnit.sourceText != packSourceText) {
          // Modified source text
          modifiedUnitKeys.add(key);
          modifiedSourceTexts[key] = packSourceText;
        }
      }

      // Collect removed units (exist in project but not in pack)
      final removedUnitKeys = <String>[];
      for (final key in existingUnitsMap.keys) {
        if (!packKeys.contains(key)) {
          removedUnitKeys.add(key);
        }
      }

      final analysis = ModUpdateAnalysis(
        newUnitsCount: newUnitKeys.length,
        removedUnitsCount: removedUnitKeys.length,
        modifiedUnitsCount: modifiedUnitKeys.length,
        totalPackUnits: packUnits.length,
        totalProjectUnits: existingUnits.length,
        newUnitKeys: newUnitKeys,
        newUnitsData: newUnitsData,
        removedUnitKeys: removedUnitKeys,
        modifiedUnitKeys: modifiedUnitKeys,
        modifiedSourceTexts: modifiedSourceTexts,
      );

      // Log analysis results for debugging
      if (analysis.hasChanges) {
        _logger.info(
          'ModUpdateAnalysis for project $projectId: '
          '+${analysis.newUnitsCount} new, -${analysis.removedUnitsCount} removed, ~${analysis.modifiedUnitsCount} modified '
          '(pack: ${packUnits.length}, project: ${existingUnits.length})',
        );
      }

      return Ok(analysis);
    } catch (e, stackTrace) {
      _logger.error('Failed to analyze mod changes', e, stackTrace);
      return Err(ServiceException(
        'Failed to analyze mod changes: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Extract all translation units from a pack file
  Future<Result<List<_PackUnitData>, ServiceException>> _extractPackUnits(
    String packFilePath,
  ) async {
    // Extract .loc files as TSV
    final extractResult = await _rpfmService.extractLocalizationFilesAsTsv(
      packFilePath,
    );

    if (extractResult.isErr) {
      return Err(ServiceException(
        'Failed to extract .loc files: ${extractResult.error}',
      ));
    }

    final extraction = extractResult.value;
    final locFiles = extraction.extractedFiles;

    if (locFiles.isEmpty) {
      return const Ok([]);
    }

    final allUnits = <_PackUnitData>[];
    final seenKeys = <String>{};

    // Parse each TSV file
    for (final tsvFilePath in locFiles) {
      final parseResult = await _locParser.parseFile(
        filePath: tsvFilePath,
        encoding: 'utf-8',
      );

      if (parseResult.isErr) {
        continue;
      }

      // Extract the original .loc file path relative to extraction directory
      // TSV path: C:\temp\rpfm_extract_xxx\text\db\something.loc.tsv
      // Extraction dir: C:\temp\rpfm_extract_xxx
      // Result: text/db/something.loc
      String sourceLocFile = tsvFilePath
          .replaceAll('\\', '/')
          .replaceFirst('${extraction.outputDirectory.replaceAll('\\', '/')}/', '');

      // Remove .tsv extension to get the original .loc path
      if (sourceLocFile.endsWith('.tsv')) {
        sourceLocFile = sourceLocFile.substring(0, sourceLocFile.length - 4);
      }

      final locFile = parseResult.value;
      for (final entry in locFile.entries) {
        // Avoid duplicates (same key from different loc files)
        if (!seenKeys.contains(entry.key)) {
          seenKeys.add(entry.key);
          allUnits.add(_PackUnitData(
            key: entry.key,
            sourceText: entry.value,
            sourceLocFile: sourceLocFile,
          ));
        }
      }
    }

    // Clean up extraction directory
    try {
      final extractionDir = Directory(extraction.outputDirectory);
      if (await extractionDir.exists()) {
        await extractionDir.delete(recursive: true);
      }
    } catch (e) {
      // Non-critical - cleanup can fail without issue
    }

    return Ok(allUnits);
  }

  /// Apply changes from a mod update analysis to the project.
  ///
  /// For modified units (source text changed):
  /// 1. Updates the source_text in translation_units table
  /// 2. Resets the status to 'pending' for ALL translation versions (all languages)
  ///
  /// This ensures that translators will review units where the source changed.
  ///
  /// Note: This method does NOT handle new or removed units - those require
  /// a full re-import process.
  ///
  /// [projectId] - The project to update
  /// [analysis] - The analysis result containing modified keys and new source texts
  ///
  /// Returns [ModUpdateApplyResult] with counts of affected records.
  Future<Result<ModUpdateApplyResult, ServiceException>> applyModifiedSourceTexts({
    required String projectId,
    required ModUpdateAnalysis analysis,
  }) async {
    try {
      if (!analysis.hasModifiedUnits) {
        return Ok(const ModUpdateApplyResult(
          sourceTextsUpdated: 0,
          translationsReset: 0,
        ));
      }

      _logger.info(
        'Applying ${analysis.modifiedUnitsCount} source text changes for project $projectId',
      );

      // Step 1: Update source texts in translation_units
      final updateResult = await _unitRepository.updateSourceTexts(
        projectId: projectId,
        sourceTextUpdates: analysis.modifiedSourceTexts,
      );

      if (updateResult.isErr) {
        return Err(ServiceException(
          'Failed to update source texts: ${updateResult.error}',
        ));
      }

      final sourceTextsUpdated = updateResult.value;

      // Step 2: Reset status to pending for all translation versions of modified units
      final resetResult = await _versionRepository.resetStatusForUnitKeys(
        projectId: projectId,
        unitKeys: analysis.modifiedUnitKeys,
      );

      if (resetResult.isErr) {
        return Err(ServiceException(
          'Failed to reset translation statuses: ${resetResult.error}',
        ));
      }

      final translationsReset = resetResult.value;

      _logger.info(
        'Applied mod update: $sourceTextsUpdated source texts updated, '
        '$translationsReset translation versions reset to pending',
      );

      return Ok(ModUpdateApplyResult(
        sourceTextsUpdated: sourceTextsUpdated,
        translationsReset: translationsReset,
      ));
    } catch (e, stackTrace) {
      _logger.error('Failed to apply mod update changes', e, stackTrace);
      return Err(ServiceException(
        'Failed to apply mod update changes: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Add new translation units from a mod update.
  ///
  /// For new units (present in pack but not in project):
  /// 1. Creates TranslationUnit records with the source text
  /// 2. Creates TranslationVersion records for each project language with status 'pending'
  ///
  /// [projectId] - The project to add units to
  /// [analysis] - The analysis result containing new unit data
  ///
  /// Returns the count of new units added.
  Future<Result<int, ServiceException>> addNewUnits({
    required String projectId,
    required ModUpdateAnalysis analysis,
  }) async {
    try {
      if (!analysis.hasNewUnits || analysis.newUnitsData.isEmpty) {
        return Ok(0);
      }

      _logger.info(
        'Adding ${analysis.newUnitsCount} new units for project $projectId',
      );

      // Get project languages for creating translation versions
      final languagesResult = await _languageRepository.getByProject(projectId);
      if (languagesResult.isErr) {
        return Err(ServiceException(
          'Failed to get project languages: ${languagesResult.error}',
        ));
      }

      final languages = languagesResult.value;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int unitsAdded = 0;

      for (final newUnit in analysis.newUnitsData) {
        // Check if unit already exists (shouldn't happen but safety check)
        final existingResult = await _unitRepository.getByKey(projectId, newUnit.key);
        if (existingResult.isOk) {
          _logger.debug('Unit already exists, skipping: ${newUnit.key}');
          continue;
        }

        // Create translation unit
        final unit = TranslationUnit(
          id: _uuid.v4(),
          projectId: projectId,
          key: newUnit.key,
          sourceText: newUnit.sourceText,
          context: null,
          notes: null,
          sourceLocFile: newUnit.sourceLocFile,
          isObsolete: false,
          createdAt: now,
          updatedAt: now,
        );

        final insertResult = await _unitRepository.insert(unit);
        if (insertResult.isErr) {
          _logger.warning('Failed to insert new unit: ${newUnit.key}');
          continue;
        }

        // Create translation versions for all project languages
        for (final language in languages) {
          final version = TranslationVersion(
            id: _uuid.v4(),
            unitId: unit.id,
            projectLanguageId: language.id,
            translatedText: null,
            isManuallyEdited: false,
            status: TranslationVersionStatus.pending,
            confidenceScore: null,
            validationIssues: null,
            createdAt: now,
            updatedAt: now,
          );

          final versionResult = await _versionRepository.insert(version);
          if (versionResult.isErr) {
            _logger.warning(
              'Failed to insert translation version for unit ${unit.id}, language ${language.id}',
            );
          }
        }

        unitsAdded++;
      }

      _logger.info('Added $unitsAdded new units for project $projectId');
      return Ok(unitsAdded);
    } catch (e, stackTrace) {
      _logger.error('Failed to add new units', e, stackTrace);
      return Err(ServiceException(
        'Failed to add new units: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }
}

