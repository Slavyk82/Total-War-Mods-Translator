import 'dart:io';
import '../models/localization_entry.dart';
import '../models/localization_file.dart';

/// Utility for validating file structure and content
///
/// Provides validation for:
/// - File format (TSV structure)
/// - Entry validity (key-value format)
/// - Duplicate detection
/// - Character encoding
/// - Common file issues
class FileValidator {
  /// Singleton instance
  static final FileValidator _instance = FileValidator._internal();

  factory FileValidator() => _instance;

  FileValidator._internal();

  /// Validate localization file structure
  ///
  /// Performs comprehensive validation:
  /// - Entry validity
  /// - Duplicate key detection
  /// - Character encoding issues
  /// - File size limits
  /// - Common formatting problems
  ///
  /// [file]: LocalizationFile to validate
  /// [options]: Validation options
  ///
  /// Returns ValidationResult with errors and warnings
  FileValidationResult validateLocalizationFile(
    LocalizationFile file, {
    ValidationOptions? options,
  }) {
    final opts = options ?? ValidationOptions.defaultOptions;
    final errors = <String>[];
    final warnings = <String>[];

    // Validate encoding
    if (!_isValidEncoding(file.encoding)) {
      errors.add(
          'Invalid encoding: ${file.encoding} (must be utf-8 or utf-16)');
    }

    // Validate entries
    if (file.entries.isEmpty) {
      if (opts.requireEntries) {
        errors.add('File contains no entries');
      } else {
        warnings.add('File contains no entries');
      }
    }

    // Validate each entry
    for (final entry in file.entries) {
      final entryResult = validateEntry(entry, options: opts);
      if (!entryResult.isValid) {
        errors.addAll(entryResult.errors);
      }
      warnings.addAll(entryResult.warnings);
    }

    // Check for duplicate keys
    final duplicates = _findDuplicateKeys(file.entries);
    if (duplicates.isNotEmpty) {
      errors.add('Duplicate keys found: ${duplicates.join(', ')}');
    }

    // Check file size
    if (opts.maxEntriesPerFile > 0 &&
        file.entries.length > opts.maxEntriesPerFile) {
      warnings.add(
          'File has ${file.entries.length} entries (recommended max: ${opts.maxEntriesPerFile})');
    }

    // Check for suspiciously short/long values
    final valueStats = _analyzeValueLengths(file.entries);
    if (valueStats.hasExtremelyShortValues) {
      warnings.add(
          'Found ${valueStats.shortValueCount} entries with very short values (<3 characters)');
    }
    if (valueStats.hasExtremelyLongValues) {
      warnings.add(
          'Found ${valueStats.longValueCount} entries with very long values (>1000 characters)');
    }

    // Check for encoding issues
    final encodingIssues = _detectEncodingIssues(file.entries);
    if (encodingIssues.isNotEmpty) {
      warnings.add(
          'Possible encoding issues in ${encodingIssues.length} entries');
    }

    return FileValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Validate a single localization entry
  ///
  /// [entry]: Entry to validate
  /// [options]: Validation options
  ///
  /// Returns ValidationResult
  EntryValidationResult validateEntry(
    LocalizationEntry entry, {
    ValidationOptions? options,
  }) {
    final opts = options ?? ValidationOptions.defaultOptions;
    final errors = <String>[];
    final warnings = <String>[];

    // Validate key
    if (entry.key.trim().isEmpty) {
      errors.add('Entry has empty key');
    }

    if (entry.key.contains('\t')) {
      errors.add('Key contains tab character: ${entry.key}');
    }

    if (entry.key.contains('\n') || entry.key.contains('\r')) {
      errors.add('Key contains newline character: ${entry.key}');
    }

    // Validate key format
    if (opts.validateKeyFormat) {
      if (!_isValidKeyFormat(entry.key)) {
        warnings.add('Key has unusual format: ${entry.key}');
      }
    }

    // Validate value
    if (opts.requireNonEmptyValues && entry.value.trim().isEmpty) {
      errors.add('Entry has empty value: ${entry.key}');
    }

    // Check for unescaped special characters
    if (opts.checkEscaping) {
      final unescapedIssues = _findUnescapedCharacters(entry.value);
      if (unescapedIssues.isNotEmpty) {
        warnings.add('Possible unescaped characters in ${entry.key}: '
            '${unescapedIssues.join(', ')}');
      }
    }

    // Check value length
    if (entry.value.length > opts.maxValueLength) {
      warnings.add('Very long value in ${entry.key}: ${entry.value.length} '
          'characters (max: ${opts.maxValueLength})');
    }

    return EntryValidationResult(
      key: entry.key,
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Validate TSV line format
  ///
  /// Checks if a line is valid TSV:
  /// - Has exactly one tab separator
  /// - Non-empty key
  /// - Valid characters
  ///
  /// [line]: Line to validate
  ///
  /// Returns true if valid
  bool validateTsvLine(String line) {
    if (line.trim().isEmpty) return false;
    if (line.trim().startsWith('#')) return true; // Comment line

    final tabIndex = line.indexOf('\t');
    if (tabIndex == -1) return false; // No tab separator

    final key = line.substring(0, tabIndex).trim();
    if (key.isEmpty) return false; // Empty key

    return true;
  }

  /// Check if file encoding is valid
  bool _isValidEncoding(String encoding) {
    final normalized = encoding.toLowerCase();
    return normalized == 'utf-8' || normalized == 'utf-16';
  }

  /// Find duplicate keys in entries
  List<String> _findDuplicateKeys(List<LocalizationEntry> entries) {
    final keysSeen = <String>{};
    final duplicates = <String>[];

    for (final entry in entries) {
      if (keysSeen.contains(entry.key)) {
        if (!duplicates.contains(entry.key)) {
          duplicates.add(entry.key);
        }
      } else {
        keysSeen.add(entry.key);
      }
    }

    return duplicates;
  }

  /// Validate key format
  ///
  /// Total War keys typically follow patterns like:
  /// - unit_description_wh_main_grn_goblins
  /// - building_name_romani_temple_1
  ///
  /// Valid characters: a-z, A-Z, 0-9, _, -
  bool _isValidKeyFormat(String key) {
    // Must contain at least one underscore or hyphen (convention)
    if (!key.contains('_') && !key.contains('-')) {
      return false;
    }

    // Should only contain alphanumeric, underscore, hyphen
    final validPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');
    return validPattern.hasMatch(key);
  }

  /// Analyze value lengths for statistics
  ValueLengthStats _analyzeValueLengths(List<LocalizationEntry> entries) {
    int shortValues = 0; // < 3 characters
    int longValues = 0; // > 1000 characters

    for (final entry in entries) {
      final length = entry.value.length;
      if (length < 3 && length > 0) shortValues++;
      if (length > 1000) longValues++;
    }

    return ValueLengthStats(
      shortValueCount: shortValues,
      longValueCount: longValues,
    );
  }

  /// Find entries with possible unescaped characters
  ///
  /// Looks for patterns that might indicate unescaped special chars
  List<String> _findUnescapedCharacters(String value) {
    final issues = <String>[];

    // Check for literal tab characters (should be \t)
    if (value.contains('\t')) {
      issues.add('literal tab');
    }

    // Check for suspicious backslash patterns
    // (single backslash not followed by n, t, r, \)
    if (RegExp(r'\\(?![ntr\\])').hasMatch(value)) {
      issues.add('suspicious backslash');
    }

    return issues;
  }

  /// Detect possible encoding issues in entries
  ///
  /// Looks for:
  /// - Replacement characters (�)
  /// - Invalid UTF-8 sequences
  /// - Mojibake patterns
  List<String> _detectEncodingIssues(List<LocalizationEntry> entries) {
    final issueKeys = <String>[];

    for (final entry in entries) {
      // Check for replacement character
      if (entry.value.contains('�')) {
        issueKeys.add(entry.key);
        continue;
      }

      // Check for common mojibake patterns (e.g., "Ã©" instead of "é")
      if (_hasMojibakePattern(entry.value)) {
        issueKeys.add(entry.key);
      }
    }

    return issueKeys;
  }

  /// Check if text has mojibake pattern
  ///
  /// Common mojibake:
  /// - Multiple accented characters in sequence
  /// - Invalid character combinations
  bool _hasMojibakePattern(String text) {
    // Check for suspicious sequences like "Ã©", "Ã¨", etc.
    return RegExp(r'Ã[©èêëàáâäùúûü]').hasMatch(text);
  }

  /// Validate file path
  ///
  /// Checks:
  /// - Path is not empty
  /// - Path is absolute (recommended)
  /// - File extension is .loc
  /// - Directory exists
  ///
  /// [filePath]: Path to validate
  ///
  /// Returns validation result
  PathValidationResult validatePath(String filePath) {
    final errors = <String>[];
    final warnings = <String>[];

    if (filePath.trim().isEmpty) {
      errors.add('File path is empty');
      return PathValidationResult(
        path: filePath,
        isValid: false,
        errors: errors,
        warnings: warnings,
      );
    }

    // Check if absolute path
    if (!_isAbsolutePath(filePath)) {
      warnings.add('Relative path (absolute recommended): $filePath');
    }

    // Check extension
    if (!filePath.toLowerCase().endsWith('.loc')) {
      warnings.add('File does not have .loc extension: $filePath');
    }

    // Check if directory exists
    final file = File(filePath);
    final dir = file.parent;
    if (!dir.existsSync()) {
      errors.add('Directory does not exist: ${dir.path}');
    }

    return PathValidationResult(
      path: filePath,
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Check if path is absolute
  bool _isAbsolutePath(String path) {
    // Windows: C:\, D:\, etc.
    if (RegExp(r'^[A-Za-z]:\\').hasMatch(path)) return true;

    // Unix: /
    if (path.startsWith('/')) return true;

    return false;
  }
}

/// Options for file validation
class ValidationOptions {
  /// Whether to require at least one entry
  final bool requireEntries;

  /// Whether to require non-empty values
  final bool requireNonEmptyValues;

  /// Whether to validate key format (naming conventions)
  final bool validateKeyFormat;

  /// Whether to check for proper escaping
  final bool checkEscaping;

  /// Maximum value length (0 = no limit)
  final int maxValueLength;

  /// Maximum entries per file (0 = no limit)
  final int maxEntriesPerFile;

  const ValidationOptions({
    this.requireEntries = false,
    this.requireNonEmptyValues = true,
    this.validateKeyFormat = true,
    this.checkEscaping = true,
    this.maxValueLength = 10000,
    this.maxEntriesPerFile = 50000,
  });

  /// Default validation options
  static const ValidationOptions defaultOptions = ValidationOptions();

  /// Strict validation
  static const ValidationOptions strict = ValidationOptions(
    requireEntries: true,
    requireNonEmptyValues: true,
    validateKeyFormat: true,
    checkEscaping: true,
    maxValueLength: 5000,
    maxEntriesPerFile: 10000,
  );

  /// Lenient validation
  static const ValidationOptions lenient = ValidationOptions(
    requireEntries: false,
    requireNonEmptyValues: false,
    validateKeyFormat: false,
    checkEscaping: false,
    maxValueLength: 0,
    maxEntriesPerFile: 0,
  );
}

/// Result of entry validation
class EntryValidationResult {
  /// Entry key
  final String key;

  /// Whether entry is valid
  final bool isValid;

  /// Validation errors
  final List<String> errors;

  /// Validation warnings
  final List<String> warnings;

  const EntryValidationResult({
    required this.key,
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  @override
  String toString() {
    return 'EntryValidationResult(key: $key, isValid: $isValid, '
        'errors: ${errors.length}, warnings: ${warnings.length})';
  }
}

/// Result of path validation
class PathValidationResult {
  /// File path
  final String path;

  /// Whether path is valid
  final bool isValid;

  /// Validation errors
  final List<String> errors;

  /// Validation warnings
  final List<String> warnings;

  const PathValidationResult({
    required this.path,
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  @override
  String toString() {
    return 'PathValidationResult(path: $path, isValid: $isValid, '
        'errors: ${errors.length}, warnings: ${warnings.length})';
  }
}

/// Statistics about value lengths
class ValueLengthStats {
  /// Number of very short values (< 3 characters)
  final int shortValueCount;

  /// Number of very long values (> 1000 characters)
  final int longValueCount;

  const ValueLengthStats({
    required this.shortValueCount,
    required this.longValueCount,
  });

  /// Whether there are extremely short values
  bool get hasExtremelyShortValues => shortValueCount > 0;

  /// Whether there are extremely long values
  bool get hasExtremelyLongValues => longValueCount > 0;

  @override
  String toString() {
    return 'ValueLengthStats(short: $shortValueCount, long: $longValueCount)';
  }
}
