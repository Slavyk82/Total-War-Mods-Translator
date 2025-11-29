import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for analyzing changes between a mod's pack file and existing project translations
class ModUpdateAnalysisService {
  final IRpfmService _rpfmService;
  final ILocalizationParser _locParser;
  final TranslationUnitRepository _unitRepository;
  final LoggingService _logger = LoggingService.instance;

  ModUpdateAnalysisService({
    required IRpfmService rpfmService,
    required ILocalizationParser locParser,
    required TranslationUnitRepository unitRepository,
  })  : _rpfmService = rpfmService,
        _locParser = locParser,
        _unitRepository = unitRepository;

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
      int newUnitsCount = 0;
      int modifiedUnitsCount = 0;
      final packKeys = <String>{};

      for (final entry in packUnits.entries) {
        final key = entry.key;
        final packSourceText = entry.value;
        packKeys.add(key);

        final existingUnit = existingUnitsMap[key];
        if (existingUnit == null) {
          // New key
          newUnitsCount++;
        } else if (existingUnit.sourceText != packSourceText) {
          // Modified source text
          modifiedUnitsCount++;
        }
      }

      // Count removed units (exist in project but not in pack)
      int removedUnitsCount = 0;
      for (final key in existingUnitsMap.keys) {
        if (!packKeys.contains(key)) {
          removedUnitsCount++;
        }
      }

      final analysis = ModUpdateAnalysis(
        newUnitsCount: newUnitsCount,
        removedUnitsCount: removedUnitsCount,
        modifiedUnitsCount: modifiedUnitsCount,
        totalPackUnits: packUnits.length,
        totalProjectUnits: existingUnits.length,
      );

      // Log analysis results for debugging
      if (analysis.hasChanges) {
        _logger.info(
          'ModUpdateAnalysis for project $projectId: '
          '+$newUnitsCount new, -$removedUnitsCount removed, ~$modifiedUnitsCount modified '
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
  Future<Result<Map<String, String>, ServiceException>> _extractPackUnits(
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
      return const Ok({});
    }

    final allUnits = <String, String>{};

    // Parse each TSV file
    for (final tsvFilePath in locFiles) {
      final parseResult = await _locParser.parseFile(
        filePath: tsvFilePath,
        encoding: 'utf-8',
      );

      if (parseResult.isErr) {
        continue;
      }

      final locFile = parseResult.value;
      for (final entry in locFile.entries) {
        allUnits[entry.key] = entry.value;
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
}

