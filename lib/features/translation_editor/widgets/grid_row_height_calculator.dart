import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';

/// Layout constants for the translation editor data grid.
///
/// Centralises every magic number used by the row-height calculation so the
/// arithmetic can be read and audited without hunting literals in the code.
class _GridLayoutConstants {
  // Fixed column widths (confidence column removed).
  static const double checkboxColumnWidth = 50;
  static const double statusColumnWidth = 60;
  static const double sourceColumnWidth = 150;
  static const double targetColumnWidth = 120;
  static const double actionsColumnWidth = 150;

  /// Sum of the five fixed columns — leftover width is split between the
  /// source and translated text columns.
  static const double fixedColumnsTotal = checkboxColumnWidth +
      statusColumnWidth +
      sourceColumnWidth +
      targetColumnWidth +
      actionsColumnWidth; // = 530

  // Row heights. Tuned to match the editor mockup: a tighter 30px header and
  // 44px base body row. Multi-line cells still expand via the dynamic
  // measurement below — only the floor is shrunk.
  static const double headerHeight = 30.0;
  static const double rowBaseHeight = 44.0;
  static const double fallbackAvailableWidth = 400.0;

  // Text-column layout.
  /// Number of variable-width text columns (source + translated).
  static const int textColumnCount = 2;
  static const double minTextColumnWidth = 200.0;

  // Padding & safety margins.
  /// Vertical padding added around measured text (16px top + 16px bottom).
  static const double rowVerticalPadding = 32.0;

  /// Horizontal padding subtracted from the column width when laying out the
  /// text painter (8px on each side).
  static const double textPainterHorizontalPadding = 16.0;

  /// Height used for empty cells so they do not collapse.
  static const double emptyTextHeight = 20.0;

  /// Multiplier applied to measured text height as a safety margin.
  static const double textHeightSafetyMultiplier = 1.2;

  // Text style.
  static const double cellFontSize = 13;
}

/// Upper bound on the row-height cache. Past this count the least-recently
/// inserted entry is evicted. 4096 entries x ~32 bytes each ~= 128 KB - a
/// rounding error on any Flutter desktop build.
const int rowHeightCacheMaxEntries = 4096;

/// Memoised `(text, width) -> height` map for `calculateTextHeight`.
///
/// Visible for testing so the cache can be cleared between tests. Not thread
/// safe - the grid row-height callback runs on the platform thread only.
/// `_HeightKey` is library-private on purpose; tests interact with this map
/// only via `.clear()` / `.length`, never constructing keys directly.
// ignore: library_private_types_in_public_api
final LinkedHashMap<_HeightKey, double> rowHeightCache =
    LinkedHashMap<_HeightKey, double>();

class _HeightKey {
  final String text;
  final double width;
  const _HeightKey(this.text, this.width);

  @override
  bool operator ==(Object other) =>
      other is _HeightKey && other.text == text && other.width == width;

  @override
  int get hashCode => Object.hash(text, width);
}

/// Calculate dynamic row height based on text content.
///
/// Returns [_GridLayoutConstants.headerHeight] for the header row, and at
/// least [_GridLayoutConstants.rowBaseHeight] for body rows. Measures the
/// source and translated text using [calculateTextHeight] against the column
/// width derived from [screenWidth] minus the fixed columns, adding generous
/// padding for readability.
double calculateRowHeight(
  RowHeightDetails details,
  List<TranslationRow> rows,
  double screenWidth,
) {
  if (details.rowIndex == 0) return _GridLayoutConstants.headerHeight;

  final rowIndex = details.rowIndex - 1;
  if (rowIndex < 0 || rowIndex >= rows.length) {
    return _GridLayoutConstants.rowBaseHeight; // Default height
  }

  final row = rows[rowIndex];
  const minHeight = _GridLayoutConstants.rowBaseHeight;

  // Get the width available for text columns (confidence column removed).
  const fixedColumnsWidth = _GridLayoutConstants.fixedColumnsTotal;
  final availableWidth = screenWidth > fixedColumnsWidth
      ? screenWidth - fixedColumnsWidth
      : _GridLayoutConstants.fallbackAvailableWidth;
  final columnWidth =
      (availableWidth / _GridLayoutConstants.textColumnCount).clamp(
    _GridLayoutConstants.minTextColumnWidth,
    double.infinity,
  );

  // Calculate height for both text columns.
  final sourceHeight = calculateTextHeight(row.sourceText, columnWidth);
  final translatedHeight =
      calculateTextHeight(row.translatedText ?? '', columnWidth);

  // Use the maximum height needed, add generous padding.
  final maxContentHeight =
      sourceHeight > translatedHeight ? sourceHeight : translatedHeight;
  final totalHeight =
      maxContentHeight + _GridLayoutConstants.rowVerticalPadding;

  return totalHeight > minHeight ? totalHeight : minHeight;
}

/// Calculate the actual height needed for text using [TextPainter].
///
/// Uses escaped text to match what the grid actually renders
/// (newlines shown as `\n`, tabs as `\t`, etc.).
double calculateTextHeight(String text, double maxWidth) {
  if (text.isEmpty) return _GridLayoutConstants.emptyTextHeight;

  final key = _HeightKey(text, maxWidth);
  final cached = rowHeightCache.remove(key);
  if (cached != null) {
    // Reinsert at the tail to mark this entry as recently used.
    rowHeightCache[key] = cached;
    return cached;
  }

  // Escape special characters to match what's actually displayed.
  final escapedText = text
      .replaceAll('\r\n', '\\r\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');

  final textStyle = const TextStyle(
    fontSize: _GridLayoutConstants.cellFontSize,
    fontWeight: FontWeight.normal,
  );

  final textSpan = TextSpan(text: escapedText, style: textStyle);
  final textPainter = TextPainter(
    text: textSpan,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  textPainter.layout(
    maxWidth: maxWidth - _GridLayoutConstants.textPainterHorizontalPadding,
  );

  // Read the height before disposing - TextPainter.dispose releases the
  // underlying paragraph and accessing properties afterwards is undefined.
  final height = textPainter.height *
      _GridLayoutConstants.textHeightSafetyMultiplier;
  textPainter.dispose();

  rowHeightCache[key] = height;
  if (rowHeightCache.length > rowHeightCacheMaxEntries) {
    rowHeightCache.remove(rowHeightCache.keys.first);
  }
  return height;
}
