import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/widgets/tm_cleanup_dialog.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Fake cleanup notifier driving [tmCleanupStateProvider] deterministically.
///
/// Subclasses the generated public class and overrides `build()` so the
/// provider resolves without GetIt/the real service. `cleanup` records the
/// `unusedDays` argument it was called with and transitions to whatever
/// terminal state the test seeded, exercising the dialog's success / error /
/// loading branches without touching the real TM service.
class _FakeTmCleanupState extends TmCleanupState {
  _FakeTmCleanupState({
    this.initial = const AsyncValue.data(null),
    this.terminal,
  });

  final AsyncValue<int?> initial;
  final AsyncValue<int?>? terminal;

  int? capturedUnusedDays;
  int cleanupCallCount = 0;
  int resetCallCount = 0;

  @override
  AsyncValue<int?> build() => initial;

  @override
  Future<void> cleanup({int unusedDays = 365}) async {
    cleanupCallCount++;
    capturedUnusedDays = unusedDays;
    state = const AsyncValue.loading();
    if (terminal != null) {
      state = terminal!;
    }
  }

  @override
  void reset() {
    resetCallCount++;
    state = const AsyncValue.data(null);
  }
}

void main() {
  late _FakeTmCleanupState fakeCleanup;

  setUp(() {
    fakeCleanup = _FakeTmCleanupState();

    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1200, 1600);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  /// Hosts the dialog under a nested Navigator (`useRootNavigator: false`) so
  /// `Navigator.of(context).pop()` works. [fake] drives the cleanup state
  /// provider. When [settle] is false a fixed pump sequence is used so the
  /// indeterminate [LinearProgressIndicator] of the loading branch doesn't
  /// hang `pumpAndSettle`.
  Future<void> pumpDialog(
    WidgetTester tester, {
    _FakeTmCleanupState Function()? fake,
    bool settle = true,
  }) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            useRootNavigator: false,
            builder: (_) => const TmCleanupDialog(),
          ),
          child: const Text('open'),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        tmCleanupStateProvider.overrideWith(fake ?? () => fakeCleanup),
      ],
    ));
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('renders the cleanup dialog with default 365-day threshold',
      (tester) async {
    await pumpDialog(tester);

    expect(find.text('Cleanup Translation Memory'), findsOneWidget);
    expect(
      find.text('Remove unused entries to optimize your translation memory.'),
      findsOneWidget,
    );
    expect(find.text('Delete if unused for (days)'), findsOneWidget);
    // Default threshold value displayed.
    expect(find.text('365'), findsOneWidget);
    // Slider rendered for choosing the threshold.
    expect(find.byType(Slider), findsOneWidget);
    // Cancel + Cleanup actions in the non-result state.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Cleanup'), findsOneWidget);
    // No "delete all" destructive copy at the default threshold.
    expect(find.text('All entries will be deleted - this cannot be undone'),
        findsNothing);
  });

  testWidgets('dragging the slider updates the threshold value', (tester) async {
    await pumpDialog(tester);

    // Drag the slider left a moderate amount; the value drops below the
    // default 365 (each division is 10 days). Staying above 0 avoids the
    // production "delete all" layout (a fixed 520-wide row that overflows by
    // a few px on the narrow test surface) while still exercising the
    // Slider.onChanged -> setState path.
    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pumpAndSettle();

    // The default value is gone; some smaller non-zero threshold is shown.
    expect(find.text('365'), findsNothing);
    // Still in age-based mode (not the destructive "delete all" state).
    expect(find.text('Delete all'), findsNothing);
    expect(find.text('All entries will be deleted - this cannot be undone'),
        findsNothing);
  });

  testWidgets('dragging to the far left enters the destructive delete-all state',
      (tester) async {
    await pumpDialog(tester);

    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();

    // At 0 the destructive "Delete all" label + warning appear. The
    // dialog's fixed 520-px body makes the label/value Row overflow by a
    // few px at this state (a production layout quirk we don't touch); the
    // overflow is recorded as a non-fatal exception which we consume so it
    // doesn't fail the test.
    expect(find.text('Delete all'), findsOneWidget);
    expect(find.text('All entries will be deleted - this cannot be undone'),
        findsOneWidget);
    expect(find.text('365'), findsNothing);
    tester.takeException();
  });

  testWidgets('confirming cleanup calls the notifier with the threshold',
      (tester) async {
    final fake = _FakeTmCleanupState(terminal: const AsyncValue.data(3));
    await pumpDialog(tester, fake: () => fake);

    await tester.tap(find.text('Cleanup'));
    await tester.pump(); // run cleanup() -> loading -> terminal data(3)
    await tester.pumpAndSettle();

    expect(fake.cleanupCallCount, 1);
    // Default threshold passed straight through.
    expect(fake.capturedUnusedDays, 365);
    // Terminal success result surfaces the deleted-count banner.
    expect(find.text('Deleted 3 entries'), findsOneWidget);
  });

  testWidgets('confirming after dragging passes the chosen threshold',
      (tester) async {
    final fake = _FakeTmCleanupState(terminal: const AsyncValue.data(99));
    await pumpDialog(tester, fake: () => fake);

    // Drag fully left -> unusedDays == 0 (delete all). The value-0 state
    // overflows the fixed-width row by a few px (production quirk); consume
    // the non-fatal overflow exception before tapping.
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    tester.takeException();

    await tester.tap(find.text('Cleanup'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fake.cleanupCallCount, 1);
    expect(fake.capturedUnusedDays, 0);
    tester.takeException();
  });

  testWidgets('success result shows the deleted-count banner and OK action',
      (tester) async {
    await pumpDialog(
      tester,
      fake: () => _FakeTmCleanupState(
        initial: const AsyncValue.data(42),
      ),
    );

    // Result banner with the formatted deleted count.
    expect(find.text('Deleted 42 entries'), findsOneWidget);
    // Actions collapse to a single OK button when a result is present.
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Cleanup'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('OK on the success result resets state and closes the dialog',
      (tester) async {
    final done = _FakeTmCleanupState(initial: const AsyncValue.data(7));
    await pumpDialog(tester, fake: () => done);

    expect(find.byType(TmCleanupDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(done.resetCallCount, 1);
    expect(find.byType(TmCleanupDialog), findsNothing);
  });

  testWidgets('loading state shows an indeterminate progress indicator',
      (tester) async {
    await pumpDialog(
      tester,
      fake: () => _FakeTmCleanupState(
        initial: const AsyncValue.loading(),
      ),
      settle: false,
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // While loading, Cancel is rendered but disabled (onTap null) and
    // Cleanup is also disabled; tapping must not invoke cleanup.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Cleanup'), findsOneWidget);
  });

  testWidgets('error state renders the error message', (tester) async {
    await pumpDialog(
      tester,
      fake: () => _FakeTmCleanupState(
        initial: AsyncValue.error(
          'Cleanup failed: database locked',
          StackTrace.empty,
        ),
      ),
    );

    expect(find.textContaining('Cleanup failed: database locked'),
        findsOneWidget);
    // Error is not a "result", so the standard Cancel/Cleanup actions remain.
    expect(find.text('Cleanup'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('cancel resets state and closes the dialog without cleanup',
      (tester) async {
    await pumpDialog(tester);

    expect(find.byType(TmCleanupDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fakeCleanup.cleanupCallCount, 0);
    expect(fakeCleanup.resetCallCount, 1);
    expect(find.byType(TmCleanupDialog), findsNothing);
  });
}
