import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Service interface for Total War .loc file operations
///
/// Handles generation and parsing of Total War localization files
/// which use a specific format for mod translations.
abstract class ILocFileService {
  /// Generate a .loc file for a specific project and language
  ///
  /// Creates a Total War compatible .loc file containing translations
  /// for the specified project and language.
  ///
  /// [projectId]: ID of the project to export
  /// [languageCode]: Language code (e.g., 'en', 'fr', 'de')
  /// [validatedOnly]: If true, only export validated translations
  ///
  /// Returns path to the generated .loc file
  ///
  /// Total War .loc format:
  /// ```
  /// !!!!!!!!!!_en_ui_key_name
  /// "Translation text"
  /// true
  ///
  /// ```
  Future<Result<String, FileServiceException>> generateLocFile({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  });

  /// Generate .loc files for multiple languages
  ///
  /// Creates .loc files for each specified language in a project.
  ///
  /// [projectId]: ID of the project to export
  /// [languageCodes]: List of language codes to export
  /// [validatedOnly]: If true, only export validated translations
  ///
  /// Returns map of language code to .loc file path
  Future<Result<Map<String, String>, FileServiceException>>
      generateLocFilesForLanguages({
    required String projectId,
    required List<String> languageCodes,
    required bool validatedOnly,
  });

  /// Count translations that would be exported
  ///
  /// Returns the number of translation entries that would be included
  /// in the export for the given criteria.
  ///
  /// [projectId]: ID of the project
  /// [languageCode]: Language code
  /// [validatedOnly]: If true, only count validated translations
  ///
  /// Returns count of translations
  Future<Result<int, FileServiceException>> countExportableTranslations({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
  });
}
