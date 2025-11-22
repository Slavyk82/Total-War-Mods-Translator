import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';
import 'package:twmt/services/rpfm/models/rpfm_pack_info.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';

/// Log message for RPFM operations
class RpfmLogMessage {
  final String message;
  final DateTime timestamp;

  RpfmLogMessage({
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Interface for RPFM (Rusted PackFile Manager) service
///
/// Handles extraction and creation of Total War .pack files
/// using the RPFM-CLI command-line tool.
abstract class IRpfmService {
  /// Extract localization files from a .pack file
  ///
  /// Extracts all .loc files to a temporary directory.
  ///
  /// [packFilePath] - Path to .pack file to extract from
  /// [outputDirectory] - Directory to extract files to (optional, uses temp if null)
  ///
  /// Returns [Ok(RpfmExtractResult)] with extracted file list
  /// or [Err(RpfmServiceException)] on failure
  Future<Result<RpfmExtractResult, RpfmServiceException>>
      extractLocalizationFiles(
    String packFilePath, {
    String? outputDirectory,
  });

  /// Extract localization files from a .pack file as TSV format
  ///
  /// Extracts all .loc files to TSV format using RPFM-CLI's --tables-as-tsv option.
  /// This produces clean, readable TSV files instead of binary .loc files.
  ///
  /// [packFilePath] - Path to .pack file to extract from
  /// [outputDirectory] - Directory to extract files to (optional, uses temp if null)
  /// [schemaPath] - Path to RPFM schema folder (optional, uses settings if null)
  ///
  /// Returns [Ok(RpfmExtractResult)] with extracted TSV file list
  /// or [Err(RpfmServiceException)] on failure
  Future<Result<RpfmExtractResult, RpfmServiceException>>
      extractLocalizationFilesAsTsv(
    String packFilePath, {
    String? outputDirectory,
    String? schemaPath,
  });

  /// Extract all files from a .pack file
  ///
  /// [packFilePath] - Path to .pack file to extract from
  /// [outputDirectory] - Directory to extract files to
  ///
  /// Returns [Ok(RpfmExtractResult)] or [Err(RpfmServiceException)]
  Future<Result<RpfmExtractResult, RpfmServiceException>> extractAllFiles(
    String packFilePath,
    String outputDirectory,
  );

  /// Create a .pack file from directory
  ///
  /// Creates a new .pack file with file prefixing for language.
  /// Prefix format: `!!!!!!!!!!_{LANG}_filename.loc`
  ///
  /// [inputDirectory] - Directory containing files to pack
  /// [outputPackPath] - Path for output .pack file
  /// [languageCode] - Language code for file prefixing (e.g., "fr", "de")
  ///
  /// Returns [Ok(packFilePath)] or [Err(RpfmServiceException)]
  Future<Result<String, RpfmServiceException>> createPack({
    required String inputDirectory,
    required String outputPackPath,
    required String languageCode,
  });

  /// Get metadata about a .pack file
  ///
  /// Returns information without extracting.
  ///
  /// [packFilePath] - Path to .pack file
  ///
  /// Returns [Ok(RpfmPackInfo)] or [Err(RpfmServiceException)]
  Future<Result<RpfmPackInfo, RpfmServiceException>> getPackInfo(
    String packFilePath,
  );

  /// List contents of a .pack file
  ///
  /// Returns list of file paths inside the pack without extracting.
  ///
  /// [packFilePath] - Path to .pack file
  ///
  /// Returns [Ok(List<String>)] with file paths or [Err(RpfmServiceException)]
  Future<Result<List<String>, RpfmServiceException>> listPackContents(
    String packFilePath,
  );

  /// Check if RPFM-CLI is available
  ///
  /// Returns true if RPFM-CLI is installed and accessible
  Future<bool> isRpfmAvailable();

  /// Get RPFM-CLI version
  ///
  /// Returns [Ok(version)] or [Err(RpfmServiceException)]
  Future<Result<String, RpfmServiceException>> getRpfmVersion();

  /// Download and install RPFM-CLI
  ///
  /// Downloads latest version from GitHub releases if not found.
  ///
  /// [force] - Force re-download even if already installed
  ///
  /// Returns [Ok(installPath)] or [Err(RpfmServiceException)]
  Future<Result<String, RpfmServiceException>> downloadRpfm({
    bool force = false,
  });

  /// Cancel ongoing operation
  ///
  /// Cancels current extraction/packing operation if any.
  Future<void> cancel();

  /// Progress stream for long operations
  ///
  /// Yields progress updates (0.0-1.0) during extraction/packing
  Stream<double> get progressStream;

  /// Log message stream for operations
  ///
  /// Yields detailed log messages during operations
  Stream<RpfmLogMessage> get logStream;
}
