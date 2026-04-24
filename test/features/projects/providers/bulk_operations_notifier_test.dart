import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';
import 'package:twmt/models/domain/project.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeProject extends Fake implements Project {
  _FakeProject(this.id, this.name);

  @override
  final String id;

  @override
  final String name;

  @override
  final String gameInstallationId = 'game-1';
}

class _FakeProjectWithDetails extends Fake implements ProjectWithDetails {
  _FakeProjectWithDetails(String id, String name)
      : project = _FakeProject(id, name);

  @override
  final Project project;

  @override
  List<ProjectLanguageWithInfo> get languages => [];
}

// ---------------------------------------------------------------------------
// Stub handlers
// ---------------------------------------------------------------------------

/// Handler stub that always returns succeeded — or can be configured to throw
/// or wait on a Completer.
class _StubBulkHandlers extends BulkHandlers {
  final int? throwOnIndex;
  final Completer<void>? pauseOnIndex;
  int callCount = 0;

  _StubBulkHandlers({this.throwOnIndex, this.pauseOnIndex});

  Future<ProjectOutcome> _handle(int index) async {
    if (pauseOnIndex != null && index == 0) {
      await pauseOnIndex!.future;
    }
    if (throwOnIndex != null && index == throwOnIndex) {
      throw Exception('stub error on project $index');
    }
    return const ProjectOutcome(status: ProjectResultStatus.succeeded);
  }

  @override
  Future<ProjectOutcome> translate({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) async {
    final idx = callCount++;
    return _handle(idx);
  }

  @override
  Future<ProjectOutcome> rescan({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) async {
    final idx = callCount++;
    return _handle(idx);
  }

  @override
  Future<ProjectOutcome> forceValidate({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) async {
    final idx = callCount++;
    return _handle(idx);
  }

  @override
  Future<ProjectOutcome> generatePack({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) async {
    final idx = callCount++;
    return _handle(idx);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<ProjectWithDetails> _fakeProjects(int count) => [
      for (var i = 0; i < count; i++)
        _FakeProjectWithDetails('proj-$i', 'Project $i'),
    ];

ProviderContainer _makeContainer(_StubBulkHandlers stub) {
  return ProviderContainer(
    overrides: [
      bulkHandlersProvider.overrideWithValue(stub),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BulkOperationsNotifier', () {
    test('runs through all projects and reports succeeded', () async {
      final stub = _StubBulkHandlers();
      final container = _makeContainer(stub);
      addTearDown(container.dispose);

      final projects = _fakeProjects(3);

      await container.read(bulkOperationsProvider.notifier).run(
            type: BulkOperationType.translate,
            targetLanguageCode: 'fr',
            projects: projects,
          );

      final state = container.read(bulkOperationsProvider);

      expect(state.isComplete, isTrue);
      expect(state.countByStatus(ProjectResultStatus.succeeded), 3);
      expect(state.currentIndex, 2);
    });

    test('cancel mid-run marks remaining projects cancelled', () async {
      final completer = Completer<void>();
      final stub = _StubBulkHandlers(pauseOnIndex: completer);
      final container = _makeContainer(stub);
      addTearDown(container.dispose);

      final projects = _fakeProjects(3);
      final notifier = container.read(bulkOperationsProvider.notifier);

      // Start the run without awaiting — it will pause on project 0
      final runFuture = notifier.run(
        type: BulkOperationType.translate,
        targetLanguageCode: 'fr',
        projects: projects,
      );

      // Let the event loop tick so the notifier enters its first await
      await Future<void>.delayed(Duration.zero);

      // Cancel while project 0 is blocked
      await notifier.cancel();

      // Unblock project 0 so the run loop can proceed and see the cancellation
      completer.complete();

      await runFuture;

      final state = container.read(bulkOperationsProvider);

      // Handler was called exactly once (project 0) — projects 1 and 2 never ran
      expect(stub.callCount, 1);

      // Projects 1 and 2 should be marked cancelled
      expect(
        state.results['proj-1']?.status,
        ProjectResultStatus.cancelled,
      );
      expect(
        state.results['proj-2']?.status,
        ProjectResultStatus.cancelled,
      );
    });

    test('handler exception marks project failed, loop continues', () async {
      // Throw on the second project (call index 1)
      final stub = _StubBulkHandlers(throwOnIndex: 1);
      final container = _makeContainer(stub);
      addTearDown(container.dispose);

      final projects = _fakeProjects(3);

      await container.read(bulkOperationsProvider.notifier).run(
            type: BulkOperationType.translate,
            targetLanguageCode: 'fr',
            projects: projects,
          );

      final state = container.read(bulkOperationsProvider);

      expect(state.isComplete, isTrue);

      expect(
        state.results['proj-0']?.status,
        ProjectResultStatus.succeeded,
      );
      expect(
        state.results['proj-1']?.status,
        ProjectResultStatus.failed,
      );
      expect(state.results['proj-1']?.error, isNotNull);
      expect(
        state.results['proj-2']?.status,
        ProjectResultStatus.succeeded,
      );
    });
  });
}
