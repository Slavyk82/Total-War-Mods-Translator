// Widget coverage tests for lib/widgets/dialogs/data_migration_dialog.dart.
//
// DataMigrationDialog is a non-dismissible, token-themed modal that renders
// DataMigration's state: a "preparing" placeholder, a live progress body
// (step text + progress message + LinearProgressIndicator + percent), an
// error banner with a Retry button, and an auto-pop on completion. It also
// kicks off runMigrations() from initState and exposes a static
// showAndRun(context, ref) that only shows the dialog when a migration is
// needed.
//
// These tests override the codegen notifier with a stub (so no DB / real
// app-data dir is touched) and drive each rendered state, assert the correct
// UI, verify the Retry button re-invokes runMigrations, verify the
// completion auto-pop, and cover the showAndRun gating (needs vs. not-needs).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/data_migration_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/dialogs/data_migration_dialog.dart';

import '../../helpers/test_helpers.dart';

/// Shared, test-owned state for the stub notifier.
///
/// `overrideWith` may invoke its factory more than once (the provider is
/// autoDispose, and `showAndRun`'s transient `ref.read` disposes it before the
/// dialog re-creates it). A NotifierProvider must return a *fresh* Notifier
/// each time, so the factory builds a new [_StubDataMigration] per call while
/// call counts and the initial state live here on the controller.
class _StubController {
  _StubController(this.initial, {this.needs = true});

  final DataMigrationState initial;
  final bool needs;

  int runMigrationsCount = 0;
  int needsMigrationCount = 0;
  _StubDataMigration? _current;

  /// Drive the currently-mounted stub into a new state.
  void emit(DataMigrationState newState) => _current?.emit(newState);
}

/// Stub notifier: keeps the production dialog logic intact but replaces
/// build()/runMigrations()/needsMigration() so initState never touches the
/// real Translation Memory service or SharedPreferences.
class _StubDataMigration extends DataMigration {
  _StubDataMigration(this._ctrl) {
    _ctrl._current = this;
  }

  final _StubController _ctrl;

  @override
  DataMigrationState build() => _ctrl.initial;

  @override
  Future<bool> needsMigration() async {
    _ctrl.needsMigrationCount++;
    return _ctrl.needs;
  }

  @override
  Future<void> runMigrations() async {
    _ctrl.runMigrationsCount++;
  }

  void emit(DataMigrationState newState) => state = newState;
}

void main() {
  final dm = t.widgets.dataMigrationDialog;

  // The dialog can render an indeterminate LinearProgressIndicator (which
  // animates forever) and a fair amount of vertical content; give each test a
  // generous surface so layout never overflows, and drive frames with fixed
  // pumps rather than pumpAndSettle where the progress bar is indeterminate.
  void useGenerousSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Opens the dialog through showDialog (so the completion pop and Retry
  /// button operate on a real dialog route) with a stub overriding the
  /// notifier. Uses fixed pumps because the progress bar may be indeterminate.
  Future<void> openDialog(
    WidgetTester tester,
    _StubController ctrl,
  ) async {
    useGenerousSurface(tester);
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const DataMigrationDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        dataMigrationProvider.overrideWith(() => _StubDataMigration(ctrl)),
      ],
    ));
    await tester.tap(find.text('open'));
    await tester.pump(); // build the dialog
    await tester.pump(); // run initState's post-frame runMigrations()
  }

  testWidgets('renders header + info and kicks off runMigrations on open',
      (tester) async {
    final ctrl = _StubController(const DataMigrationState());
    await openDialog(tester, ctrl);

    expect(find.byType(DataMigrationDialog), findsOneWidget);
    expect(find.text(dm.title), findsOneWidget);
    expect(find.text(dm.subtitle), findsOneWidget);
    expect(find.text(dm.info), findsOneWidget);
    // initState scheduled runMigrations exactly once.
    expect(ctrl.runMigrationsCount, 1);
  });

  testWidgets('idle state shows the "preparing" placeholder + indeterminate bar',
      (tester) async {
    final ctrl = _StubController(const DataMigrationState());
    await openDialog(tester, ctrl);

    // Empty currentStep falls back to the localized "preparing" label.
    expect(find.text(dm.preparing), findsOneWidget);
    // totalProgress == 0 -> indeterminate bar (value null), no percent text.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('running state shows step, message, determinate bar and percent',
      (tester) async {
    final ctrl = _StubController(const DataMigrationState(
      isRunning: true,
      currentStep: 'Rebuilding Translation Memory...',
      progressMessage: '50 / 200 translations (3 added)',
      currentProgress: 50,
      totalProgress: 200,
    ));
    await openDialog(tester, ctrl);

    expect(find.text('Rebuilding Translation Memory...'), findsOneWidget);
    expect(find.text('50 / 200 translations (3 added)'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 1e-6));

    // No error banner in the running state.
    expect(find.text(dm.actions.retry), findsNothing);
  });

  testWidgets('error state shows the error banner + Retry (no progress bar)',
      (tester) async {
    const errorText = 'Rebuild failed: database is locked';
    final ctrl = _StubController(const DataMigrationState(error: errorText));
    await openDialog(tester, ctrl);

    expect(find.text(errorText), findsOneWidget);
    expect(find.text(dm.actions.retry), findsOneWidget);
    // The progress body (and its bar) is hidden while an error is shown.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(dm.preparing), findsNothing);
  });

  testWidgets('Retry button re-invokes runMigrations', (tester) async {
    final ctrl = _StubController(const DataMigrationState(error: 'boom'));
    await openDialog(tester, ctrl);

    // initState already fired one runMigrations.
    expect(ctrl.runMigrationsCount, 1);

    await tester.tap(find.text(dm.actions.retry));
    await tester.pump();

    expect(ctrl.runMigrationsCount, 2);
  });

  testWidgets('completion auto-pops the dialog', (tester) async {
    final ctrl = _StubController(const DataMigrationState());
    await openDialog(tester, ctrl);
    expect(find.byType(DataMigrationDialog), findsOneWidget);

    // Migration finishes -> isComplete triggers a post-frame pop.
    ctrl.emit(const DataMigrationState(
      isComplete: true,
      currentStep: 'Migration complete',
    ));
    await tester.pump(); // rebuild schedules the pop
    await tester.pump(); // start the route exit
    await tester.pump(const Duration(milliseconds: 400)); // finish exit

    expect(find.byType(DataMigrationDialog), findsNothing);
  });

  group('showAndRun', () {
    Future<_StubController> pumpHost(
      WidgetTester tester, {
      required bool needs,
    }) async {
      useGenerousSurface(tester);
      final ctrl = _StubController(const DataMigrationState(), needs: needs);
      await tester.pumpWidget(createThemedTestableWidget(
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => DataMigrationDialog.showAndRun(context, ref),
              child: const Text('run'),
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          dataMigrationProvider.overrideWith(() => _StubDataMigration(ctrl)),
        ],
      ));
      return ctrl;
    }

    testWidgets('does NOT show the dialog when no migration is needed',
        (tester) async {
      final ctrl = await pumpHost(tester, needs: false);

      await tester.tap(find.text('run'));
      await tester.pump(); // resolve needsMigration()
      await tester.pump();

      expect(ctrl.needsMigrationCount, 1);
      expect(find.byType(DataMigrationDialog), findsNothing);
      // Not shown -> initState never ran, so no migration was kicked off.
      expect(ctrl.runMigrationsCount, 0);
    });

    testWidgets('shows the dialog when a migration is needed', (tester) async {
      final ctrl = await pumpHost(tester, needs: true);

      await tester.tap(find.text('run'));
      await tester.pump(); // resolve needsMigration()
      await tester.pump(); // build the dialog
      await tester.pump(); // run initState post-frame

      expect(ctrl.needsMigrationCount, 1);
      expect(find.byType(DataMigrationDialog), findsOneWidget);
      expect(ctrl.runMigrationsCount, 1);
    });
  });
}
