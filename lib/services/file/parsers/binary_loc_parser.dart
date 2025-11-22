import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Parser for binary .loc format files (Total War games)
///
/// Binary .loc files use UTF-16 LE encoding with a specific structure:
/// - Optional BOM (FF FE)
/// - Optional LOC header (12 bytes)
/// - Entries with 3 fields (key, text, tooltip)
/// - Each field has a 2-byte length prefix followed by UTF-16 LE string
///
/// Entry type detection:
/// - Type 1: [identifier, short_text, subtitle_identifier]
/// - Type 2: [short_title, description_identifier, long_description_text]
class BinaryLocParser {
  /// Singleton instance
  static final BinaryLocParser _instance = BinaryLocParser._internal();

  factory BinaryLocParser() => _instance;

  BinaryLocParser._internal();

  /// Parse binary LOC file and extract entries
  Future<Result<List<LocalizationEntry>, FileParsingException>> parseFile({
    required String filePath,
    required List<int> bytes,
  }) async {
    try {
      final fileName = File(filePath).uri.pathSegments.last;
      final entries = <LocalizationEntry>[];

      // Check minimum file size
      if (bytes.length < 10) {
        return Err(
          FileParsingException(
            'File too small to be a valid LOC file',
            fileName,
            lineNumber: 0,
          ),
        );
      }

      int offset = 0;

      // Skip BOM if present (FF FE for UTF-16 LE)
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        offset = 2;
      }

      // Check for LOC header
      if (offset + 4 <= bytes.length) {
        final header = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        if (header.startsWith('LOC')) {
          // Skip header: LOC\0 (4 bytes) + version (4 bytes) + entry count/offset (4 bytes)
          offset += 12;
        }
      }

      // Parse entries
      int entryNumber = 0;
      while (offset < bytes.length - 3) {
        entryNumber++;

        // Skip single null byte separator if present (between entries)
        if (entryNumber > 1 && bytes[offset] == 0 && bytes[offset + 1] != 0) {
          offset += 1;
          if (offset >= bytes.length - 2) break;
        }

        // Parse entry with 3 fields
        final entryResult = _parseEntry(bytes, offset, entryNumber);
        if (entryResult.isErr) {
          // End of valid data
          break;
        }

        final parsedEntry = entryResult.value;
        offset = parsedEntry.nextOffset;

        entries.add(parsedEntry.entry);
      }

      return Ok(entries);
    } catch (e, stackTrace) {
      return Err(
        FileParsingException(
          'Failed to parse binary LOC file: ${e.toString()}',
          filePath,
          lineNumber: 0,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Parse a single entry (key, text, tooltip triplet)
  Result<_ParsedEntry, FileParsingException> _parseEntry(
    List<int> bytes,
    int offset,
    int entryNumber,
  ) {
    try {
      // Read key field
      final keyResult = _readUtf16Field(bytes, offset);
      if (keyResult.isErr) {
        return Err(keyResult.error);
      }
      final key = keyResult.value.text;
      offset = keyResult.value.nextOffset;

      // Skip single null byte separator if present (between key and text)
      if (offset < bytes.length &&
          bytes[offset] == 0 &&
          offset + 1 < bytes.length &&
          bytes[offset + 1] != 0) {
        offset += 1;
      }

      // Read text field
      if (offset + 2 > bytes.length) {
        return Err(
          FileParsingException(
            'Incomplete entry: missing text field',
            'binary_loc',
            lineNumber: entryNumber,
          ),
        );
      }

      final textResult = _readUtf16Field(bytes, offset);
      if (textResult.isErr) {
        return Err(textResult.error);
      }
      final text = textResult.value.text;
      offset = textResult.value.nextOffset;

      // Skip single null byte separator if present (between text and tooltip)
      if (offset < bytes.length &&
          bytes[offset] == 0 &&
          offset + 1 < bytes.length &&
          bytes[offset + 1] != 0) {
        offset += 1;
      }

      // Read tooltip field
      if (offset + 2 > bytes.length) {
        return Err(
          FileParsingException(
            'Incomplete entry: missing tooltip field',
            'binary_loc',
            lineNumber: entryNumber,
          ),
        );
      }

      final tooltipResult = _readUtf16Field(bytes, offset);
      if (tooltipResult.isErr) {
        return Err(tooltipResult.error);
      }
      final tooltip = tooltipResult.value.text;
      offset = tooltipResult.value.nextOffset;

      // Detect entry type and extract key-value pair
      final detectedEntry = _detectEntryType(key, text, tooltip, entryNumber);

      return Ok(_ParsedEntry(
        entry: detectedEntry,
        nextOffset: offset,
      ));
    } catch (e, stackTrace) {
      return Err(
        FileParsingException(
          'Error parsing entry: ${e.toString()}',
          'binary_loc',
          lineNumber: entryNumber,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Read a UTF-16 LE field with 2-byte length prefix
  Result<_FieldData, FileParsingException> _readUtf16Field(
    List<int> bytes,
    int offset,
  ) {
    try {
      // Read length (2 bytes, little endian)
      if (offset + 2 > bytes.length) {
        return Err(
          FileParsingException(
            'Not enough bytes for field length',
            'binary_loc',
            lineNumber: 0,
          ),
        );
      }

      final length = bytes[offset] | (bytes[offset + 1] << 8);
      offset += 2;

      // Validate length
      if (length == 0) {
        return Ok(_FieldData(text: '', nextOffset: offset));
      }

      if (offset + length * 2 > bytes.length) {
        return Err(
          FileParsingException(
            'Not enough bytes for field data',
            'binary_loc',
            lineNumber: 0,
          ),
        );
      }

      // Read UTF-16 LE string
      final fieldBytes = bytes.sublist(offset, offset + length * 2);
      final text = String.fromCharCodes(
        [for (int i = 0; i < length; i++)
          fieldBytes[i * 2] | (fieldBytes[i * 2 + 1] << 8)],
      );
      offset += length * 2;

      return Ok(_FieldData(text: text, nextOffset: offset));
    } catch (e) {
      return Err(
        FileParsingException(
          'Error reading UTF-16 field: ${e.toString()}',
          'binary_loc',
          lineNumber: 0,
          error: e,
        ),
      );
    }
  }

  /// Detect entry type based on field content patterns
  ///
  /// Type 1 (title entries): [identifier, short_text, subtitle_identifier]
  ///   Example: ["wh2_main_hef_prince_title", "The Glittering Host", "wh2_main_hef_prince_subtitle"]
  ///   Use: key as KEY, text as VALUE
  ///
  /// Type 2 (description entries): [short_title, description_identifier, long_description_text]
  ///   Example: ["Commanders of Ulthuan", "wh2_main_hef_prince_description", "The noble families..."]
  ///   Use: text as KEY, tooltip as VALUE
  ///
  /// Keys (identifiers) have underscores and no spaces
  /// Natural language text has spaces
  LocalizationEntry _detectEntryType(
    String key,
    String text,
    String tooltip,
    int entryNumber,
  ) {
    final keyLooksLikeIdentifier = key.contains('_') && !key.contains(' ');
    final textLooksLikeIdentifier = text.contains('_') && !text.contains(' ');
    final tooltipLooksLikeIdentifier = tooltip.contains('_') && !tooltip.contains(' ');

    String finalKey;
    String finalValue;

    // Type 1: Key is identifier, text is short natural language, tooltip is another identifier
    // Use: key as KEY, text as VALUE
    if (keyLooksLikeIdentifier && !textLooksLikeIdentifier) {
      finalKey = key;
      finalValue = text;
    }
    // Type 2: Key is natural language, text is identifier, tooltip is long natural language
    // Use: text as KEY, tooltip as VALUE
    else if (!keyLooksLikeIdentifier && textLooksLikeIdentifier && !tooltipLooksLikeIdentifier) {
      finalKey = text;
      finalValue = tooltip;
    }
    // Fallback: use key/text as before
    else {
      finalKey = key;
      finalValue = text;
    }

    return LocalizationEntry(
      key: finalKey,
      value: finalValue,
      lineNumber: entryNumber,
    );
  }
}

/// Internal class for parsed field data
class _FieldData {
  final String text;
  final int nextOffset;

  _FieldData({required this.text, required this.nextOffset});
}

/// Internal class for parsed entry with offset
class _ParsedEntry {
  final LocalizationEntry entry;
  final int nextOffset;

  _ParsedEntry({required this.entry, required this.nextOffset});
}
