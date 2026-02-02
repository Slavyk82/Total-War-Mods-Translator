import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
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
  /// Format for mod translations: !!!!!!!!!!_{lang}_twmt_{original_pack_name}.pack (all lowercase)
  /// Format for game translations: !!!!!!!!!!_{lang}_twmt_game_translation.pack (all lowercase)
  /// The exclamation marks ensure the mod loads with high priority.
  String buildPackFileName(String languageCode, String? sourceFilePath) {
    final langCode = languageCode.toLowerCase();

    // Check if this is a game localization pack (local_*.pack)
    if (isGameLocalizationPack(sourceFilePath)) {
      return '!!!!!!!!!!_${langCode}_twmt_game_translation.pack';
    }

    final originalPackName = extractOriginalPackName(sourceFilePath);
    return '!!!!!!!!!!_${langCode}_twmt_$originalPackName.pack';
  }

  /// Check if the source file path is a game localization pack (local_*.pack)
  bool isGameLocalizationPack(String? sourceFilePath) {
    if (sourceFilePath == null || sourceFilePath.isEmpty) {
      return false;
    }
    final fileName = path.basename(sourceFilePath).toLowerCase();
    return fileName.startsWith('local_') && fileName.endsWith('.pack');
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

  /// Build the image file name for Steam Workshop
  ///
  /// Returns the same name as the pack file but with .png extension.
  /// Example: "!!!!!!!!!!_fr_twmt_game_translation.pack" -> "!!!!!!!!!!_fr_twmt_game_translation.png"
  String buildPackImageFileName(String packFileName) {
    if (packFileName.toLowerCase().endsWith('.pack')) {
      return '${packFileName.substring(0, packFileName.length - 5)}.png';
    }
    return '$packFileName.png';
  }

  /// Copy TWMT icon to the game's data folder for Steam Workshop
  ///
  /// This copies the bundled twmt_icon.png asset to the destination folder
  /// with the appropriate name matching the pack file.
  Future<void> copyTwmtIconToDataFolder({
    required String packFileName,
    required String destinationFolder,
  }) async {
    try {
      final imageFileName = buildPackImageFileName(packFileName);
      final destinationPath = path.join(destinationFolder, imageFileName);

      // Load the icon from bundled assets
      final byteData = await rootBundle.load('assets/twmt_icon.png');
      final bytes = byteData.buffer.asUint8List();

      // Write to destination
      await File(destinationPath).writeAsBytes(bytes);

      _logger.info('TWMT icon copied for Steam Workshop', {
        'destination': destinationPath,
      });
    } catch (e) {
      _logger.warning('Failed to copy TWMT icon', {
        'error': e.toString(),
      });
      // Don't throw - this is not critical for the export
    }
  }

  /// Get the path to the TWMT icon asset
  static const String twmtIconAssetPath = 'assets/twmt_icon.png';

  /// Wait for a file to be fully released by the system
  ///
  /// On Windows, files may remain locked briefly after a process exits.
  /// This method waits until the file is fully accessible for reading.
  ///
  /// [filePath] - Path to the file to check
  /// [maxRetries] - Maximum number of retry attempts (default: 10)
  /// [initialDelayMs] - Initial delay between retries in milliseconds (default: 100)
  ///
  /// Returns true if file is accessible, false if timeout reached.
  Future<bool> waitForFileRelease(
    String filePath, {
    int maxRetries = 10,
    int initialDelayMs = 100,
  }) async {
    final file = File(filePath);

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Try to open the file for reading with exclusive access
        // This will fail if the file is still locked by another process
        final randomAccessFile = await file.open(mode: FileMode.read);

        // Successfully opened - file is released
        await randomAccessFile.close();

        if (attempt > 0) {
          _logger.info('File released after ${attempt + 1} attempts', {
            'filePath': filePath,
          });
        }

        return true;
      } on FileSystemException catch (e) {
        // File is still locked, wait and retry
        final delayMs = initialDelayMs * (attempt + 1); // Increasing delay

        _logger.debug('File still locked, retrying in ${delayMs}ms', {
          'filePath': filePath,
          'attempt': attempt + 1,
          'maxRetries': maxRetries,
          'error': e.message,
        });

        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    // Timeout reached
    _logger.warning('File release timeout reached', {
      'filePath': filePath,
      'maxRetries': maxRetries,
    });

    return false;
  }
}
