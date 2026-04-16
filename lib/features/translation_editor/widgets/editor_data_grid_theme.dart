import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Maps the active [TwmtThemeTokens] to a Syncfusion [SfDataGridThemeData].
///
/// Wrapping the editor `SfDataGrid` in `SfDataGridTheme` with this data lets
/// the grid pick up palette-aware colours (header background, grid lines,
/// selection / hover / current-cell highlights, frozen pane line) without
/// hardcoding any `Colors.*` value at the call site.
SfDataGridThemeData editorGridThemeFromTokens(TwmtThemeTokens tokens) {
  return SfDataGridThemeData(
    headerColor: tokens.panel,
    gridLineColor: tokens.border,
    selectionColor: tokens.accentBg,
    currentCellStyle: DataGridCurrentCellStyle(
      borderColor: tokens.accent,
      borderWidth: 1.0,
    ),
    rowHoverColor: tokens.panel2,
    rowHoverTextStyle: TextStyle(color: tokens.text),
    frozenPaneLineColor: tokens.border,
  );
}
