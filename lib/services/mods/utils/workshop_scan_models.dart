import 'dart:io';

/// Data transfer object containing local mod information during scanning.
///
/// Holds all locally-extracted data about a mod before Steam API enrichment.
class ModLocalData {
  /// Steam Workshop ID (numeric string).
  final String workshopId;

  /// Reference to the pack file.
  final File packFile;

  /// Base name of the pack file without extension.
  final String packFileName;

  /// Local path to mod preview image, if found.
  final String? modImagePath;

  /// Whether the pack file contains localization (.loc) files.
  final bool hasLocFiles;

  /// Local file last modified timestamp (Unix epoch seconds).
  final int fileLastModified;

  const ModLocalData({
    required this.workshopId,
    required this.packFile,
    required this.packFileName,
    this.modImagePath,
    this.hasLocFiles = false,
    required this.fileLastModified,
  });
}

/// Intermediate data holder for pack file information before cache lookup.
///
/// Used during the first pass of workshop scanning to collect pack file
/// metadata before checking the scan cache.
class PackFileInfo {
  /// Steam Workshop ID (numeric string).
  final String workshopId;

  /// Reference to the mod directory.
  final Directory modDir;

  /// Reference to the pack file.
  final File packFile;

  /// Base name of the pack file without extension.
  final String packFileName;

  /// File last modified timestamp (Unix epoch seconds).
  final int fileLastModified;

  const PackFileInfo({
    required this.workshopId,
    required this.modDir,
    required this.packFile,
    required this.packFileName,
    required this.fileLastModified,
  });
}
