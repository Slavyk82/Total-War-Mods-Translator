import 'dart:async';
import 'dart:convert' show LineSplitter;
import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/parsers/encoding_detector.dart';

/// Parser for TSV (Tab-Separated Values) format localization files
///
/// TSV format structure:
/// - Lines starting with # are comments
/// - Empty lines are skipped
/// - Data lines: Key\tValue
/// - Special characters are escaped (\n, \t, \\, \r)
class TsvParser {
  /// Singleton instance
  static final TsvParser _instance = TsvParser._internal();

  factory TsvParser() => _instance;

  TsvParser._internal();

  final _encodingDetector = EncodingDetector();

  /// Parse TSV content from string
  ///
  /// Returns entries and comments separately
  ({List<LocalizationEntry> entries, List<String> comments})? parseString({
    required String content,
    required String fileName,
  }) {
    try {
      final entries = <LocalizationEntry>[];
      final comments = <String>[];
      final lines = content.split('\n');

      int lineNumber = 0;

      for (final line in lines) {
        lineNumber++;
        final trimmed = line.trim();

        // Skip empty lines
        if (trimmed.isEmpty) {
          continue;
        }

        // Handle comments
        if (trimmed.startsWith('#')) {
          comments.add(trimmed.substring(1).trim());
          continue;
        }

        // Parse TSV line (Key\tValue)
        final parts = trimmed.split('\t');

        if (parts.length < 2) {
          // Invalid line - skip or throw based on options
          continue;
        }

        final key = parts[0].trim();
        final value = parts.sublist(1).join('\t').trim();

        // Unescape special characters
        final unescapedValue = _unescapeValue(value);

        final entry = LocalizationEntry(
          key: key,
          value: unescapedValue,
          lineNumber: lineNumber,
        );

        entries.add(entry);
      }

      return (entries: entries, comments: comments);
    } catch (e) {
      return null;
    }
  }

  /// Parse TSV file as stream
  Stream<Result<LocalizationEntry, FileParsingException>> parseFileStream({
    required String filePath,
    String encoding = 'utf-8',
  }) async* {
    final file = File(filePath);

    if (!await file.exists()) {
      yield Err(
        FileParsingException(
          'Localization file not found: $filePath',
          filePath,
          lineNumber: 0,
        ),
      );
      return;
    }

    int lineNumber = 0;

    try {
      // Open file stream and read line by line
      final lines = file
          .openRead()
          .transform(_encodingDetector.getEncoding(encoding).decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        lineNumber++;
        final trimmed = line.trim();

        // Skip empty lines
        if (trimmed.isEmpty) {
          continue;
        }

        // Skip comments
        if (trimmed.startsWith('#')) {
          continue;
        }

        // Parse TSV line (Key\tValue)
        final parts = trimmed.split('\t');

        if (parts.length < 2) {
          // Invalid line - yield error but continue processing
          yield Err(
            FileParsingException(
              'Invalid TSV format: expected key and value separated by tab',
              filePath,
              lineNumber: lineNumber,
              rawLine: line,
            ),
          );
          continue;
        }

        final key = parts[0].trim();
        final value = parts.sublist(1).join('\t').trim();

        // Unescape special characters
        final unescapedValue = _unescapeValue(value);

        final entry = LocalizationEntry(
          key: key,
          value: unescapedValue,
          lineNumber: lineNumber,
        );

        yield Ok(entry);
      }
    } on FileSystemException catch (e) {
      yield Err(
        FileParsingException(
          'Cannot read file: ${e.message}',
          filePath,
          lineNumber: lineNumber,
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      yield Err(
        FileParsingException(
          'Unexpected error parsing file: ${e.toString()}',
          filePath,
          lineNumber: lineNumber,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Generate TSV content from entries
  String generateContent({
    required List<LocalizationEntry> entries,
    required List<String> comments,
    bool includeComments = true,
  }) {
    final buffer = StringBuffer();

    // Add comments at top
    if (includeComments && comments.isNotEmpty) {
      for (final comment in comments) {
        buffer.writeln('# $comment');
      }
      buffer.writeln();
    }

    // Add entries
    for (final entry in entries) {
      // Escape value
      final escapedValue = _escapeValue(entry.value);

      // Write TSV line
      buffer.writeln('${entry.key}\t$escapedValue');
    }

    return buffer.toString();
  }

  /// Validate TSV file structure
  ///
  /// Returns validation result with isValid, errors, and warnings
  Future<({bool isValid, List<String> errors, List<String> warnings})?> validateFile({
    required String filePath,
    required String detectedEncoding,
  }) async {
    final errors = <String>[];
    final warnings = <String>[];

    try {
      final file = File(filePath);

      // Check file is readable with detected encoding
      String content;
      try {
        content = await file.readAsString(
          encoding: _encodingDetector.getEncoding(detectedEncoding),
        );
      } catch (e) {
        errors.add('File is not readable with encoding $detectedEncoding: ${e.toString()}');
        return (
          isValid: false,
          errors: errors,
          warnings: warnings,
        );
      }

      // Parse and validate structure
      final lines = content.split('\n');
      int validEntries = 0;
      int emptyLines = 0;
      final keysSet = <String>{};
      final duplicateKeys = <String>[];

      for (var i = 0; i < lines.length; i++) {
        final lineNumber = i + 1;
        final line = lines[i];
        final trimmed = line.trim();

        // Track empty lines
        if (trimmed.isEmpty) {
          emptyLines++;
          continue;
        }

        // Track comments
        if (trimmed.startsWith('#')) {
          continue;
        }

        // Validate TSV format
        final parts = trimmed.split('\t');
        if (parts.length < 2) {
          errors.add('Line $lineNumber: Invalid TSV format (missing tab separator)');
          continue;
        }

        final key = parts[0].trim();
        final value = parts.sublist(1).join('\t').trim();

        // Check for empty keys
        if (key.isEmpty) {
          errors.add('Line $lineNumber: Empty key');
          continue;
        }

        // Check for duplicate keys
        if (keysSet.contains(key)) {
          duplicateKeys.add(key);
          warnings.add('Line $lineNumber: Duplicate key "$key"');
        } else {
          keysSet.add(key);
        }

        // Check for empty values (warning only)
        if (value.isEmpty) {
          warnings.add('Line $lineNumber: Empty value for key "$key"');
        }

        // Check for invalid characters in key
        if (key.contains('\n') || key.contains('\r')) {
          errors.add('Line $lineNumber: Key contains newline characters');
          continue;
        }

        validEntries++;
      }

      // Check if file has any valid entries
      if (validEntries == 0 && errors.isEmpty) {
        warnings.add('File contains no valid translation entries');
      }

      // Summary warnings
      if (duplicateKeys.isNotEmpty) {
        warnings.add('Found ${duplicateKeys.length} duplicate keys total');
      }

      if (emptyLines > lines.length / 2) {
        warnings.add('File has many empty lines ($emptyLines of ${lines.length})');
      }

      return (
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
      );
    } catch (e) {
      return null;
    }
  }

  /// Unescape special characters in .loc values
  ///
  /// Handles:
  /// - \\n → newline
  /// - \\t → tab
  /// - \\\\ → backslash
  /// - \\r → carriage return
  String _unescapeValue(String value) {
    return value
        .replaceAll(r'\\', '\x00') // Temporary marker for literal backslash
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\r', '\r')
        .replaceAll('\x00', '\\'); // Restore literal backslash
  }

  /// Escape special characters for .loc values
  ///
  /// Reverse of _unescapeValue
  String _escapeValue(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r');
  }
}
