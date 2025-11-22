import 'package:twmt/models/common/result.dart';
import 'models/localization_entry.dart';
import 'models/localization_file.dart';
import 'models/file_exceptions.dart';

/// Interface for parsing .loc localization files
///
/// .loc files are TSV (Tab-Separated Values) files used by Total War games.
///
/// Features:
/// - Parse UTF-8 and UTF-16 encoded files
/// - Handle comments (lines starting with #)
/// - Handle escaped characters (\n, \t, \\, \r)
/// - Handle multi-line values
/// - Generate .loc files with language prefix
/// - Stream parsing for large files (10k+ lines)
/// - Round-trip preservation (parse → generate → identical)
abstract class ILocalizationParser {
  /// Parse a .loc file from disk
  ///
  /// [filePath]: Path to the .loc file
  /// [encoding]: File encoding ('utf-8' or 'utf-16')
  /// [languageCode]: Language code (e.g., 'fr', 'en', 'de')
  ///
  /// Returns LocalizationFile with all entries and metadata
  ///
  /// Throws:
  /// - FileNotFoundException if file doesn't exist
  /// - FileEncodingException if encoding is invalid
  /// - FileParsingException if file format is invalid
  Future<Result<LocalizationFile, FileServiceException>> parseFile({
    required String filePath,
    String encoding = 'utf-8',
    String? languageCode,
  });

  /// Parse .loc file from string content
  ///
  /// [content]: File content as string
  /// [fileName]: Original file name (for metadata)
  /// [languageCode]: Language code
  ///
  /// Returns LocalizationFile with all entries
  Future<Result<LocalizationFile, FileParsingException>> parseString({
    required String content,
    required String fileName,
    required String languageCode,
  });

  /// Parse .loc file as stream (for large files)
  ///
  /// Processes file line-by-line to avoid loading entire file into memory.
  /// Recommended for files with 10,000+ lines.
  ///
  /// [filePath]: Path to the .loc file
  /// [encoding]: File encoding
  /// [languageCode]: Language code
  ///
  /// Returns Stream of LocalizationEntry items
  ///
  /// Usage:
  /// ```dart
  /// await for (final entry in parser.parseFileStream(path)) {
  ///   processEntry(entry);
  /// }
  /// ```
  Stream<Result<LocalizationEntry, FileParsingException>> parseFileStream({
    required String filePath,
    String encoding = 'utf-8',
    String? languageCode,
  });

  /// Generate .loc file content from entries
  ///
  /// [file]: LocalizationFile to generate content for
  /// [includeComments]: Whether to include comment lines
  /// [applyPrefix]: Whether to use language prefix in filename
  ///
  /// Returns file content as string
  Future<Result<String, FileServiceException>> generateFileContent({
    required LocalizationFile file,
    bool includeComments = true,
    bool applyPrefix = true,
  });

  /// Write LocalizationFile to disk
  ///
  /// [file]: LocalizationFile to write
  /// [destinationPath]: Where to write the file
  /// [encoding]: File encoding ('utf-8' or 'utf-16')
  /// [applyPrefix]: Whether to use language prefix in filename
  ///
  /// Returns path to written file
  ///
  /// Throws:
  /// - FileWriteException if writing fails
  /// - FileAccessDeniedException if no write permission
  Future<Result<String, FileServiceException>> writeFile({
    required LocalizationFile file,
    required String destinationPath,
    String encoding = 'utf-8',
    bool applyPrefix = true,
  });

  /// Validate .loc file structure without full parsing
  ///
  /// Quick validation to check:
  /// - File exists and is readable
  /// - Encoding is valid
  /// - Basic TSV structure is correct
  /// - No critical format errors
  ///
  /// [filePath]: Path to validate
  ///
  /// Returns FileValidationResult with errors/warnings
  Future<Result<FileValidationResult, FileServiceException>> validateFile({
    required String filePath,
  });

  /// Detect file encoding (UTF-8 vs UTF-16)
  ///
  /// Reads first few bytes to detect BOM (Byte Order Mark):
  /// - UTF-8: EF BB BF
  /// - UTF-16 LE: FF FE
  /// - UTF-16 BE: FE FF
  ///
  /// [filePath]: Path to file
  ///
  /// Returns detected encoding string
  Future<Result<String, FileEncodingException>> detectEncoding({
    required String filePath,
  });

  /// Extract language code from filename
  ///
  /// Parses language from prefixed filename:
  /// "!!!!!!!!!!_FR_units.loc" → "fr"
  ///
  /// [fileName]: File name to parse
  ///
  /// Returns language code or null if not prefixed
  String? extractLanguageCode(String fileName);

  /// Generate prefixed filename for language
  ///
  /// Applies Total War naming convention:
  /// "units.loc" + "fr" → "!!!!!!!!!!_FR_units.loc"
  ///
  /// [baseName]: Base file name
  /// [languageCode]: Language code
  ///
  /// Returns prefixed filename
  String generatePrefixedFileName(String baseName, String languageCode);

  /// Merge multiple .loc files into one
  ///
  /// Combines entries from multiple files:
  /// - Detects and resolves duplicate keys
  /// - Preserves comments from all files
  /// - Maintains entry order
  ///
  /// [files]: List of LocalizationFile to merge
  /// [conflictResolution]: How to handle duplicate keys
  ///   - 'first': Keep first occurrence
  ///   - 'last': Keep last occurrence
  ///   - 'error': Throw exception
  ///
  /// Returns merged LocalizationFile
  Future<Result<LocalizationFile, FileServiceException>> mergeFiles({
    required List<LocalizationFile> files,
    String conflictResolution = 'last',
  });

  /// Split large .loc file into smaller chunks
  ///
  /// Useful for processing very large files (100k+ entries):
  /// - Splits by entry count
  /// - Preserves key-value integrity
  /// - Distributes comments proportionally
  ///
  /// [file]: File to split
  /// [maxEntriesPerFile]: Maximum entries per chunk
  ///
  /// Returns list of LocalizationFile chunks
  Future<Result<List<LocalizationFile>, FileServiceException>> splitFile({
    required LocalizationFile file,
    int maxEntriesPerFile = 10000,
  });
}

/// Options for parsing localization files
class ParsingOptions {
  /// Whether to preserve comment lines
  final bool preserveComments;

  /// Whether to preserve empty lines
  final bool preserveEmptyLines;

  /// Whether to validate entries during parsing
  final bool validateEntries;

  /// Whether to trim whitespace from keys and values
  final bool trimWhitespace;

  /// Whether to skip invalid entries (vs throwing exception)
  final bool skipInvalidEntries;

  /// Maximum file size in bytes (0 = no limit)
  final int maxFileSize;

  const ParsingOptions({
    this.preserveComments = true,
    this.preserveEmptyLines = false,
    this.validateEntries = true,
    this.trimWhitespace = true,
    this.skipInvalidEntries = false,
    this.maxFileSize = 0,
  });

  /// Default parsing options
  static const ParsingOptions defaultOptions = ParsingOptions();

  /// Strict parsing (fail on any error)
  static const ParsingOptions strict = ParsingOptions(
    preserveComments: true,
    preserveEmptyLines: true,
    validateEntries: true,
    trimWhitespace: false,
    skipInvalidEntries: false,
  );

  /// Lenient parsing (skip errors)
  static const ParsingOptions lenient = ParsingOptions(
    preserveComments: false,
    preserveEmptyLines: false,
    validateEntries: false,
    trimWhitespace: true,
    skipInvalidEntries: true,
  );
}
