import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Total War .loc file service
class LocFileServiceImpl implements ILocFileService {
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _projectLanguageRepository;
  final LoggingService _logger;

  LocFileServiceImpl({
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required ProjectLanguageRepository projectLanguageRepository,
    LoggingService? logger,
  })  : _unitRepository = unitRepository,
        _versionRepository = versionRepository,
        _projectLanguageRepository = projectLanguageRepository,
        _logger = logger ?? LoggingService.instance;

  @override
  Future<Result<String, FileServiceException>> generateLocFile({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  }) async {
    try {
      _logger.info('Generating .loc file', {
        'projectId': projectId,
        'languageCode': languageCode,
        'validatedOnly': validatedOnly,
      });

      // Get project language ID
      final projectLanguagesResult = await _projectLanguageRepository.getByProject(
        projectId,
      );

      if (projectLanguagesResult.isErr) {
        return Err(FileServiceException(
          'Failed to load project languages: ${projectLanguagesResult.unwrapErr()}',
        ));
      }

      final projectLanguages = projectLanguagesResult.unwrap();

      final projectLanguage = projectLanguages.firstWhere(
        (pl) => pl.languageId.contains(languageCode),
        orElse: () => throw FileServiceException(
          'Language $languageCode not found in project $projectId',
        ),
      );

      // Get all translation units for the project
      final unitsResult = await _unitRepository.getByProject(projectId);

      if (unitsResult.isErr) {
        return Err(FileServiceException(
          'Failed to load translation units: ${unitsResult.unwrapErr()}',
        ));
      }

      final units = unitsResult.unwrap();

      if (units.isEmpty) {
        return Err(FileServiceException(
          'No translation units found for project',
        ));
      }

      // Get translations for this language
      final buffer = StringBuffer();
      int exportedCount = 0;

      for (final unit in units) {
        // Skip obsolete units
        if (unit.isObsolete) continue;

        // Get translation version for this unit and language
        final versionResult = await _versionRepository.getByUnitAndProjectLanguage(
          unitId: unit.id,
          projectLanguageId: projectLanguage.id,
        );

        if (versionResult.isErr) {
          // Skip units without translations
          continue;
        }

        final version = versionResult.unwrap();

        // Apply validation filter
        if (validatedOnly) {
          // Only export approved or reviewed translations
          if (version.status != TranslationVersionStatus.approved &&
              version.status != TranslationVersionStatus.reviewed) {
            continue;
          }
        } else {
          // Export any completed translation
          if (version.translatedText == null ||
              version.translatedText!.isEmpty) {
            continue;
          }
        }

        // Format as .loc entry
        // Line 1: !!!!!!!!!!_{LANG}_{KEY}
        buffer.writeln('!!!!!!!!!!_${languageCode.toUpperCase()}_${unit.key}');

        // Line 2: "{TRANSLATION}" (escape internal quotes)
        final escapedText = _escapeLocText(version.translatedText!);
        buffer.writeln('"$escapedText"');

        // Line 3: true
        buffer.writeln('true');

        // Empty line between entries
        buffer.writeln();

        exportedCount++;
      }

      if (exportedCount == 0) {
        return Err(FileServiceException(
          'No translations available for export',
        ));
      }

      // Write to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${languageCode}_text_$timestamp.loc';
      final filePath = path.join(tempDir.path, 'twmt_export', fileName);

      final file = File(filePath);
      await file.parent.create(recursive: true);

      // Write with Windows line endings (CRLF) and UTF-8 encoding
      final contentWithCrlf = buffer.toString().replaceAll('\n', '\r\n');
      await file.writeAsString(contentWithCrlf, flush: true);

      _logger.info('.loc file generated successfully', {
        'filePath': filePath,
        'entriesExported': exportedCount,
      });

      return Ok(filePath);
    } catch (e, stackTrace) {
      _logger.error('Failed to generate .loc file', e, stackTrace);

      if (e is FileServiceException) {
        return Err(e);
      }

      return Err(FileServiceException(
        'Failed to generate .loc file: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<Map<String, String>, FileServiceException>>
      generateLocFilesForLanguages({
    required String projectId,
    required List<String> languageCodes,
    required bool validatedOnly,
  }) async {
    try {
      final results = <String, String>{};

      for (final languageCode in languageCodes) {
        final result = await generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: validatedOnly,
        );

        if (result is Err) {
          // Return error if any language fails
          return Err(result.error);
        }

        results[languageCode] = (result as Ok<String, FileServiceException>).value;
      }

      return Ok(results);
    } catch (e, stackTrace) {
      _logger.error('Failed to generate .loc files for languages', e, stackTrace);

      return Err(FileServiceException(
        'Failed to generate .loc files: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Future<Result<int, FileServiceException>> countExportableTranslations({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  }) async {
    try {
      // Get project language ID
      final projectLanguagesResult = await _projectLanguageRepository.getByProject(
        projectId,
      );

      if (projectLanguagesResult.isErr) {
        return Err(FileServiceException(
          'Failed to load project languages: ${projectLanguagesResult.unwrapErr()}',
        ));
      }

      final projectLanguages = projectLanguagesResult.unwrap();

      final projectLanguage = projectLanguages.firstWhere(
        (pl) => pl.languageId.contains(languageCode),
        orElse: () => throw FileServiceException(
          'Language $languageCode not found in project',
        ),
      );

      // Get all translation units for the project
      final unitsResult = await _unitRepository.getByProject(projectId);

      if (unitsResult.isErr) {
        return Err(FileServiceException(
          'Failed to load translation units: ${unitsResult.unwrapErr()}',
        ));
      }

      final units = unitsResult.unwrap();

      int count = 0;

      for (final unit in units) {
        // Skip obsolete units
        if (unit.isObsolete) continue;

        // Get translation version for this unit and language
        final versionResult = await _versionRepository.getByUnitAndProjectLanguage(
          unitId: unit.id,
          projectLanguageId: projectLanguage.id,
        );

        if (versionResult.isErr) {
          // Skip units without translations
          continue;
        }

        final version = versionResult.unwrap();

        // Apply validation filter
        if (validatedOnly) {
          if (version.status == TranslationVersionStatus.approved ||
              version.status == TranslationVersionStatus.reviewed) {
            count++;
          }
        } else {
          if (version.translatedText != null &&
              version.translatedText!.isNotEmpty) {
            count++;
          }
        }
      }

      return Ok(count);
    } catch (e, stackTrace) {
      _logger.error('Failed to count exportable translations', e, stackTrace);

      if (e is FileServiceException) {
        return Err(e);
      }

      return Err(FileServiceException(
        'Failed to count translations: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Escape text for .loc file format
  ///
  /// Escapes internal quotes by doubling them
  String _escapeLocText(String text) {
    return text.replaceAll('"', '""');
  }
}
