import 'package:json_annotation/json_annotation.dart';
import 'localization_entry.dart';

part 'localization_file.g.dart';

/// Represents a complete .loc localization file
///
/// .loc files are TSV (Tab-Separated Values) files used by Total War games:
/// - UTF-8 or UTF-16 encoding
/// - Comments start with #
/// - Format: key\tvalue
/// - Generated files have language prefix: !!!!!!!!!!_{LANG}_filename.loc
@JsonSerializable()
class LocalizationFile {
  /// File name (without path)
  ///
  /// Example: "!!!!!!!!!!_FR_text_units.loc"
  final String fileName;

  /// Full file path
  final String filePath;

  /// Language code (ISO 639-1)
  ///
  /// Example: "fr", "en", "de", "es"
  final String languageCode;

  /// File encoding (UTF-8 or UTF-16)
  @JsonKey(defaultValue: 'utf-8')
  final String encoding;

  /// All localization entries in this file
  final List<LocalizationEntry> entries;

  /// Comment lines (preserved for round-trip)
  ///
  /// Lines starting with # are stored separately
  /// to preserve them when writing back to disk
  @JsonKey(defaultValue: [])
  final List<String> comments;

  /// Metadata about the file
  final LocalizationFileMetadata? metadata;

  const LocalizationFile({
    required this.fileName,
    required this.filePath,
    required this.languageCode,
    this.encoding = 'utf-8',
    required this.entries,
    this.comments = const [],
    this.metadata,
  });

  /// Factory constructor for JSON deserialization
  factory LocalizationFile.fromJson(Map<String, dynamic> json) =>
      _$LocalizationFileFromJson(json);

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() => _$LocalizationFileToJson(this);

  /// Create a copy with modified fields
  LocalizationFile copyWith({
    String? fileName,
    String? filePath,
    String? languageCode,
    String? encoding,
    List<LocalizationEntry>? entries,
    List<String>? comments,
    LocalizationFileMetadata? metadata,
  }) {
    return LocalizationFile(
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      languageCode: languageCode ?? this.languageCode,
      encoding: encoding ?? this.encoding,
      entries: entries ?? this.entries,
      comments: comments ?? this.comments,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Get entry by key
  LocalizationEntry? getEntry(String key) {
    try {
      return entries.firstWhere((e) => e.key == key);
    } catch (_) {
      return null;
    }
  }

  /// Check if file contains a key
  bool containsKey(String key) {
    return entries.any((e) => e.key == key);
  }

  /// Get all keys in this file
  List<String> get keys => entries.map((e) => e.key).toList();

  /// Total number of entries
  int get entryCount => entries.length;

  /// Check if file is empty
  bool get isEmpty => entries.isEmpty;

  /// Check if file is not empty
  bool get isNotEmpty => entries.isNotEmpty;

  /// Generate language-prefixed filename
  ///
  /// Total War convention: !!!!!!!!!!_{LANG}_filename.loc
  ///
  /// Example: "units.loc" with "fr" → "!!!!!!!!!!_FR_units.loc"
  static String generatePrefixedFileName(String baseName, String langCode) {
    final upperLang = langCode.toUpperCase();

    // Remove existing prefix if present
    String cleanName = baseName;
    if (baseName.startsWith('!!!!!!!!!!_')) {
      final parts = baseName.split('_');
      if (parts.length >= 3) {
        cleanName = parts.sublist(2).join('_');
      }
    }

    // Ensure .loc extension
    if (!cleanName.toLowerCase().endsWith('.loc')) {
      cleanName = '$cleanName.loc';
    }

    return '!!!!!!!!!!_${upperLang}_$cleanName';
  }

  /// Extract language code from prefixed filename
  ///
  /// Example: "!!!!!!!!!!_FR_units.loc" → "fr"
  static String? extractLanguageCode(String fileName) {
    if (!fileName.startsWith('!!!!!!!!!!_')) return null;

    final parts = fileName.split('_');
    if (parts.length < 2) return null;

    return parts[1].toLowerCase();
  }

  /// Extract base filename without prefix
  ///
  /// Example: "!!!!!!!!!!_FR_units.loc" → "units.loc"
  static String extractBaseName(String fileName) {
    if (!fileName.startsWith('!!!!!!!!!!_')) return fileName;

    final parts = fileName.split('_');
    if (parts.length < 3) return fileName;

    return parts.sublist(2).join('_');
  }

  /// Validate file structure
  ///
  /// Checks:
  /// - Has valid entries
  /// - All entries are valid
  /// - No duplicate keys
  /// - Encoding is supported
  FileValidationResult validate() {
    final errors = <String>[];
    final warnings = <String>[];

    // Check encoding
    if (encoding != 'utf-8' && encoding != 'utf-16') {
      errors.add('Unsupported encoding: $encoding (must be utf-8 or utf-16)');
    }

    // Check entries
    if (entries.isEmpty) {
      warnings.add('File contains no entries');
    }

    // Validate each entry
    for (final entry in entries) {
      if (!entry.isValid()) {
        errors.add('Invalid entry at line ${entry.lineNumber}: ${entry.key}');
      }
    }

    // Check for duplicate keys
    final keysSet = <String>{};
    final duplicates = <String>[];
    for (final entry in entries) {
      if (keysSet.contains(entry.key)) {
        duplicates.add(entry.key);
      } else {
        keysSet.add(entry.key);
      }
    }

    if (duplicates.isNotEmpty) {
      errors.add('Duplicate keys found: ${duplicates.join(', ')}');
    }

    return FileValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  @override
  String toString() {
    return 'LocalizationFile(fileName: $fileName, languageCode: $languageCode, '
        'entries: ${entries.length}, encoding: $encoding)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalizationFile &&
        other.fileName == fileName &&
        other.filePath == filePath &&
        other.languageCode == languageCode &&
        other.encoding == encoding &&
        _listEquals(other.entries, entries) &&
        _listEquals(other.comments, comments) &&
        other.metadata == metadata;
  }

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return fileName.hashCode ^
        filePath.hashCode ^
        languageCode.hashCode ^
        encoding.hashCode ^
        entries.hashCode ^
        comments.hashCode ^
        metadata.hashCode;
  }
}

/// Metadata about a localization file
@JsonSerializable()
class LocalizationFileMetadata {
  /// When the file was created
  final DateTime createdAt;

  /// When the file was last modified
  final DateTime modifiedAt;

  /// File size in bytes
  final int sizeBytes;

  /// Total number of lines in file
  final int totalLines;

  /// Number of comment lines
  final int commentLines;

  /// Number of empty lines
  final int emptyLines;

  /// Original file hash (for change detection)
  final String? fileHash;

  const LocalizationFileMetadata({
    required this.createdAt,
    required this.modifiedAt,
    required this.sizeBytes,
    required this.totalLines,
    this.commentLines = 0,
    this.emptyLines = 0,
    this.fileHash,
  });

  /// Factory constructor for JSON deserialization
  factory LocalizationFileMetadata.fromJson(Map<String, dynamic> json) =>
      _$LocalizationFileMetadataFromJson(json);

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() => _$LocalizationFileMetadataToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalizationFileMetadata &&
        other.createdAt == createdAt &&
        other.modifiedAt == modifiedAt &&
        other.sizeBytes == sizeBytes &&
        other.totalLines == totalLines &&
        other.commentLines == commentLines &&
        other.emptyLines == emptyLines &&
        other.fileHash == fileHash;
  }

  @override
  int get hashCode {
    return createdAt.hashCode ^
        modifiedAt.hashCode ^
        sizeBytes.hashCode ^
        totalLines.hashCode ^
        commentLines.hashCode ^
        emptyLines.hashCode ^
        fileHash.hashCode;
  }
}

/// Result of file validation
class FileValidationResult {
  /// Whether the file is valid
  final bool isValid;

  /// List of validation errors
  final List<String> errors;

  /// List of validation warnings
  final List<String> warnings;

  const FileValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  /// Check if there are any errors
  bool get hasErrors => errors.isNotEmpty;

  /// Check if there are any warnings
  bool get hasWarnings => warnings.isNotEmpty;

  /// Get total issue count
  int get issueCount => errors.length + warnings.length;

  @override
  String toString() {
    return 'FileValidationResult(isValid: $isValid, errors: ${errors.length}, warnings: ${warnings.length})';
  }
}
