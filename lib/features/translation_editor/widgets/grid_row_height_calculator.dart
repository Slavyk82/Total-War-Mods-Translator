import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';

/// Calculate dynamic row height based on text content.
///
/// Returns 48.0 for the header row, and at least 56.0 for body rows.
/// Measures the source and translated text using [calculateTextHeight]
/// against the column width derived from [screenWidth] minus the fixed
/// columns, adding generous padding for readability.
double calculateRowHeight(
  RowHeightDetails details,
  List<TranslationRow> rows,
  double screenWidth,
) {
  if (details.rowIndex == 0) return 48.0; // Header row

  final rowIndex = details.rowIndex - 1;
  if (rowIndex < 0 || rowIndex >= rows.length) {
    return 56.0; // Default height
  }

  final row = rows[rowIndex];
  const minHeight = 56.0;

  // Get the width available for text columns
  final fixedColumnsWidth = 50 + 60 + 150 + 120 + 150; // = 530 (removed confidence column)
  final availableWidth = screenWidth > fixedColumnsWidth
      ? screenWidth - fixedColumnsWidth
      : 400.0; // Fallback width
  final columnWidth = (availableWidth / 2).clamp(200.0, double.infinity);

  // Calculate height for both text columns
  final sourceHeight = calculateTextHeight(row.sourceText, columnWidth);
  final translatedHeight = calculateTextHeight(row.translatedText ?? '', columnWidth);

  // Use the maximum height needed, add generous padding
  final maxContentHeight = sourceHeight > translatedHeight ? sourceHeight : translatedHeight;
  final totalHeight = maxContentHeight + 32.0; // Generous padding (16px top + 16px bottom)

  return totalHeight > minHeight ? totalHeight : minHeight;
}

/// Calculate the actual height needed for text using [TextPainter].
///
/// Uses escaped text to match what the grid actually renders
/// (newlines shown as `\n`, tabs as `\t`, etc.).
double calculateTextHeight(String text, double maxWidth) {
  if (text.isEmpty) return 20.0;

  // Escape special characters to match what's actually displayed
  final escapedText = text
      .replaceAll('\r\n', '\\r\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');

  final textStyle = const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
  );

  final textSpan = TextSpan(text: escapedText, style: textStyle);
  final textPainter = TextPainter(
    text: textSpan,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );

  // Layout with available width minus padding (16px total)
  textPainter.layout(maxWidth: maxWidth - 16);

  // Add 20% extra height as safety margin
  return textPainter.height * 1.2;
}
