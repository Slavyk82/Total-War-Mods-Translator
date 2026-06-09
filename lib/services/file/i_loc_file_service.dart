import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// A generated TSV file together with its real internal .loc path inside the
/// pack (e.g. `text/db/!!!!!!!!!!_fr_twmt_something.loc`). The internal path is
/// carried explicitly rather than encoded in the file name, which previously
/// corrupted paths containing double underscores.
class GeneratedLocFile {
  final String tsvPath;
  final String internalPath;
  const GeneratedLocFile({required this.tsvPath, required this.internalPath});
}

/// Service interface for Total War .loc file operations
///
/// Handles generation and parsing of Total War localization files
/// which use a specific format for mod translations.
abstract class ILocFileService {
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

  /// Generate multiple .loc files grouped by original source file
  ///
  /// Creates separate TSV files for each distinct source .loc file in the project.
  /// Each TSV file preserves the original internal path with a language prefix.
  ///
  /// [projectId]: ID of the project to export
  /// [languageCode]: Language code (e.g., 'en', 'fr', 'de')
  /// [validatedOnly]: If true, only export validated translations
  /// [excludeKeys]: Translation keys to omit from the output. Used by pack
  ///   compilation to drop the losing/skipped entries of resolved key conflicts
  ///   so only the winning project's value survives the pack merge.
  /// [prefix]: Load-order prefix prepended to each generated .loc filename
  ///   inside the pack (default [AppConstants.defaultPackPrefix]). Controls Total
  ///   War load priority; see Settings/General.
  ///
  /// Returns a list of generated TSV files paired with their internal .loc path
  Future<Result<List<GeneratedLocFile>, FileServiceException>> generateLocFilesGroupedBySource({
    required String projectId,
    required String languageCode,
    required bool validatedOnly,
    Set<String> excludeKeys = const {},
    String prefix = AppConstants.defaultPackPrefix,
  });
}
