import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/editor_intents.dart';

/// Verifies that the editor's Shortcuts/Actions wiring (lifted from the top
/// bar to screen scope in this change) fires from focus contexts outside the
/// top bar — i.e. the bug we're fixing where Ctrl+Shift+T did nothing while
/// editing a grid cell.
///
/// We rebuild the same intent map used by [TranslationEditorScreen] around a
/// minimal widget tree containing a TextField that stands in for the grid
/// focus area. Building the full screen here would pull in many real
/// repository providers (handleTranslateAll → untranslated units query →
/// LLM provider config check, etc.) that aren't relevant to the shortcut
/// dispatch path itself.
void main() {
  Widget _buildHarness({
    required FocusNode searchFocus,
    required FocusNode externalFocus,
    required VoidCallback onTranslateAll,
    required VoidCallback onTranslateSelected,
    required VoidCallback onValidate,
  }) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  FocusSearchIntent(),
              SingleActivator(LogicalKeyboardKey.keyT, control: true):
                  TranslateSelectedIntent(),
              SingleActivator(LogicalKeyboardKey.keyT,
                      control: true, shift: true):
                  TranslateAllIntent(),
              SingleActivator(LogicalKeyboardKey.keyV,
                      control: true, shift: true):
                  ValidateIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                FocusSearchIntent: CallbackAction<FocusSearchIntent>(
                  onInvoke: (_) {
                    searchFocus.requestFocus();
                    return null;
                  },
                ),
                TranslateSelectedIntent:
                    CallbackAction<TranslateSelectedIntent>(
                  onInvoke: (_) {
                    onTranslateSelected();
                    return null;
                  },
                ),
                TranslateAllIntent: CallbackAction<TranslateAllIntent>(
                  onInvoke: (_) {
                    onTranslateAll();
                    return null;
                  },
                ),
                ValidateIntent: CallbackAction<ValidateIntent>(
                  onInvoke: (_) {
                    onValidate();
                    return null;
                  },
                ),
              },
              child: Column(
                children: [
                  // Stand-in for the EditorTopBar — its search field
                  // neutralizes the editor key bindings so typing here
                  // doesn't fire editor actions.
                  Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.keyT, control: true):
                          DoNothingAndStopPropagationIntent(),
                      SingleActivator(LogicalKeyboardKey.keyT,
                              control: true, shift: true):
                          DoNothingAndStopPropagationIntent(),
                      SingleActivator(LogicalKeyboardKey.keyV,
                              control: true, shift: true):
                          DoNothingAndStopPropagationIntent(),
                    },
                    child: SizedBox(
                      width: 200,
                      child: TextField(
                        focusNode: searchFocus,
                        decoration: const InputDecoration(
                          hintText: 'search',
                        ),
                      ),
                    ),
                  ),
                  // Stand-in for the grid / inspector focus area.
                  SizedBox(
                    width: 200,
                    child: TextField(
                      focusNode: externalFocus,
                      decoration: const InputDecoration(hintText: 'grid'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Ctrl+Shift+T fires TranslateAll from a non-top-bar focus context',
    (tester) async {
      var translateAllCount = 0;
      var translateSelectedCount = 0;
      var validateCount = 0;
      final searchFocus = FocusNode();
      final externalFocus = FocusNode();
      addTearDown(searchFocus.dispose);
      addTearDown(externalFocus.dispose);

      await tester.pumpWidget(_buildHarness(
        searchFocus: searchFocus,
        externalFocus: externalFocus,
        onTranslateAll: () => translateAllCount++,
        onTranslateSelected: () => translateSelectedCount++,
        onValidate: () => validateCount++,
      ));
      await tester.pumpAndSettle();

      // Focus the "grid" TextField (outside the top bar).
      externalFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(externalFocus.hasFocus, isTrue);

      // Send Ctrl+Shift+T.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(translateAllCount, 1);
      expect(translateSelectedCount, 0);
      expect(validateCount, 0);
    },
  );

  testWidgets(
    'Ctrl+F focuses the search field from a non-top-bar focus context',
    (tester) async {
      final searchFocus = FocusNode();
      final externalFocus = FocusNode();
      addTearDown(searchFocus.dispose);
      addTearDown(externalFocus.dispose);

      await tester.pumpWidget(_buildHarness(
        searchFocus: searchFocus,
        externalFocus: externalFocus,
        onTranslateAll: () {},
        onTranslateSelected: () {},
        onValidate: () {},
      ));
      await tester.pumpAndSettle();

      externalFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(externalFocus.hasFocus, isTrue);
      expect(searchFocus.hasFocus, isFalse);

      // Send Ctrl+F.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(searchFocus.hasFocus, isTrue);
    },
  );

  testWidgets(
    'Search field neutralizes Ctrl+T so typing inside it does not '
    'fire editor actions',
    (tester) async {
      var translateSelectedCount = 0;
      var translateAllCount = 0;
      final searchFocus = FocusNode();
      final externalFocus = FocusNode();
      addTearDown(searchFocus.dispose);
      addTearDown(externalFocus.dispose);

      await tester.pumpWidget(_buildHarness(
        searchFocus: searchFocus,
        externalFocus: externalFocus,
        onTranslateAll: () => translateAllCount++,
        onTranslateSelected: () => translateSelectedCount++,
        onValidate: () {},
      ));
      await tester.pumpAndSettle();

      // Focus the search field directly.
      searchFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(searchFocus.hasFocus, isTrue);

      // Press Ctrl+T while focused on the search field.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Empty Shortcuts({}) at the search field overrides parent bindings.
      expect(translateSelectedCount, 0);
      expect(translateAllCount, 0);
    },
  );
}
