import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/common/service_exception.dart';
import '../shared/logging_service.dart';

/// Represents a detected game localization pack file.
class DetectedLocalPack {
  /// Language code extracted from filename (e.g., 'en', 'fr', 'de')
  final String languageCode;

  /// Display name for the language (e.g., 'English', 'French')
  final String languageName;

  /// Full path to the pack file
  final String packFilePath;

  /// File size in bytes
  final int fileSizeBytes;

  /// Last modification time
  final DateTime lastModified;

  const DetectedLocalPack({
    required this.languageCode,
    required this.languageName,
    required this.packFilePath,
    required this.fileSizeBytes,
    required this.lastModified,
  });

  /// Get formatted file size (e.g., "245 MB")
  String get formattedSize {
    if (fileSizeBytes < 1024) {
      return '$fileSizeBytes B';
    } else if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else if (fileSizeBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  @override
  String toString() => 'DetectedLocalPack($languageCode: $packFilePath)';
}

/// Service for detecting and managing game localization pack files.
///
/// Game localization packs are located at: {game_installation_path}/data/local_xx.pack
/// where xx is the language code (en, fr, de, es, ru, zh, etc.)
class GameLocalizationService {
  final LoggingService _logging = LoggingService.instance;

  /// Map of language codes to display names
  static const Map<String, String> languageCodeNames = {
    'en': 'English',
    'br': 'Brazilian Portuguese',
    'cn': 'Chinese (Simplified)',
    'cz': 'Czech',
    'de': 'German',
    'es': 'Spanish',
    'fr': 'French',
    'it': 'Italian',
    'jp': 'Japanese',
    'kr': 'Korean',
    'pl': 'Polish',
    'ru': 'Russian',
    'tr': 'Turkish',
    'tw': 'Chinese (Traditional)',
    'zh': 'Chinese',
  };

  /// Detect all available localization packs for a game installation.
  ///
  /// Scans the game's data folder for files matching the pattern `local_*.pack`
  /// and returns information about each detected pack.
  Future<List<DetectedLocalPack>> detectLocalizationPacks(
    String gameInstallationPath,
  ) async {
    final dataPath = path.join(gameInstallationPath, 'data');
    final dataDir = Directory(dataPath);

    if (!await dataDir.exists()) {
      _logging.warning('Data directory not found: $dataPath');
      return [];
    }

    final packs = <DetectedLocalPack>[];

    try {
      await for (final entity in dataDir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path).toLowerCase();

          // Match local_xx.pack pattern
          if (fileName.startsWith('local_') && fileName.endsWith('.pack')) {
            // Extract language code (e.g., 'en' from 'local_en.pack')
            final languageCode = fileName
                .substring(6) // Remove 'local_'
                .replaceAll('.pack', '');

            if (languageCode.isNotEmpty) {
              final stat = await entity.stat();
              packs.add(DetectedLocalPack(
                languageCode: languageCode,
                languageName: getLanguageName(languageCode),
                packFilePath: entity.path,
                fileSizeBytes: stat.size,
                lastModified: stat.modified,
              ));
            }
          }
        }
      }

      // Sort with English first, then alphabetically by language name
      packs.sort((a, b) {
        // English always comes first
        if (a.languageCode == 'en') return -1;
        if (b.languageCode == 'en') return 1;
        // Rest sorted alphabetically by language name
        return a.languageName.compareTo(b.languageName);
      });

      _logging.info(
        'Detected ${packs.length} localization packs in $dataPath: '
        '${packs.map((p) => p.languageCode).join(", ")}',
      );

      return packs;
    } catch (e, stackTrace) {
      _logging.error(
        'Failed to detect localization packs in $dataPath',
        e,
        stackTrace,
      );
      throw FileSystemException(
        'Failed to scan for localization packs',
        filePath: dataPath,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get display name for a language code.
  ///
  /// Returns the code in uppercase if no mapping exists.
  String getLanguageName(String code) {
    return languageCodeNames[code.toLowerCase()] ?? code.toUpperCase();
  }

  /// Get language code from a pack file path.
  ///
  /// Returns null if the path doesn't match the expected pattern.
  String? getLanguageCodeFromPath(String packFilePath) {
    final fileName = path.basename(packFilePath).toLowerCase();

    if (fileName.startsWith('local_') && fileName.endsWith('.pack')) {
      return fileName.substring(6).replaceAll('.pack', '');
    }

    return null;
  }

  /// Check if a file path is a valid game localization pack.
  bool isLocalizationPack(String filePath) {
    final fileName = path.basename(filePath).toLowerCase();
    return fileName.startsWith('local_') && fileName.endsWith('.pack');
  }
}
