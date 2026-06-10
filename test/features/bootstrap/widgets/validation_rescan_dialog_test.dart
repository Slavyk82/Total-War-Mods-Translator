import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/bootstrap/providers/validation_rescan_provider.dart';
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

// Regression tests for the ValidationRescanDialog completion branch.
//
// When the rescan stream errors, the controller sets
// copyWith(error: e, isRunning: false, isDone: true) with `plan` retained.
// The dialog's only completion branch used to pop and — because plan was
// non-null — fire the SUCCESS toast 'Validation data update complete.'
// without ever reading state.error: a mid-rescan DB failure was explicitly
// reported to the user as a successful completion while legacy rows remained
// unmigrated. A failed prepare() (error set, plan null) closed with no
// message at all. The dialog must surface `state.error` as an error toast
// and never fire the success toast for a failed run.

/// Controller stub: keeps the production dialog logic intact but prevents
/// initState's prepare() from touching the real database, and lets tests
/// drive the state machine directly.
class _StubRescanController extends ValidationRescanController {
  @override
  RescanState build() => const RescanState();

  @override
  Future<void> prepare() async {
    // No-op: tests emit states explicitly via [emit].
  }

  void emit(RescanState newState) => state = newState;
}

const _plan = RescanPlan(
  total: 12000,
  already: 0,
  isResume: false,
  estimated: Duration(minutes: 3),
);

void main() {
  group('formatDuration', () {
    test('seconds only under 1 min', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
    });
    test('minutes + seconds when under 1h', () {
      expect(
        formatDuration(const Duration(minutes: 3, seconds: 20)),
        '3m 20s',
      );
    });
    test('hours + minutes when >= 1h', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 5, seconds: 30)),
        '1h 5m',
      );
    });
  });

  group('formatCount', () {
    test('inserts thousands separators', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(12000), '12,000');
      expect(formatCount(1234567), '1,234,567');
    });

    test('handles negative values', () {
      expect(formatCount(-1234), '-1,234');
    });
  });

  group('completion branch (error surfacing)', () {
    late _StubRescanController stub;

    Future<void> pumpDialogHost(WidgetTester tester) async {
      stub = _StubRescanController();
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const ValidationRescanDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          validationRescanControllerProvider.overrideWith(() => stub),
        ],
      ));
      await tester.tap(find.text('open'));
      // Fixed pumps instead of pumpAndSettle: the freshly opened dialog
      // shows an indeterminate LinearProgressIndicator (preparing body)
      // that animates forever, so pumpAndSettle would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ValidationRescanDialog), findsOneWidget);
    }

    testWidgets(
        'rescan stream error (isDone + error, plan retained) closes the '
        'dialog with the FAILURE toast — never the success toast',
        (tester) async {
      await pumpDialogHost(tester);

      // What the controller's onError handler emits when a commit batch
      // fails mid-rescan: error + isDone with the plan still present.
      stub.emit(RescanState(
        plan: _plan,
        isRunning: false,
        isDone: true,
        error: Exception('Rescan commit failed: db locked'),
      ));
      await tester.pump(); // rebuild; post-frame callback pops + toasts
      await tester.pump(); // start the route's exit transition
      await tester.pump(const Duration(milliseconds: 400)); // finish exit

      expect(find.byType(ValidationRescanDialog), findsNothing,
          reason: 'the dialog must close on completion');
      expect(find.textContaining('Validation data update failed'),
          findsOneWidget,
          reason: 'a failed rescan must surface state.error to the user');
      expect(find.textContaining('Rescan commit failed'), findsOneWidget,
          reason: 'the toast must carry the underlying error detail');
      expect(find.text('Validation data update complete.'), findsNothing,
          reason: 'a failed migration must NEVER be reported as a '
              'successful completion');

      // Drain the toast auto-dismiss timer.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets(
        'prepare() failure (isDone + error, plan null) also surfaces the '
        'error instead of closing silently', (tester) async {
      await pumpDialogHost(tester);

      stub.emit(RescanState(
        isRunning: false,
        isDone: true,
        error: Exception('calibration query failed'),
      ));
      await tester.pump(); // rebuild; post-frame callback pops + toasts
      await tester.pump(); // start the route's exit transition
      await tester.pump(const Duration(milliseconds: 400)); // finish exit

      expect(find.byType(ValidationRescanDialog), findsNothing);
      expect(find.textContaining('Validation data update failed'),
          findsOneWidget);
      expect(find.text('Validation data update complete.'), findsNothing);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets(
        'sanity: successful completion (isDone, no error, plan set) still '
        'fires the success toast', (tester) async {
      await pumpDialogHost(tester);

      stub.emit(const RescanState(
        plan: _plan,
        isRunning: false,
        isDone: true,
      ));
      await tester.pump(); // rebuild; post-frame callback pops + toasts
      await tester.pump(); // start the route's exit transition
      await tester.pump(const Duration(milliseconds: 400)); // finish exit

      expect(find.byType(ValidationRescanDialog), findsNothing);
      expect(find.text('Validation data update complete.'), findsOneWidget);
      expect(find.textContaining('Validation data update failed'),
          findsNothing);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
