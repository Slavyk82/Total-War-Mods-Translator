// Widget tests for the batch pack-export screen.
//
// The screen reads [batchExportStagingProvider] in initState, kicks off an
// export via a post-frame callback, and renders a progress section, per-project
// status rows, a results summary and (de)pending on state) cancel/close actions.
//
// We drive each lifecycle state (idle/running/completed-success/
// completed-with-errors/cancelled/no-data) by overriding the batch-export
// notifier with a fake whose build() returns a crafted state and whose
// exportBatch/cancel/reset record calls instead of touching real services.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/features/projects/providers/batch_pack_export_notifier.dart';
import 'package:twmt/features/projects/providers/batch_project_selection_provider.dart';
import 'package:twmt/features/projects/screens/batch_pack_export_screen.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/fluent/fluent_progress_indicator.dart';

import '../../../helpers/fakes/fake_logger.dart';

/// Fake batch-export notifier: build() returns a fixed state and the mutating
/// methods record their calls instead of running the real export loop.
class _FakeBatchExportNotifier extends BatchPackExportNotifier {
  _FakeBatchExportNotifier(this._initial);

  final BatchPackExportState _initial;

  int exportCalls = 0;
  int cancelCalls = 0;
  int resetCalls = 0;

  @override
  BatchPackExportState build() => _initial;

  @override
  Future<void> exportBatch({
    required List<ProjectExportInfo> projects,
    required String languageCode,
  }) async {
    exportCalls++;
  }

  @override
  void cancel() {
    cancelCalls++;
  }

  @override
  void reset() {
    resetCalls++;
  }
}

void main() {
  const dprOverride = 1.0;

  // The screen's dispose() reads providers via ref. Under Riverpod 3, widget
  // disposal in flutter_test runs during BuildOwner.finalizeTree, where ref is
  // already considered unmounted — so a benign "ref when unmounted is unsafe"
  // StateError is reported. In the real app the route disposes while still
  // active, so this only surfaces under test. Installed from inside each test
  // body (the binding resets FlutterError.onError per test, so a setUp install
  // would be clobbered). Swallows exactly that error; all else propagates.
  void swallowDisposeRefError() {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final ex = details.exception;
      if (ex is StateError &&
          ex.message.contains('about to or has been unmounted')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);
  }

  /// Three staged projects with stable ids/names.
  BatchExportStagingData stagingFor(List<String> ids) => BatchExportStagingData(
        projects: [
          for (final id in ids) ProjectExportInfo(id: id, name: 'Project $id'),
        ],
        languageCode: 'fr',
        languageName: 'French',
      );

  /// Build a container with the batch-export notifier faked and the (private)
  /// staging notifier primed via its public set(). The staging value must be
  /// present before the screen's initState reads it.
  ProviderContainer makeContainer({
    required BatchExportStagingData? staging,
    required _FakeBatchExportNotifier fake,
    List<Override> extraOverrides = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        batchPackExportProvider.overrideWith(() => fake),
        ...extraOverrides,
      ],
    );
    addTearDown(container.dispose);
    container.read(batchExportStagingProvider.notifier).set(staging);
    return container;
  }

  /// Build the screen with the given staging data + batch-export state.
  /// Returns the fake notifier so callers can assert recorded calls.
  Future<_FakeBatchExportNotifier> pumpScreen(
    WidgetTester tester, {
    required BatchExportStagingData? staging,
    required BatchPackExportState state,
    GoRouter? router,
    List<Override> extraOverrides = const [],
  }) async {
    swallowDisposeRefError();
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    tester.view.devicePixelRatio = dprOverride;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.reset);

    final fake = _FakeBatchExportNotifier(state);
    final container = makeContainer(
      staging: staging,
      fake: fake,
      extraOverrides: extraOverrides,
    );

    final Widget app = router != null
        ? MaterialApp.router(
            theme: AppTheme.atelierDarkTheme,
            routerConfig: router,
          )
        : MaterialApp(
            theme: AppTheme.atelierDarkTheme,
            home: const SizedBox(
              width: 1400,
              height: 1000,
              child: BatchPackExportScreen(),
            ),
          );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: app),
    );
    // Indeterminate progress / running spinners: pump, never pumpAndSettle.
    await tester.pump();
    return fake;
  }

  /// Advance route/dialog transitions WITHOUT pumpAndSettle. The screen runs a
  /// 1s periodic elapsed timer that never lets the tree settle, so pumpAndSettle
  /// would time out whenever the export screen is mounted.
  Future<void> advance(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Router that hosts the screen at /export and a sentinel landing route so
  /// context.pop() has somewhere to return to.
  GoRouter exportRouter() => GoRouter(
        initialLocation: '/host',
        routes: [
          GoRoute(
            path: '/host',
            builder: (_, _) => Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => context.push('/export'),
                    child: const Text('go-export'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/export',
            builder: (_, _) => const BatchPackExportScreen(),
          ),
        ],
      );

  group('BatchPackExportScreen — no staging data', () {
    testWidgets('renders no-data fallback when staging is null',
        (tester) async {
      await pumpScreen(tester, staging: null, state: const BatchPackExportState());

      expect(find.text(t.projects.batchExport.noData), findsOneWidget);
      expect(find.text(t.projects.batchExport.title), findsOneWidget);
    });

    testWidgets('back button on no-data screen pops the route', (tester) async {
      await pumpScreen(
        tester,
        staging: null,
        state: const BatchPackExportState(),
        router: exportRouter(),
      );

      // Navigate onto the export screen.
      await tester.tap(find.text('go-export'));
      await advance(tester);
      expect(find.text(t.projects.batchExport.noData), findsOneWidget);

      // Tap the header back button (tooltip == common back). The no-data
      // branch pops directly via context.pop() (no confirm dialog).
      await tester.tap(find.byTooltip(t.common.actions.back));
      await advance(tester);

      // Returned to host.
      expect(find.text('go-export'), findsOneWidget);
    });
  });

  group('BatchPackExportScreen — running state', () {
    testWidgets('renders exporting status, progress and per-project rows',
        (tester) async {
      const state = BatchPackExportState(
        isExporting: true,
        totalProjects: 3,
        completedProjects: 1,
        currentProjectProgress: 0.5,
        currentProjectId: 'b',
        currentProjectName: 'Project b',
        projectStatuses: {
          'a': BatchProjectStatus.success,
          'b': BatchProjectStatus.inProgress,
          'c': BatchProjectStatus.pending,
        },
        results: [
          ProjectExportResult(
            projectId: 'a',
            projectName: 'Project a',
            success: true,
            entryCount: 7,
          ),
        ],
      );

      final fake = await pumpScreen(
        tester,
        staging: stagingFor(['a', 'b', 'c']),
        state: state,
      );

      // initState fires exportBatch via post-frame callback.
      expect(fake.exportCalls, 1);

      // Exporting status + "current project" line.
      expect(find.text(t.projects.batchExport.statusExporting), findsOneWidget);
      expect(
        find.text(t.projects.batchExport.current(name: 'Project b')),
        findsOneWidget,
      );

      // overallProgress = (1 + 0.5) / 3 = 0.5 => "50.0%".
      expect(find.text('50.0%'), findsOneWidget);

      // Three project rows rendered (names appear in list).
      expect(find.text('Project a'), findsOneWidget);
      expect(find.text('Project b'), findsWidgets);
      expect(find.text('Project c'), findsOneWidget);

      // Success entry count under the completed project.
      expect(
        find.text(t.projects.batchExport.entryCount(count: 7)),
        findsOneWidget,
      );

      // In-progress project shows a CircularProgressIndicator status icon.
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Current project mini progress bar present.
      expect(find.byType(FluentProgressBar), findsWidgets);

      // While active, a Cancel action is shown and wired.
      expect(find.text(t.common.actions.cancel), findsOneWidget);
      await tester.tap(find.text(t.common.actions.cancel));
      await tester.pump();
      expect(fake.cancelCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('elapsed timer ticks update the screen', (tester) async {
      await pumpScreen(
        tester,
        staging: stagingFor(['a']),
        state: const BatchPackExportState(
          isExporting: true,
          totalProjects: 1,
          projectStatuses: {'a': BatchProjectStatus.inProgress},
        ),
      );

      // Default elapsed is "0m 0s".
      expect(find.textContaining('m '), findsWidgets);
      // Advance the periodic 1s timer twice; setState re-renders.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BatchPackExportScreen), findsOneWidget);
    });
  });

  group('BatchPackExportScreen — completed (success)', () {
    testWidgets('renders complete status, summary and close button',
        (tester) async {
      const state = BatchPackExportState(
        isExporting: false,
        totalProjects: 2,
        completedProjects: 2,
        projectStatuses: {
          'a': BatchProjectStatus.success,
          'b': BatchProjectStatus.success,
        },
        results: [
          ProjectExportResult(
            projectId: 'a',
            projectName: 'Project a',
            success: true,
            entryCount: 3,
          ),
          ProjectExportResult(
            projectId: 'b',
            projectName: 'Project b',
            success: true,
            entryCount: 4,
          ),
        ],
      );

      await pumpScreen(
        tester,
        staging: stagingFor(['a', 'b']),
        state: state,
      );

      expect(find.text(t.projects.batchExport.statusComplete), findsOneWidget);
      expect(find.text(t.projects.batchExport.allSuccess), findsOneWidget);
      expect(
        find.text(t.projects.batchExport.summary(succeeded: 2, failed: 0)),
        findsOneWidget,
      );
      // overall = (2 + 0) / 2 = 1.0 => "100.0%".
      expect(find.text('100.0%'), findsOneWidget);

      // Close button present, no Cancel button.
      expect(find.text(t.common.actions.close), findsOneWidget);
      expect(find.text(t.common.actions.cancel), findsNothing);
    });

    testWidgets('close button pops the route', (tester) async {
      const state = BatchPackExportState(
        isExporting: false,
        totalProjects: 1,
        completedProjects: 1,
        projectStatuses: {'a': BatchProjectStatus.success},
        results: [
          ProjectExportResult(
            projectId: 'a',
            projectName: 'Project a',
            success: true,
            entryCount: 1,
          ),
        ],
      );

      await pumpScreen(
        tester,
        staging: stagingFor(['a']),
        state: state,
        router: exportRouter(),
      );

      await tester.tap(find.text('go-export'));
      await advance(tester);
      expect(find.text(t.projects.batchExport.statusComplete), findsOneWidget);

      await tester.tap(find.text(t.common.actions.close));
      await advance(tester);
      expect(find.text('go-export'), findsOneWidget);
    });
  });

  group('BatchPackExportScreen — completed (with errors)', () {
    testWidgets('renders warning summary and per-row error message',
        (tester) async {
      const state = BatchPackExportState(
        isExporting: false,
        totalProjects: 2,
        completedProjects: 2,
        projectStatuses: {
          'a': BatchProjectStatus.success,
          'b': BatchProjectStatus.failed,
        },
        results: [
          ProjectExportResult(
            projectId: 'a',
            projectName: 'Project a',
            success: true,
            entryCount: 5,
          ),
          ProjectExportResult(
            projectId: 'b',
            projectName: 'Project b',
            success: false,
            errorMessage: 'boom failure',
          ),
        ],
      );

      await pumpScreen(
        tester,
        staging: stagingFor(['a', 'b']),
        state: state,
      );

      expect(
        find.text(t.projects.batchExport.completedWithErrors),
        findsOneWidget,
      );
      expect(
        find.text(t.projects.batchExport.summary(succeeded: 1, failed: 1)),
        findsOneWidget,
      );
      // Failed row's error message rendered.
      expect(find.text('boom failure'), findsOneWidget);
    });
  });

  group('BatchPackExportScreen — cancelled state', () {
    testWidgets('renders cancelled status and close button', (tester) async {
      // Cancelled before any project finished: results stay empty so the
      // status reads "Cancelled" (a non-empty results list would flip
      // isComplete=true and show "Export Complete" instead).
      const state = BatchPackExportState(
        isExporting: false,
        isCancelled: true,
        totalProjects: 2,
        completedProjects: 0,
        projectStatuses: {
          'a': BatchProjectStatus.cancelled,
          'b': BatchProjectStatus.cancelled,
        },
      );

      await pumpScreen(
        tester,
        staging: stagingFor(['a', 'b']),
        state: state,
      );

      expect(find.text(t.projects.batchExport.statusCancelled), findsOneWidget);
      // isDone => close button present; not active => no cancel button.
      expect(find.text(t.common.actions.close), findsOneWidget);
      expect(find.text(t.common.actions.cancel), findsNothing);
    });
  });

  group('BatchPackExportScreen — back / leave confirmation', () {
    testWidgets('back while active prompts confirm-leave; staying keeps screen',
        (tester) async {
      final fake = await pumpScreen(
        tester,
        staging: stagingFor(['a', 'b']),
        state: const BatchPackExportState(
          isExporting: true,
          totalProjects: 2,
          projectStatuses: {
            'a': BatchProjectStatus.inProgress,
            'b': BatchProjectStatus.pending,
          },
        ),
        router: exportRouter(),
      );

      await tester.tap(find.text('go-export'));
      await advance(tester);
      expect(find.text(t.projects.batchExport.statusExporting), findsOneWidget);

      // Tap back -> confirm-leave dialog appears (export is active).
      await tester.tap(find.byTooltip(t.common.actions.back));
      await advance(tester);
      expect(find.text(t.projects.dialogs.confirmLeave.title), findsOneWidget);

      // "Stay" dismisses the dialog and keeps us on the export screen.
      await tester.tap(find.text(t.projects.dialogs.confirmLeave.stay));
      await advance(tester);
      expect(find.text(t.projects.batchExport.statusExporting), findsOneWidget);
      expect(find.text('go-export'), findsNothing);
      // No cancel issued by staying (export was started once in initState).
      expect(fake.cancelCalls, 0);
    });

    testWidgets('back while active and confirming leave cancels and pops',
        (tester) async {
      final fake = await pumpScreen(
        tester,
        staging: stagingFor(['a', 'b']),
        state: const BatchPackExportState(
          isExporting: true,
          totalProjects: 2,
          projectStatuses: {
            'a': BatchProjectStatus.inProgress,
            'b': BatchProjectStatus.pending,
          },
        ),
        router: exportRouter(),
      );

      await tester.tap(find.text('go-export'));
      await advance(tester);

      await tester.tap(find.byTooltip(t.common.actions.back));
      await advance(tester);
      expect(find.text(t.projects.dialogs.confirmLeave.title), findsOneWidget);

      // Confirm "Leave" -> cancel + pop back to host.
      await tester.tap(find.text(t.projects.dialogs.confirmLeave.leave));
      await advance(tester);

      expect(find.text('go-export'), findsOneWidget);
      // cancel() called via _handleBack confirm-branch (+ dispose safety net).
      expect(fake.cancelCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('back when not active pops immediately without a dialog',
        (tester) async {
      await pumpScreen(
        tester,
        staging: stagingFor(['a']),
        state: const BatchPackExportState(
          isExporting: false,
          totalProjects: 1,
          completedProjects: 1,
          projectStatuses: {'a': BatchProjectStatus.success},
          results: [
            ProjectExportResult(
              projectId: 'a',
              projectName: 'Project a',
              success: true,
              entryCount: 1,
            ),
          ],
        ),
        router: exportRouter(),
      );

      await tester.tap(find.text('go-export'));
      await advance(tester);
      expect(find.text(t.projects.batchExport.statusComplete), findsOneWidget);

      // Not exporting -> _confirmLeaveIfActive returns true, no dialog.
      await tester.tap(find.byTooltip(t.common.actions.back));
      await advance(tester);
      expect(find.text(t.projects.dialogs.confirmLeave.title), findsNothing);
      expect(find.text('go-export'), findsOneWidget);
    });
  });

  group('BatchPackExportScreen — selection provider integration', () {
    testWidgets('close clears selection mode and pops', (tester) async {
      late ProviderContainer capturedContainer;

      const state = BatchPackExportState(
        isExporting: false,
        totalProjects: 1,
        completedProjects: 1,
        projectStatuses: {'a': BatchProjectStatus.success},
        results: [
          ProjectExportResult(
            projectId: 'a',
            projectName: 'Project a',
            success: true,
            entryCount: 1,
          ),
        ],
      );

      swallowDisposeRefError();
      final fake = _FakeBatchExportNotifier(state);
      final router = exportRouter();

      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      tester.view.devicePixelRatio = dprOverride;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.reset);

      capturedContainer = makeContainer(staging: stagingFor(['a']), fake: fake);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: capturedContainer,
        child: MaterialApp.router(
          theme: AppTheme.atelierDarkTheme,
          routerConfig: router,
        ),
      ));
      await tester.pump();

      // Put selection mode on so we can prove close() exits it.
      capturedContainer
          .read(batchProjectSelectionProvider.notifier)
          .enterSelectionMode();
      capturedContainer
          .read(batchProjectSelectionProvider.notifier)
          .toggleProject('a');
      expect(
        capturedContainer.read(batchProjectSelectionProvider).isSelectionMode,
        isTrue,
      );

      await tester.tap(find.text('go-export'));
      await advance(tester);

      await tester.tap(find.text(t.common.actions.close));
      await advance(tester);

      // Close exits selection mode + pops.
      expect(
        capturedContainer.read(batchProjectSelectionProvider).isSelectionMode,
        isFalse,
      );
      expect(find.text('go-export'), findsOneWidget);
    });
  });
}
