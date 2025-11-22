import 'package:json_annotation/json_annotation.dart';

part 'localization_entry.g.dart';

/// Represents a single localization entry (key-value pair) in a .loc file
///
/// .loc files use TSV (Tab-Separated Values) format:
/// - Column 1: Key (unique identifier)
/// - Column 2: Value (translated text)
/// - Optional: Comments (lines starting with #)
/// - Optional: Multi-line values (escaped with \n)
@JsonSerializable()
class LocalizationEntry {
  /// Unique key identifying this entry
  ///
  /// Example: "unit_description_wh_main_grn_goblins"
  final String key;

  /// Localized text value
  ///
  /// May contain:
  /// - Escaped characters (\n, \t, \\)
  /// - Multi-line text (using \n)
  /// - Special formatting (BBCode, XML tags)
  final String value;

  /// Line number in source file (for error reporting)
  final int? lineNumber;

  /// Original raw value (before processing escapes)
  final String? rawValue;

  /// Whether this entry was modified during parsing
  ///
  /// Used to track changes for validation/debugging
  final bool isModified;

  const LocalizationEntry({
    required this.key,
    required this.value,
    this.lineNumber,
    this.rawValue,
    this.isModified = false,
  });

  /// Factory constructor for JSON deserialization
  factory LocalizationEntry.fromJson(Map<String, dynamic> json) =>
      _$LocalizationEntryFromJson(json);

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() => _$LocalizationEntryToJson(this);

  /// Create a copy with modified fields
  LocalizationEntry copyWith({
    String? key,
    String? value,
    int? lineNumber,
    String? rawValue,
    bool? isModified,
  }) {
    return LocalizationEntry(
      key: key ?? this.key,
      value: value ?? this.value,
      lineNumber: lineNumber ?? this.lineNumber,
      rawValue: rawValue ?? this.rawValue,
      isModified: isModified ?? this.isModified,
    );
  }

  /// Create an entry from a TSV line
  ///
  /// Parses a tab-separated line:
  /// - Splits on first tab (key\tvalue)
  /// - Processes escape sequences
  /// - Handles multi-line values
  factory LocalizationEntry.fromTsvLine(String line, {int? lineNumber}) {
    if (line.trim().isEmpty || line.trim().startsWith('#')) {
      throw FormatException('Not a valid entry line', line);
    }

    // Split on first tab only
    final tabIndex = line.indexOf('\t');
    if (tabIndex == -1) {
      throw FormatException('Invalid TSV format: no tab separator', line);
    }

    final key = line.substring(0, tabIndex).trim();
    final rawValue = line.substring(tabIndex + 1);
    final value = _processEscapeSequences(rawValue);

    return LocalizationEntry(
      key: key,
      value: value,
      lineNumber: lineNumber,
      rawValue: rawValue,
      isModified: false,
    );
  }

  /// Convert to TSV line format
  ///
  /// Escapes special characters and formats as key\tvalue
  String toTsvLine() {
    final escapedValue = _escapeSpecialCharacters(value);
    return '$key\t$escapedValue';
  }

  /// Process escape sequences in value
  ///
  /// Converts:
  /// - \n → newline
  /// - \t → tab
  /// - \\ → backslash
  /// - \r → carriage return
  static String _processEscapeSequences(String text) {
    return text
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\\', '\\');
  }

  /// Escape special characters for TSV output
  ///
  /// Converts:
  /// - newline → \n
  /// - tab → \t
  /// - backslash → \\
  /// - carriage return → \r
  static String _escapeSpecialCharacters(String text) {
    return text
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t')
        .replaceAll('\r', r'\r');
  }

  /// Validate entry format
  ///
  /// Checks:
  /// - Key is not empty
  /// - Key contains only valid characters
  /// - Value is not null (can be empty)
  bool isValid() {
    if (key.trim().isEmpty) return false;

    // Key should not contain tabs, newlines, or invalid characters
    if (key.contains('\t') || key.contains('\n') || key.contains('\r')) {
      return false;
    }

    return true;
  }

  @override
  String toString() {
    return 'LocalizationEntry(key: $key, value: ${value.length > 50 ? '${value.substring(0, 50)}...' : value})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalizationEntry &&
        other.key == key &&
        other.value == value &&
        other.lineNumber == lineNumber &&
        other.rawValue == rawValue &&
        other.isModified == isModified;
  }

  @override
  int get hashCode {
    return key.hashCode ^
        value.hashCode ^
        lineNumber.hashCode ^
        rawValue.hashCode ^
        isModified.hashCode;
  }
}
