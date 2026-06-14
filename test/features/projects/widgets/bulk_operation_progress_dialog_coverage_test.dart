import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Test notifier that lets tests drive the state directly and records calls to
/// the lifecycle methods without running the real bulk-operation machinery.
class _TestBulkNotifier extends BulkOperationsNotifier {
  _TestBulkNotifier(this._initial);
  final BulkOperationState _initial;

  int resetCalls = 0;
  int cancelCalls = 0;
  final List<({BulkOperationType type, String lang, int count})> runCalls = [];

  @override
  BulkOperationState build() => _initial;

  @override
  void reset() {
    resetCalls++;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> run({
    required BulkOperationType type,
    required String targetLanguageCode,
    required List<ProjectWithDetails> projects,
  }) async {
    runCalls.add((type: type, lang: targetLanguageCode, count: projects.length));
  }
}

/// Gives the test view a large surface (1200x1600 @ dPR 1.0) so the 560x420+
/// token dialog plus its action rows lay out without overflow. Registers a
/// tear-down that resets the view.
void _sizeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<_TestBulkNotifier> _pumpDialog(
  WidgetTester tester,
  BulkOperationState state, {
  List<Override> extraOverrides = const [],
}) async {
  _sizeView(tester);
  late _TestBulkNotifier notifier;
  await tester.pumpWidget(
    createThemedTestableWidget(
      const BulkOperationProgressDialog(),
      theme: AppTheme.atelierDarkTheme,
      screenSize: const Size(1200, 1600),
      overrides: [
        bulkOperationsProvider.overrideWith(() {
          notifier = _TestBulkNotifier(state);
          return notifier;
        }),
        ...extraOverrides,
      ],
    ),
  );
  // Indeterminate progress indicators never settle; a single pump is enough.
  await tester.pump();
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('title + icon per operation type', () {
    final cases = <BulkOperationType?, String>{
      BulkOperationType.translate: 'Translating projects',
      BulkOperationType.rescan: 'Rescanning reviews',
      BulkOperationType.forceValidate: 'Force-validating reviews',
      BulkOperationType.generatePack: 'Generating packs',
      BulkOperationType.translateReviews: 'Retranslating flagged units',
      null: 'Bulk operation',
    };

    cases.forEach((type, expectedTitle) {
      testWidgets('renders title "$expectedTitle"', (tester) async {
        await _pumpDialog(
          tester,
          BulkOperationState(
            operationType: type,
            targetLanguageCode: 'fr',
            projectIds: const ['a'],
            results: const {
              'a': ProjectOutcome(status: ProjectResultStatus.pending),
            },
          ),
        );
        expect(find.text(expectedTitle), findsOneWidget);
      });
    });
  });

  testWidgets('shows cancelling spinner when isCancelled', (tester) async {
    await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a', 'b'],
        isCancelled: true,
        results: {
          'a': ProjectOutcome(status: ProjectResultStatus.inProgress),
          'b': ProjectOutcome(status: ProjectResultStatus.pending),
        },
      ),
    );
    expect(find.textContaining('Cancelling'), findsOneWidget);
    // No cancel / close buttons while cancelling is in flight.
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('current project block shows step + determinate progress',
      (tester) async {
    await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a', 'b'],
        currentIndex: 0,
        currentProjectName: 'project-a',
        currentStep: 'Translating units',
        currentProjectProgress: 0.5,
        results: {
          'a': ProjectOutcome(status: ProjectResultStatus.inProgress),
          'b': ProjectOutcome(status: ProjectResultStatus.pending),
        },
      ),
    );
    expect(find.text('project-a'), findsOneWidget);
    expect(find.text('Translating units'), findsOneWidget);
  });

  testWidgets('current project block handles null name + empty step',
      (tester) async {
    await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.rescan,
        targetLanguageCode: 'fr',
        projectIds: ['a'],
        currentStep: '',
        currentProjectProgress: -1,
        results: {
          'a': ProjectOutcome(status: ProjectResultStatus.inProgress),
        },
      ),
    );
    // Null name renders the em-dash placeholder.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('timeline renders every status with messages + colours',
      (tester) async {
    await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'],
        projectNames: {
          'p1': 'Pending One',
          'p2': 'In Progress Two',
          // p3 has no name => falls back to id.
          'p4': 'Skipped Four',
          'p5': 'Failed Five',
          'p6': 'Cancelled Six',
        },
        results: {
          // Pending + inProgress carry messages so _statusColor's shared
          // textDim case labels are exercised for those statuses too.
          'p1': ProjectOutcome(
            status: ProjectResultStatus.pending,
            message: 'Queued',
          ),
          'p2': ProjectOutcome(
            status: ProjectResultStatus.inProgress,
            message: 'Working',
          ),
          'p3': ProjectOutcome(
            status: ProjectResultStatus.succeeded,
            message: 'Done',
          ),
          'p4': ProjectOutcome(
            status: ProjectResultStatus.skipped,
            message: 'No changes',
          ),
          'p5': ProjectOutcome(
            status: ProjectResultStatus.failed,
            message: 'Boom',
          ),
          'p6': ProjectOutcome(
            status: ProjectResultStatus.cancelled,
            message: 'Stopped',
          ),
        },
      ),
    );
    expect(find.text('Pending One'), findsOneWidget);
    expect(find.text('In Progress Two'), findsOneWidget);
    // p3 falls back to its id since no projectNames entry exists.
    expect(find.text('p3'), findsOneWidget);
    expect(find.text('Skipped Four'), findsOneWidget);
    expect(find.text('Failed Five'), findsOneWidget);
    expect(find.text('Cancelled Six'), findsOneWidget);
    // Outcome messages render on the right.
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('No changes'), findsOneWidget);
    expect(find.text('Boom'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets('empty project list yields 0% overall progress', (tester) async {
    await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.generatePack,
        targetLanguageCode: 'fr',
        projectIds: [],
        results: {},
      ),
    );
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('complete with zero failures hides retry button',
      (tester) async {
    await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a', 'b'],
        isComplete: true,
        results: {
          'a': ProjectOutcome(status: ProjectResultStatus.succeeded),
          'b': ProjectOutcome(status: ProjectResultStatus.skipped),
        },
      ),
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Retry failed'), findsNothing);
  });

  testWidgets('Close button resets the notifier and pops the dialog',
      (tester) async {
    _sizeView(tester);
    // Open the dialog through a real route so Navigator.pop has something to
    // pop, exercising the close branch's reset + pop.
    late _TestBulkNotifier notifier;
    final complete = const BulkOperationState(
      operationType: BulkOperationType.translate,
      targetLanguageCode: 'fr',
      projectIds: ['a'],
      isComplete: true,
      results: {'a': ProjectOutcome(status: ProjectResultStatus.succeeded)},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bulkOperationsProvider.overrideWith(() {
            notifier = _TestBulkNotifier(complete);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => const BulkOperationProgressDialog(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(notifier.resetCalls, 1);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('Cancel button opens confirm dialog and cancels on Stop',
      (tester) async {
    final notifier = await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a'],
        results: {'a': ProjectOutcome(status: ProjectResultStatus.inProgress)},
      ),
    );

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    // Confirm dialog appears.
    expect(find.text('Stop the current operation?'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(notifier.cancelCalls, 1);
  });

  testWidgets('Cancel confirm dialog dismissed via Keep running does not cancel',
      (tester) async {
    final notifier = await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a'],
        results: {'a': ProjectOutcome(status: ProjectResultStatus.inProgress)},
      ),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Keep running'), findsOneWidget);
    await tester.tap(find.text('Keep running'));
    await tester.pump();

    expect(notifier.cancelCalls, 0);
  });

  testWidgets('Retry failed re-runs only the failed projects', (tester) async {
    final notifier = await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a', 'b'],
        isComplete: true,
        results: {
          'a': ProjectOutcome(status: ProjectResultStatus.succeeded),
          'b': ProjectOutcome(status: ProjectResultStatus.failed),
        },
      ),
      extraOverrides: [
        // Provide an empty-but-resolved scope so _retryFailed proceeds past the
        // null guard; matching is empty so it re-runs with zero failed projects.
        visibleProjectsForBulkProvider.overrideWithValue(
          const AsyncValue.data((visible: [], matching: [])),
        ),
      ],
    );

    expect(find.text('Retry failed'), findsOneWidget);
    await tester.tap(find.text('Retry failed'));
    await tester.pump();

    expect(notifier.resetCalls, 1);
    expect(notifier.runCalls, hasLength(1));
    expect(notifier.runCalls.single.type, BulkOperationType.translate);
    expect(notifier.runCalls.single.lang, 'fr');
  });

  testWidgets('Retry failed bails when scope is unresolved', (tester) async {
    final notifier = await _pumpDialog(
      tester,
      const BulkOperationState(
        operationType: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projectIds: ['a'],
        isComplete: true,
        results: {'a': ProjectOutcome(status: ProjectResultStatus.failed)},
      ),
      extraOverrides: [
        visibleProjectsForBulkProvider.overrideWithValue(
          const AsyncValue.loading(),
        ),
      ],
    );

    await tester.tap(find.text('Retry failed'));
    await tester.pump();

    // Loading scope => asData?.value is null => early return, no run/reset.
    expect(notifier.resetCalls, 0);
    expect(notifier.runCalls, isEmpty);
  });
}
