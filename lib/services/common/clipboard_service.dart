import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../models/domain/translation_version.dart';
import '../../models/domain/translation_unit.dart';

/// Service for clipboard operations with TSV formatting
///
/// Provides methods to copy translation data to clipboard in various formats,
/// particularly TSV (Tab-Separated Values) for Excel compatibility.
class ClipboardService {
  /// Copy selected units to clipboard in TSV format
  ///
  /// Format: Key\tSource Text\tTranslated Text\tStatus
  /// This format is Excel-compatible and can be pasted directly into spreadsheets.
  ///
  /// [units] - Translation units with source text
  /// [versions] - Translation versions with translated text
  static Future<void> copyUnitsToClipboard({
    required List<TranslationUnit> units,
    required List<TranslationVersion> versions,
  }) async {
    // Create a map of unit ID to version for quick lookup
    final versionMap = <String, TranslationVersion>{};
    for (final version in versions) {
      versionMap[version.unitId] = version;
    }

    // Build TSV content
    final buffer = StringBuffer();

    // Add header row
    buffer.writeln('Key\tSource Text\tTranslated Text\tStatus');

    // Add data rows
    for (final unit in units) {
      final version = versionMap[unit.id];
      final translatedText = version?.translatedText ?? '';
      final status = version?.statusDisplay ?? 'Pending';

      // Escape any tabs or newlines in the data
      final key = _escapeTsvField(unit.key);
      final sourceText = _escapeTsvField(unit.sourceText);
      final translated = _escapeTsvField(translatedText);

      buffer.writeln('$key\t$sourceText\t$translated\t$status');
    }

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
  }

  /// Copy selected versions to clipboard in TSV format
  ///
  /// Simplified version when only translation versions are available
  /// (without full unit details).
  ///
  /// Format: Unit ID\tTranslated Text\tStatus
  static Future<void> copyVersionsToClipboard(
    List<TranslationVersion> versions,
  ) async {
    final buffer = StringBuffer();

    // Add header row
    buffer.writeln('Unit ID\tTranslated Text\tStatus');

    // Add data rows
    for (final version in versions) {
      final translatedText = _escapeTsvField(version.translatedText ?? '');
      final status = version.statusDisplay;

      buffer.writeln(
        '${version.unitId}\t$translatedText\t$status',
      );
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
  }

  /// Copy single field to clipboard
  ///
  /// Simple text copy operation for copying individual fields.
  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Copy multiple texts as a list (one per line)
  static Future<void> copyTextList(List<String> texts) async {
    final content = texts.join('\n');
    await Clipboard.setData(ClipboardData(text: content));
  }

  /// Copy units in CSV format with proper escaping
  ///
  /// CSV format uses commas as delimiters and quotes for fields containing
  /// commas, quotes, or newlines.
  static Future<void> copyUnitsToCsv({
    required List<TranslationUnit> units,
    required List<TranslationVersion> versions,
  }) async {
    final versionMap = <String, TranslationVersion>{};
    for (final version in versions) {
      versionMap[version.unitId] = version;
    }

    final buffer = StringBuffer();

    // Add header row
    buffer.writeln('"Key","Source Text","Translated Text","Status"');

    // Add data rows
    for (final unit in units) {
      final version = versionMap[unit.id];
      final translatedText = version?.translatedText ?? '';
      final status = version?.statusDisplay ?? 'Pending';

      final key = _escapeCsvField(unit.key);
      final sourceText = _escapeCsvField(unit.sourceText);
      final translated = _escapeCsvField(translatedText);

      buffer.writeln('$key,$sourceText,$translated,"$status"');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
  }

  /// Copy units in JSON format
  static Future<void> copyUnitsToJson({
    required List<TranslationUnit> units,
    required List<TranslationVersion> versions,
  }) async {
    final versionMap = <String, TranslationVersion>{};
    for (final version in versions) {
      versionMap[version.unitId] = version;
    }

    final items = units.map((unit) {
      final version = versionMap[unit.id];
      return {
        'key': unit.key,
        'sourceText': unit.sourceText,
        'translatedText': version?.translatedText,
        'status': version?.statusDisplay,
      };
    }).toList();

    // Simple JSON formatting (not using dart:convert to avoid dependencies)
    final buffer = StringBuffer();
    buffer.writeln('[');
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      buffer.write('  {');
      buffer.write('"key": "${_escapeJson(item['key'])}", ');
      buffer.write('"sourceText": "${_escapeJson(item['sourceText'])}", ');
      buffer.write('"translatedText": "${_escapeJson(item['translatedText'])}", ');
      buffer.write('"status": "${item['status']}"');
      buffer.write('}');
      if (i < items.length - 1) buffer.write(',');
      buffer.writeln();
    }
    buffer.writeln(']');

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
  }

  /// Show success toast notification after copy
  ///
  /// Displays a temporary notification informing the user that
  /// items were successfully copied to clipboard.
  static void showCopySuccess(BuildContext context, int count) {
    FluentToast.success(
      context,
      'Copied $count item${count == 1 ? '' : 's'} to clipboard',
    );
  }

  /// Show error toast notification
  static void showCopyError(BuildContext context, String message) {
    FluentToast.error(context, 'Failed to copy: $message');
  }

  // ============================================================================
  // Private helper methods
  // ============================================================================

  /// Escape field for TSV format
  ///
  /// Replaces tabs with spaces and newlines with spaces to prevent
  /// breaking the TSV structure.
  static String _escapeTsvField(String field) {
    return field
        .replaceAll('\t', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .trim();
  }

  /// Escape field for CSV format
  ///
  /// Wraps field in quotes and escapes internal quotes by doubling them.
  static String _escapeCsvField(String field) {
    // If field contains comma, quote, or newline, wrap in quotes
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      // Escape quotes by doubling them
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return '"$field"';
  }

  /// Escape string for JSON format
  static String _escapeJson(dynamic value) {
    if (value == null) return '';
    final str = value.toString();
    return str
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
