import 'package:flutter/widgets.dart';

/// Intent fired when the user requests focusing the editor search field
/// (Ctrl+F).
class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

/// Intent fired when the user requests translating the current selection
/// (Ctrl+T). The screen-level handler must guard on selection state.
class TranslateSelectedIntent extends Intent {
  const TranslateSelectedIntent();
}

/// Intent fired when the user requests translating all visible rows
/// (Ctrl+Shift+T).
class TranslateAllIntent extends Intent {
  const TranslateAllIntent();
}

/// Intent fired when the user requests running validation (Ctrl+Shift+V).
class ValidateIntent extends Intent {
  const ValidateIntent();
}
