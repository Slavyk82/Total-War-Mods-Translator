import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Maps [TwmtThemeTokens] to a Syncfusion [SfDataGridThemeData].
/// Single source of truth for any list screen using SfDataGrid:
/// editor, glossary, translation memory.
SfDataGridThemeData buildTokenDataGridTheme(TwmtThemeTokens tokens) {
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
