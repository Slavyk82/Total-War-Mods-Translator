import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/bootstrap/providers/validation_rescan_provider.dart';
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';
import 'package:twmt/services/validation/validation_rescan_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

// Coverage for ValidationRescanDialog body/title rendering branches.
//
// The companion `validation_rescan_dialog_test.dart` exercises the completion
// branch (error/success toasts). This file drives the non-completion state
// machine: normalization, preparing, plan (fresh + resume), the Start action,
// and every progress lane (no-progress, progress, progress+ETA).
//
// House rules: pump under ProviderScope + themed MaterialApp via
// createThemedTestableWidget(AppTheme.atelierDarkTheme); open the dialog with
// showDialog(useRootNavigator:false); 1200x1600 surface, dPR 1.0, tear-downs.
// Indeterminate progress animates forever, so always `pump`, never
// `pumpAndSettle`.

/// Controller stub: keeps the production dialog logic intact but prevents
/// initState's prepare() from touching the real database, and lets tests
/// drive the state machine directly. `start()` is recorded (not executed)
/// so we can assert the Start button wires through without a real service.
class _StubRescanController extends ValidationRescanController {
  final RescanState _initial;
  int startCalls = 0;

  _StubRescanController([this._initial = const RescanState()]);

  @override
  RescanState build() => _initial;

  @override
  Future<void> prepare() async {
    // No-op: tests emit states explicitly via [emit].
  }

  @override
  void start() {
    startCalls++;
  }

  void emit(RescanState newState) => state = newState;
}

const _freshPlan = RescanPlan(
  total: 12000,
  already: 0,
  isResume: false,
  estimated: Duration(minutes: 3),
);

const _resumePlan = RescanPlan(
  total: 4000,
  already: 8000,
  isResume: true,
  estimated: Duration(minutes: 1, seconds: 30),
);

void main() {
  late _StubRescanController stub;

  /// Pump the dialog host with [initial] as the controller's build() state
  /// and open the dialog. Returns after the first frames are pumped.
  Future<void> pumpDialog(
    WidgetTester tester, {
    RescanState initial = const RescanState(),
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    stub = _StubRescanController(initial);
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              useRootNavigator: false,
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
    // Fixed pumps: the freshly opened dialog may render an indeterminate
    // LinearProgressIndicator that animates forever — pumpAndSettle would
    // time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ValidationRescanDialog), findsOneWidget);
  }

  group('normalizing body', () {
    testWidgets('total == 0 shows indeterminate "Scanning..." label',
        (tester) async {
      await pumpDialog(
        tester,
        initial: const RescanState(isNormalizing: true),
      );

      expect(find.text('Preparing validation data'), findsOneWidget);
      expect(find.text('Scanning validation entries...'), findsOneWidget);
      expect(
        find.text('Upgrading legacy validation records to the new format.'),
        findsOneWidget,
      );
    });

    testWidgets('total > 0 shows determinate "Normalized X of Y" label',
        (tester) async {
      await pumpDialog(
        tester,
        initial: const RescanState(
          isNormalizing: true,
          normalizeProcessed: 3000,
          normalizeTotal: 12000,
        ),
      );

      expect(find.text('Preparing validation data'), findsOneWidget);
      expect(find.text('Normalized 3,000 of 12,000'), findsOneWidget);
    });
  });

  group('preparing body', () {
    testWidgets('no plan and not normalizing shows the preparing lane',
        (tester) async {
      // Plan null, not normalizing, not running → _preparingBody.
      await pumpDialog(tester);

      expect(find.text('Preparing validation data'), findsOneWidget);
      expect(find.text('Preparing...'), findsOneWidget);
    });
  });

  group('plan body', () {
    testWidgets('fresh plan shows first-run wording and "Start rescan"',
        (tester) async {
      await pumpDialog(tester, initial: const RescanState(plan: _freshPlan));

      expect(find.text('Validation data update required'), findsOneWidget);
      expect(find.text('Start rescan'), findsOneWidget);
      // freshBody interpolates the formatted total + estimate.
      expect(find.textContaining('12,000 units to rescan'), findsOneWidget);
      expect(find.textContaining('~3m 0s'), findsOneWidget);
    });

    testWidgets('resume plan shows resume wording and "Continue"',
        (tester) async {
      await pumpDialog(tester, initial: const RescanState(plan: _resumePlan));

      expect(find.text('Resuming validation update'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      // resumeBody: already / totalAll / remaining / estimated.
      expect(find.textContaining('8,000 of 12,000 units already processed'),
          findsOneWidget);
      expect(find.textContaining('Remaining: 4,000 units'), findsOneWidget);
      expect(find.textContaining('~1m 30s'), findsOneWidget);
    });

    testWidgets('tapping Start invokes controller.start()', (tester) async {
      await pumpDialog(tester, initial: const RescanState(plan: _freshPlan));

      expect(stub.startCalls, 0);
      await tester.tap(find.text('Start rescan'));
      await tester.pump();
      expect(stub.startCalls, 1);
    });
  });

  group('progress body', () {
    testWidgets('isRunning with no progress shows "Starting rescan..."',
        (tester) async {
      await pumpDialog(tester, initial: const RescanState(isRunning: true));

      // Title flips to "Updating validation data" once running.
      expect(find.text('Updating validation data'), findsOneWidget);
      expect(find.text('Starting rescan...'), findsOneWidget);
      expect(
        find.textContaining('Closing the app will pause the update'),
        findsOneWidget,
      );
    });

    testWidgets('progress without ETA shows "Rescanned X of Y"',
        (tester) async {
      await pumpDialog(
        tester,
        initial: const RescanState(
          isRunning: true,
          progress: RescanProgress(done: 5000, total: 12000, eta: null),
        ),
      );

      expect(find.text('Updating validation data'), findsOneWidget);
      expect(find.text('Rescanned 5,000 of 12,000'), findsOneWidget);
    });

    testWidgets('progress with ETA shows "Rescanned X of Y — ETA Z"',
        (tester) async {
      await pumpDialog(
        tester,
        initial: const RescanState(
          isRunning: true,
          progress: RescanProgress(
            done: 6000,
            total: 12000,
            eta: Duration(seconds: 45),
          ),
        ),
      );

      expect(
        find.text('Rescanned 6,000 of 12,000 — ETA 45s'),
        findsOneWidget,
      );
    });

    testWidgets('progress with total == 0 renders a full (1.0) bar safely',
        (tester) async {
      // Guards the `progress.total == 0 ? 1.0 : ...` branch in _progressBody.
      await pumpDialog(
        tester,
        initial: const RescanState(
          isRunning: true,
          progress: RescanProgress(done: 0, total: 0, eta: Duration.zero),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // eta is non-null (zero) → the ETA headline form is used.
      expect(find.text('Rescanned 0 of 0 — ETA 0s'), findsOneWidget);
    });
  });

  group('title transitions', () {
    testWidgets('progress present (not yet running) still titles "Updating"',
        (tester) async {
      // _titleFor: progress != null forces the updating title even when
      // isRunning is false (covers the `progress != null ||` clause).
      await pumpDialog(
        tester,
        initial: const RescanState(
          progress: RescanProgress(done: 1, total: 2, eta: null),
        ),
      );

      expect(find.text('Updating validation data'), findsOneWidget);
    });
  });
}
