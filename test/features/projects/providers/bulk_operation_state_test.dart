import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';

void main() {
  group('BulkOperationState', () {
    test('idle() returns state with no operation and empty results', () {
      final s = BulkOperationState.idle();
      expect(s.operationType, isNull);
      expect(s.projectIds, isEmpty);
      expect(s.results, isEmpty);
      expect(s.isComplete, false);
      expect(s.isCancelled, false);
    });

    test('copyWith returns new instance with overridden field', () {
      final s = BulkOperationState.idle();
      final s2 = s.copyWith(currentIndex: 5, isComplete: true);
      expect(s2.currentIndex, 5);
      expect(s2.isComplete, true);
      expect(s.currentIndex, 0);
    });

    test('counts by status reflect results map', () {
      final s = BulkOperationState.idle().copyWith(results: {
        'a': const ProjectOutcome(status: ProjectResultStatus.succeeded),
        'b': const ProjectOutcome(status: ProjectResultStatus.succeeded),
        'c': const ProjectOutcome(status: ProjectResultStatus.skipped),
        'd': const ProjectOutcome(status: ProjectResultStatus.failed),
      });
      expect(s.countByStatus(ProjectResultStatus.succeeded), 2);
      expect(s.countByStatus(ProjectResultStatus.skipped), 1);
      expect(s.countByStatus(ProjectResultStatus.failed), 1);
    });

    test('failedProjectIds returns projectIds with failed outcome in order', () {
      final s = BulkOperationState.idle().copyWith(
        projectIds: ['a', 'b', 'c', 'd'],
        results: {
          'a': const ProjectOutcome(status: ProjectResultStatus.succeeded),
          'b': const ProjectOutcome(status: ProjectResultStatus.failed),
          'c': const ProjectOutcome(status: ProjectResultStatus.failed),
          'd': const ProjectOutcome(status: ProjectResultStatus.succeeded),
        },
      );
      expect(s.failedProjectIds, ['b', 'c']);
    });

    test('clearCurrentStep resets currentStep to null', () {
      final s = BulkOperationState.idle().copyWith(currentStep: 'Translating');
      expect(s.currentStep, 'Translating');
      final cleared = s.copyWith(clearCurrentStep: true);
      expect(cleared.currentStep, isNull);
    });
  });
}
