import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/clear_confirmation_dialog.dart';
import 'package:twmt/features/translation_editor/widgets/clear_progress_dialog.dart';
import 'package:twmt/features/translation_editor/widgets/delete_confirmation_dialog.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Pumps a host with a button that opens [dialog] via `showDialog<bool>` and
/// returns the captured pop value through [resultRef].
Future<void> _openDialog(
  WidgetTester tester,
  Widget dialog,
  void Function(bool?) onResult,
) async {
  await tester.pumpWidget(createThemedTestableWidget(
    Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () async {
            onResult(await showDialog<bool>(
              context: context,
              builder: (_) => dialog,
            ));
          },
          child: const Text('open'),
        ),
      ),
    ),
    theme: AppTheme.atelierDarkTheme,
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('DeleteConfirmationDialog', () {
    testWidgets('renders singular message for count == 1', (tester) async {
      await _openDialog(
        tester,
        const DeleteConfirmationDialog(count: 1),
        (_) {},
      );

      expect(find.text('Confirm Deletion'), findsOneWidget);
      expect(
        find.text('Are you sure you want to delete this translation?'),
        findsOneWidget,
      );
      expect(find.text('This action cannot be undone.'), findsOneWidget);
    });

    testWidgets('renders pluralised message for count > 1', (tester) async {
      await _openDialog(
        tester,
        const DeleteConfirmationDialog(count: 3),
        (_) {},
      );

      expect(
        find.text('Are you sure you want to delete 3 translations?'),
        findsOneWidget,
      );
    });

    testWidgets('confirm button pops true', (tester) async {
      bool? result;
      await _openDialog(
        tester,
        const DeleteConfirmationDialog(count: 1),
        (r) => result = r,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancel button pops false', (tester) async {
      bool? result;
      await _openDialog(
        tester,
        const DeleteConfirmationDialog(count: 1),
        (r) => result = r,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('ClearConfirmationDialog', () {
    testWidgets('renders singular message for count == 1', (tester) async {
      await _openDialog(
        tester,
        const ClearConfirmationDialog(count: 1),
        (_) {},
      );

      expect(find.text('Confirm Clear'), findsOneWidget);
      expect(
        find.text('Are you sure you want to clear this translation?'),
        findsOneWidget,
      );
    });

    testWidgets('renders pluralised message for count > 1', (tester) async {
      await _openDialog(
        tester,
        const ClearConfirmationDialog(count: 5),
        (_) {},
      );

      expect(
        find.text('Are you sure you want to clear 5 translations?'),
        findsOneWidget,
      );
    });

    testWidgets('clear button pops true', (tester) async {
      bool? result;
      await _openDialog(
        tester,
        const ClearConfirmationDialog(count: 2),
        (r) => result = r,
      );

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancel button pops false', (tester) async {
      bool? result;
      await _openDialog(
        tester,
        const ClearConfirmationDialog(count: 2),
        (r) => result = r,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('ClearProgressDialog', () {
    testWidgets('renders phase, counts and percentage', (tester) async {
      await tester.pumpWidget(createThemedTestableWidget(
        const ClearProgressDialog(
          processed: 25,
          total: 100,
          phase: 'Clearing rows…',
        ),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Clearing Translations'), findsOneWidget);
      expect(find.text('Clearing rows…'), findsOneWidget);
      expect(find.text('25 / 100'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.25, 1e-9));
    });

    testWidgets('guards against division by zero when total is 0',
        (tester) async {
      await tester.pumpWidget(createThemedTestableWidget(
        const ClearProgressDialog(processed: 0, total: 0, phase: 'Starting'),
        theme: AppTheme.atelierDarkTheme,
      ));
      await tester.pumpAndSettle();

      expect(find.text('0 / 0'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 0.0);
    });
  });
}
