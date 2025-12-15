import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/file/i_loc_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Total War .loc file service
///
/// Generates TSV files in RPFM format that can be converted to binary .loc
/// files using RPFM-CLI's --tsv-to-binary option.
class LocFileServiceImpl implements ILocFileService {
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final ProjectLanguageRepository _projectLanguageRepository;
  final LanguageRepository _languageRepository;
  final LoggingService _logger;

  LocFileServiceImpl({
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required ProjectLanguageRepository projectLanguageRepository,
    required LanguageRepository languageRepository,
    LoggingService? logger,
  })  : _unitRepository = unitRepository,
        _versionRepository = versionRepository,
        _projectLanguageRepository = projectLanguageRepository,
        _languageRepository = languageRepository,
        _logger = logger ?? LoggingService.instance;

  /// Find project language by language code
  ///
  /// Looks up the language by code to get its ID, then finds the matching
  /// project language. This supports both system languages (with IDs like 'lang_en')
  /// and custom languages (with UUID IDs).
  Future<Result<ProjectLanguage, FileServiceException>> _findProjectLanguage({
    required String projectId,
    required String languageCode,
    required List<ProjectLanguage> projectLanguages,
  }) async {
    // First, get the language ID from the language code
    final languageResult = await _languageRepository.getByCode(languageCode);

    if (languageResult.isErr) {
      return Err(FileServiceException(
        'Language code "$languageCode" not found in system',
      ));
    }

    final language = languageResult.unwrap();

    // Now find the project language that matches this language ID
    final projectLanguage = projectLanguages.where(
      (pl) => pl.languageId == language.id,
    ).firstOrNull;

    if (projectLanguage == null) {
      return Err(FileServiceException(
        'Language "$languageCode" not found in project $projectId',
      ));
    }

    return Ok(projectLanguage);
  }

  @override
  Future<Result<String, FileServiceException>> generateLocFile({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  }) async {
    try {
      _logger.info('Generating TSV file for .loc export', {
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

      final projectLanguageResult = await _findProjectLanguage(
        projectId: projectId,
        languageCode: languageCode,
        projectLanguages: projectLanguages,
      );

      if (projectLanguageResult.isErr) {
        return Err(projectLanguageResult.unwrapErr());
      }

      final projectLanguage = projectLanguageResult.unwrap();

      // Get all active (non-obsolete) translation units for the project
      final unitsResult = await _unitRepository.getActive(projectId);

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

      // Build TSV content in RPFM format
      final buffer = StringBuffer();

      // TSV Header row
      buffer.writeln('key\ttext\ttooltip');

      // Metadata row - RPFM format: #Loc;version;internal_path
      // The internal path will be set by RPFM when adding to pack
      final langLower = languageCode.toLowerCase();
      buffer.writeln('#Loc;1;text/db/!!!!!!!!!!_${langLower}_twmt_text.loc\t\t');

      int exportedCount = 0;

      for (final unit in units) {
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
          // Only export translated translations (not needsReview)
          if (version.status != TranslationVersionStatus.translated) {
            continue;
          }
        } else {
          // Export any completed translation
          if (version.translatedText == null ||
              version.translatedText!.isEmpty) {
            continue;
          }
        }

        // Format as TSV row: key\ttext\ttooltip
        final escapedText = _escapeTsvText(version.translatedText!);
        buffer.writeln('${unit.key}\t$escapedText\tfalse');

        exportedCount++;
      }

      if (exportedCount == 0) {
        return Err(FileServiceException(
          'No translations available for export',
        ));
      }

      // Write to temporary file with .tsv extension
      final tempDir = await getTemporaryDirectory();
// Removed unused variable
      // Create directory structure matching pack internal path
      final tsvDir = path.join(tempDir.path, 'twmt_export', 'text', 'db');
      final fileName = '!!!!!!!!!!_${langLower}_twmt_text.loc.tsv';
      final filePath = path.join(tsvDir, fileName);

      final file = File(filePath);
      await file.parent.create(recursive: true);

      // Write with UTF-8 encoding (no BOM) and LF line endings
      // RPFM expects LF, not CRLF
      await file.writeAsString(buffer.toString(), flush: true);

      _logger.info('TSV file generated successfully', {
        'filePath': filePath,
        'entriesExported': exportedCount,
      });

      return Ok(filePath);
    } catch (e, stackTrace) {
      _logger.error('Failed to generate TSV file', e, stackTrace);

      if (e is FileServiceException) {
        return Err(e);
      }

      return Err(FileServiceException(
        'Failed to generate TSV file: ${e.toString()}',
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

      final projectLanguageResult = await _findProjectLanguage(
        projectId: projectId,
        languageCode: languageCode,
        projectLanguages: projectLanguages,
      );

      if (projectLanguageResult.isErr) {
        return Err(projectLanguageResult.unwrapErr());
      }

      final projectLanguage = projectLanguageResult.unwrap();

      // Get all active (non-obsolete) translation units for the project
      final unitsResult = await _unitRepository.getActive(projectId);

      if (unitsResult.isErr) {
        return Err(FileServiceException(
          'Failed to load translation units: ${unitsResult.unwrapErr()}',
        ));
      }

      final units = unitsResult.unwrap();

      int count = 0;

      for (final unit in units) {
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
          if (version.status == TranslationVersionStatus.translated) {
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

  @override
  Future<Result<List<String>, FileServiceException>> generateLocFilesGroupedBySource({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  }) async {
    try {
      _logger.info('Generating TSV files grouped by source .loc file', {
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

      final projectLanguageResult = await _findProjectLanguage(
        projectId: projectId,
        languageCode: languageCode,
        projectLanguages: projectLanguages,
      );

      if (projectLanguageResult.isErr) {
        return Err(projectLanguageResult.unwrapErr());
      }

      final projectLanguage = projectLanguageResult.unwrap();

      // Get all active (non-obsolete) translation units for the project
      final unitsResult = await _unitRepository.getActive(projectId);

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

      // Group units by source .loc file
      final groupedUnits = <String, List<({String key, String translatedText})>>{};
      final langLower = languageCode.toLowerCase();

      for (final unit in units) {
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
          if (version.status != TranslationVersionStatus.translated) {
            continue;
          }
        } else {
          if (version.translatedText == null ||
              version.translatedText!.isEmpty) {
            continue;
          }
        }

        // Determine the source file grouping key
        // Use the original source .loc file path, or fallback to a default
        final sourceFile = unit.sourceLocFile ?? 'text/db/translations.loc';
        
        groupedUnits.putIfAbsent(sourceFile, () => []);
        groupedUnits[sourceFile]!.add((
          key: unit.key,
          translatedText: version.translatedText!,
        ));
      }

      if (groupedUnits.isEmpty) {
        return Err(FileServiceException(
          'No translations available for export',
        ));
      }

      // Generate a TSV file for each source .loc file
      final tempDir = await getTemporaryDirectory();
      final generatedFiles = <String>[];

      for (final entry in groupedUnits.entries) {
        final sourceLocFile = entry.key;
        final translations = entry.value;

        // Build TSV content in RPFM format
        final buffer = StringBuffer();
        
        // TSV Header row
        buffer.writeln('key\ttext\ttooltip');
        
        // Generate the output .loc path with language prefix (lowercase)
        // Original: text/db/something.loc -> text/db/!!!!!!!!!!_fr_twmt_something.loc
        final outputLocPath = _generateOutputLocPath(sourceLocFile, langLower);
        
        // Metadata row - RPFM format: #Loc;version;internal_path
        buffer.writeln('#Loc;1;$outputLocPath\t\t');
        
        for (final translation in translations) {
          final escapedText = _escapeTsvText(translation.translatedText);
          buffer.writeln('${translation.key}\t$escapedText\tfalse');
        }

        // Create directory structure matching the output path
        // The TSV filename encodes the full path with __ as separator
        final tsvFileName = '${outputLocPath.replaceAll('/', '__')}.tsv';
        final tsvDir = path.join(tempDir.path, 'twmt_export');
        final filePath = path.join(tsvDir, tsvFileName);

        final file = File(filePath);
        await file.parent.create(recursive: true);

        // Write with UTF-8 encoding (no BOM) and LF line endings
        await file.writeAsString(buffer.toString(), flush: true);

        generatedFiles.add(filePath);

        _logger.info('TSV file generated', {
          'sourceFile': sourceLocFile,
          'outputFile': outputLocPath,
          'filePath': filePath,
          'entriesExported': translations.length,
        });
      }

      _logger.info('All TSV files generated successfully', {
        'totalFiles': generatedFiles.length,
      });

      return Ok(generatedFiles);
    } catch (e, stackTrace) {
      _logger.error('Failed to generate TSV files', e, stackTrace);

      if (e is FileServiceException) {
        return Err(e);
      }

      return Err(FileServiceException(
        'Failed to generate TSV files: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Generate output .loc path with language prefix (all lowercase)
  ///
  /// Transforms the original .loc path to include the language prefix.
  /// Example: text/db/Something.loc -> text/db/!!!!!!!!!!_fr_twmt_something.loc
  String _generateOutputLocPath(String sourceLocFile, String langLower) {
    // Get the directory and filename parts
    final dir = path.dirname(sourceLocFile).replaceAll('\\', '/').toLowerCase();
    final fileName = path.basename(sourceLocFile);
    
    // Remove .loc extension if present and convert to lowercase
    String baseName = fileName;
    if (baseName.toLowerCase().endsWith('.loc')) {
      baseName = baseName.substring(0, baseName.length - 4);
    }
    baseName = baseName.toLowerCase();
    
    // Build new filename with prefix (all lowercase): !!!!!!!!!!_fr_twmt_originalname.loc
    final newFileName = '!!!!!!!!!!_${langLower}_twmt_$baseName.loc';
    
    // Combine directory and new filename
    if (dir.isEmpty || dir == '.') {
      return newFileName;
    }
    return '$dir/$newFileName';
  }

  /// Escape text for TSV format compatible with RPFM
  ///
  /// RPFM TSV format uses double-backslash for escape sequences:
  /// - Existing backslash → \\\\ (two backslashes in file)
  /// - Real newline (char 10) → \\n (backslash, backslash, n in file)
  /// - Real tab (char 9) → \\t (backslash, backslash, t in file)
  String _escapeTsvText(String text) {
    return text
        .replaceAll('\\', '\\\\')  // Escape existing backslashes: \ → \\
        .replaceAll('\t', '\\\\t') // Escape tabs: tab → \\t
        .replaceAll('\n', '\\\\n') // Escape newlines: newline → \\n
        .replaceAll('\r', '');     // Remove carriage returns
  }
}
