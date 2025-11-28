import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:twmt/services/shared/logging_service.dart';

/// Utility functions for .pack file export operations
///
/// Contains helper methods specific to Total War .pack file generation,
/// including file structure handling and naming conventions.
class PackExportUtils {
  final LoggingService _logger;

  PackExportUtils({LoggingService? logger})
      : _logger = logger ?? LoggingService.instance;

  /// Create a temporary directory for export operations
  Future<Directory> createTempDirectory(String prefix) async {
    final tempDirPath = path.join(
      Directory.systemTemp.path,
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}',
    );
    return Directory(tempDirPath).create(recursive: true);
  }

  /// Clean up temporary directory
  ///
  /// Safely deletes the temporary directory and logs any errors.
  /// Does not throw on failure.
  Future<void> cleanupTempDirectory(Directory? tempDir) async {
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

  /// Copy TSV files to pack structure maintaining internal path
  ///
  /// Reconstructs the directory structure from the encoded filename.
  /// TSV filename format: text__db__!!!!!!!!!!_FR_something.loc.tsv
  /// Internal path: text/db/!!!!!!!!!!_FR_something.loc.tsv
  Future<void> copyTsvFilesToPackStructure(
    List<String> tsvPaths,
    Directory tempDir,
  ) async {
    for (final generatedTsvPath in tsvPaths) {
      final tsvFile = File(generatedTsvPath);
      final tsvFileName = path.basename(generatedTsvPath);

      // Reconstruct directory structure from filename
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
  }

  /// Build pack file name with prefix for load order priority
  ///
  /// Format: !!!!!!!!!!_{lang}_twmt_{original_pack_name}.pack (all lowercase)
  /// The exclamation marks ensure the mod loads with high priority.
  String buildPackFileName(String languageCode, String? sourceFilePath) {
    final langCode = languageCode.toLowerCase();
    final originalPackName = extractOriginalPackName(sourceFilePath);
    return '!!!!!!!!!!_${langCode}_twmt_$originalPackName.pack';
  }

  /// Extract original pack filename from source file path
  ///
  /// Extracts just the pack name (without extension) from the full path.
  /// Returns lowercase name.
  /// Example: "C:\Games\Steam\...\Something.pack" -> "something"
  String extractOriginalPackName(String? sourceFilePath) {
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      return 'translation';
    }

    final fileName = path.basename(sourceFilePath);
    if (fileName.toLowerCase().endsWith('.pack')) {
      return fileName.substring(0, fileName.length - 5).toLowerCase();
    }

    return fileName.toLowerCase();
  }
}
