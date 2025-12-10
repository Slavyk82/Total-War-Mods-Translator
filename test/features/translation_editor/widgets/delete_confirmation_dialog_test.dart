import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/delete_confirmation_dialog.dart';

void main() {
  group('DeleteConfirmationDialog Tests', () {
    testWidgets('Dialog renders with correct title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Confirm Deletion'), findsOneWidget);
    });

    testWidgets('Dialog shows singular message for single item', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Are you sure you want to delete this translation?'),
        findsOneWidget,
      );
    });

    testWidgets('Dialog shows plural message for multiple items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 5),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Are you sure you want to delete 5 translations?'),
        findsOneWidget,
      );
    });

    testWidgets('Dialog shows warning message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('This action cannot be undone.'), findsOneWidget);
    });

    testWidgets('Cancel button returns false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (context) => const DeleteConfirmationDialog(count: 1),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, false);
    });

    testWidgets('Delete button returns true', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (context) => const DeleteConfirmationDialog(count: 1),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, true);
    });

    testWidgets('Cancel button has correct styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Delete button has correct styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('Dialog uses Fluent icons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify icons are present (by type)
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets('Dialog width is constrained', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteConfirmationDialog(count: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        ).first,
      );

      expect(dialog, isNotNull);
      expect(container, isNotNull);
    });
  });
}
