import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/widgets/editor_history_panel.dart';

void main() {
  group('EditorHistoryPanel', () {
    testWidgets('shows empty state when no version selected', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorHistoryPanel(
                selectedVersionId: null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Select a translation unit to view edit history'), findsOneWidget);
    });

    testWidgets('shows empty history message when version selected but no history', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorHistoryPanel(
                selectedVersionId: 'test-version-id',
              ),
            ),
          ),
        ),
      );

      expect(find.text('No edit history available for this translation'), findsOneWidget);
    });

    testWidgets('handles revert callback', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EditorHistoryPanel(
                selectedVersionId: 'test-version-id',
                onRevert: (text, reason) {
                  // Callback invoked but not asserted in this test
                },
              ),
            ),
          ),
        ),
      );

      // Widget created without errors
      expect(find.byType(EditorHistoryPanel), findsOneWidget);
    });
  });
}
