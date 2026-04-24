import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';

/// Test notifier that lets tests set the state directly without running anything.
class _TestBulkNotifier extends BulkOperationsNotifier {
  _TestBulkNotifier(this._initial);
  final BulkOperationState _initial;
  @override
  BulkOperationState build() => _initial;
}

void main() {
  testWidgets('shows Cancel button while running', (tester) async {
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bulkOperationsProvider.overrideWith(() => _TestBulkNotifier(running)),
      ],
      child: const MaterialApp(home: BulkOperationProgressDialog()),
    ));
    // pumpAndSettle would time out due to infinite progress indicator animations.
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('shows Close + summary when isComplete', (tester) async {
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bulkOperationsProvider.overrideWith(() => _TestBulkNotifier(complete)),
      ],
      child: const MaterialApp(home: BulkOperationProgressDialog()),
    ));
    // pumpAndSettle would time out due to infinite progress indicator animations.
    await tester.pump();
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.textContaining('2 succeeded'), findsOneWidget);
    expect(find.textContaining('1 failed'), findsOneWidget);
    expect(find.text('Retry failed'), findsOneWidget);
  });
}
