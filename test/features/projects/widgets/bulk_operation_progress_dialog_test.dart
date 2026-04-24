import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';
import 'package:twmt/theme/app_theme.dart';

/// Test notifier that lets tests set the state directly without running anything.
class _TestBulkNotifier extends BulkOperationsNotifier {
  _TestBulkNotifier(this._initial);
  final BulkOperationState _initial;
  @override
  BulkOperationState build() => _initial;
}

Future<void> _pumpDialog(
  WidgetTester tester,
  BulkOperationState state,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      bulkOperationsProvider.overrideWith(() => _TestBulkNotifier(state)),
    ],
    child: MaterialApp(
      theme: AppTheme.atelierDarkTheme,
      home: const BulkOperationProgressDialog(),
    ),
  ));
  // pumpAndSettle would time out due to infinite progress indicator animations.
  await tester.pump();
}

void main() {
  setUp(() {
    // The token dialog renders at 560x420+ which does not fit the default
    // 800x600 test viewport once title + action rows are added. Give it
    // enough headroom so layout doesn't overflow during assertions.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('shows Cancel button while running', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final running = BulkOperationState(
      operationType: BulkOperationType.translate,
      targetLanguageCode: 'fr',
      projectIds: ['a', 'b'],
      results: const {
        'a': ProjectOutcome(status: ProjectResultStatus.inProgress),
        'b': ProjectOutcome(status: ProjectResultStatus.pending),
      },
      currentProjectName: 'project-a',
      currentStep: 'Translating',
    );
    await _pumpDialog(tester, running);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('shows Close + summary when isComplete', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final complete = BulkOperationState(
      operationType: BulkOperationType.translate,
      targetLanguageCode: 'fr',
      projectIds: ['a', 'b', 'c'],
      results: const {
        'a': ProjectOutcome(status: ProjectResultStatus.succeeded),
        'b': ProjectOutcome(status: ProjectResultStatus.succeeded),
        'c': ProjectOutcome(status: ProjectResultStatus.failed),
      },
      isComplete: true,
    );
    await _pumpDialog(tester, complete);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.textContaining('2 succeeded'), findsOneWidget);
    expect(find.textContaining('1 failed'), findsOneWidget);
    expect(find.text('Retry failed'), findsOneWidget);
  });
}
