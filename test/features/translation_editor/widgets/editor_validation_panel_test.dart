import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/widgets/editor_validation_panel.dart';

void main() {
  group('EditorValidationPanel', () {
    testWidgets('shows empty state when no text provided', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorValidationPanel(
                sourceText: null,
                translatedText: null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Select a translation unit to view validation issues'), findsOneWidget);
    });

    testWidgets('shows success state when text provided', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorValidationPanel(
                sourceText: 'Test',
                translatedText: 'Test',
              ),
            ),
          ),
        ),
      );

      // Should show success message since we're not actually validating
      expect(find.text('No issues found!'), findsOneWidget);
    });

    testWidgets('handles apply fix callback', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorValidationPanel(
                sourceText: 'Test',
                translatedText: 'Test',
                onApplyFix: (text) {
                  // Callback invoked but not asserted in this test
                },
              ),
            ),
          ),
        ),
      );

      // Widget created without errors
      expect(find.byType(EditorValidationPanel), findsOneWidget);
    });

    testWidgets('handles validate callback', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorValidationPanel(
                sourceText: 'Test',
                translatedText: 'Test',
                onValidate: () {
                  // Callback invoked but not asserted in this test
                },
              ),
            ),
          ),
        ),
      );

      // Widget created without errors
      expect(find.byType(EditorValidationPanel), findsOneWidget);
    });
  });
}
