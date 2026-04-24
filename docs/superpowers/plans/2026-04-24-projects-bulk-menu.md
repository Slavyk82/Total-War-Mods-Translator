# Projects Bulk Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the right-side 320 px bulk menu panel on the Projects screen with a target-language selector, shared translation settings, and four actions (Translate all, Rescan reviews, Force validate reviews, Generate pack) that operate on the currently visible projects via a unified `BulkOperationsNotifier` driving a modal progress dialog.

**Architecture:** One unified Riverpod notifier drives a sequential loop over visible projects, dispatching to four pure handler functions by `BulkOperationType`. The translate handler awaits the existing `ITranslationOrchestrator` stream; other handlers call existing repository/service methods. A modal dialog watches the notifier state and shows per-project progress + a final retry-able summary.

**Tech Stack:** Flutter 3.x (Windows desktop), Riverpod 2 (Notifier/AsyncNotifier), SQLite via existing repositories, SharedPreferences for UI state persistence, `mocktail` + `flutter_test` for tests.

**Design spec:** `docs/superpowers/specs/2026-04-24-projects-bulk-menu-design.md`

---

## Phase 1 — Foundation Providers

### Task 1: `bulkTargetLanguageProvider` (with SharedPrefs persistence)

**Files:**
- Create: `lib/features/projects/providers/bulk_target_language_provider.dart`
- Create: `test/features/projects/providers/bulk_target_language_provider_test.dart`

**Context:** Holds the currently selected target language code (e.g. `"fr"`, `"de"`) for bulk actions. Persisted under SharedPrefs key `projects_bulk_target_lang`. `null` means no selection.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/projects/providers/bulk_target_language_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to null when no pref stored', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(bulkTargetLanguageProvider.future), isNull);
  });

  test('setLanguage persists and updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkTargetLanguageProvider.future);
    await container.read(bulkTargetLanguageProvider.notifier).setLanguage('fr');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('projects_bulk_target_lang'), 'fr');
    expect(container.read(bulkTargetLanguageProvider).value, 'fr');
  });

  test('loads existing pref on init', () async {
    SharedPreferences.setMockInitialValues({'projects_bulk_target_lang': 'de'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(bulkTargetLanguageProvider.future), 'de');
  });

  test('setLanguage(null) clears pref', () async {
    SharedPreferences.setMockInitialValues({'projects_bulk_target_lang': 'de'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkTargetLanguageProvider.future);
    await container.read(bulkTargetLanguageProvider.notifier).setLanguage(null);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('projects_bulk_target_lang'), isNull);
    expect(container.read(bulkTargetLanguageProvider).value, isNull);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (file missing)**

```bash
flutter test test/features/projects/providers/bulk_target_language_provider_test.dart
```

- [ ] **Step 3: Implement provider**

```dart
// lib/features/projects/providers/bulk_target_language_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'projects_bulk_target_lang';

class BulkTargetLanguageNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  Future<void> setLanguage(String? code) async {
    state = AsyncValue.data(code);
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, code);
    }
  }
}

final bulkTargetLanguageProvider =
    AsyncNotifierProvider<BulkTargetLanguageNotifier, String?>(
      BulkTargetLanguageNotifier.new,
    );
```

- [ ] **Step 4: Run test — expect PASS**

```bash
flutter test test/features/projects/providers/bulk_target_language_provider_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/providers/bulk_target_language_provider.dart \
        test/features/projects/providers/bulk_target_language_provider_test.dart
git commit -m "feat(projects): add bulkTargetLanguageProvider with SharedPrefs persistence"
```

---

### Task 2: `bulkInfoCardDismissedProvider`

**Files:**
- Create: `lib/features/projects/providers/bulk_info_card_dismissed_provider.dart`
- Create: `test/features/projects/providers/bulk_info_card_dismissed_provider_test.dart`

**Context:** Boolean pref under `projects_bulk_info_dismissed`. Defaults to `false`. `dismiss()` sets to true; `reset()` sets back to false (to re-show).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/projects/providers/bulk_info_card_dismissed_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to false', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(bulkInfoCardDismissedProvider.future), false);
  });

  test('dismiss() sets true and persists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkInfoCardDismissedProvider.future);
    await container.read(bulkInfoCardDismissedProvider.notifier).dismiss();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('projects_bulk_info_dismissed'), true);
    expect(container.read(bulkInfoCardDismissedProvider).value, true);
  });

  test('reset() sets false', () async {
    SharedPreferences.setMockInitialValues({'projects_bulk_info_dismissed': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkInfoCardDismissedProvider.future);
    await container.read(bulkInfoCardDismissedProvider.notifier).reset();
    expect(container.read(bulkInfoCardDismissedProvider).value, false);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
flutter test test/features/projects/providers/bulk_info_card_dismissed_provider_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/features/projects/providers/bulk_info_card_dismissed_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'projects_bulk_info_dismissed';

class BulkInfoCardDismissedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  Future<void> dismiss() async {
    state = const AsyncValue.data(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  Future<void> reset() async {
    state = const AsyncValue.data(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
  }
}

final bulkInfoCardDismissedProvider =
    AsyncNotifierProvider<BulkInfoCardDismissedNotifier, bool>(
      BulkInfoCardDismissedNotifier.new,
    );
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/providers/bulk_info_card_dismissed_provider.dart \
        test/features/projects/providers/bulk_info_card_dismissed_provider_test.dart
git commit -m "feat(projects): add bulkInfoCardDismissedProvider"
```

---

### Task 3: `BulkOperationState` + enums

**Files:**
- Create: `lib/features/projects/providers/bulk_operation_state.dart`
- Create: `test/features/projects/providers/bulk_operation_state_test.dart`

**Context:** Immutable state class + enums for the unified notifier. This task is pure data modeling — no business logic, no side effects.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/projects/providers/bulk_operation_state_test.dart
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
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement state**

```dart
// lib/features/projects/providers/bulk_operation_state.dart
import 'package:flutter/foundation.dart';

enum BulkOperationType { translate, rescan, forceValidate, generatePack }

enum ProjectResultStatus {
  pending,
  inProgress,
  succeeded,
  skipped,
  failed,
  cancelled,
}

@immutable
class ProjectOutcome {
  final ProjectResultStatus status;
  final String? message;
  final Object? error;

  const ProjectOutcome({required this.status, this.message, this.error});
}

@immutable
class BulkOperationState {
  final BulkOperationType? operationType;
  final String? targetLanguageCode;
  final List<String> projectIds;
  final int currentIndex;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentStep;
  final double currentProjectProgress;
  final Map<String, ProjectOutcome> results;
  final bool isCancelled;
  final bool isComplete;

  const BulkOperationState({
    this.operationType,
    this.targetLanguageCode,
    this.projectIds = const [],
    this.currentIndex = 0,
    this.currentProjectId,
    this.currentProjectName,
    this.currentStep,
    this.currentProjectProgress = -1,
    this.results = const {},
    this.isCancelled = false,
    this.isComplete = false,
  });

  factory BulkOperationState.idle() => const BulkOperationState();

  int countByStatus(ProjectResultStatus s) =>
      results.values.where((o) => o.status == s).length;

  List<String> get failedProjectIds =>
      projectIds.where((id) => results[id]?.status == ProjectResultStatus.failed)
          .toList();

  BulkOperationState copyWith({
    BulkOperationType? operationType,
    String? targetLanguageCode,
    List<String>? projectIds,
    int? currentIndex,
    String? currentProjectId,
    String? currentProjectName,
    String? currentStep,
    double? currentProjectProgress,
    Map<String, ProjectOutcome>? results,
    bool? isCancelled,
    bool? isComplete,
  }) {
    return BulkOperationState(
      operationType: operationType ?? this.operationType,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
      projectIds: projectIds ?? this.projectIds,
      currentIndex: currentIndex ?? this.currentIndex,
      currentProjectId: currentProjectId ?? this.currentProjectId,
      currentProjectName: currentProjectName ?? this.currentProjectName,
      currentStep: currentStep ?? this.currentStep,
      currentProjectProgress: currentProjectProgress ?? this.currentProjectProgress,
      results: results ?? this.results,
      isCancelled: isCancelled ?? this.isCancelled,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/providers/bulk_operation_state.dart \
        test/features/projects/providers/bulk_operation_state_test.dart
git commit -m "feat(projects): add BulkOperationState model and enums"
```

---

## Phase 2 — Headless Execution Services

### Task 4: Extract headless validation rescan service

**Files:**
- Create: `lib/services/translation/headless_validation_rescan_service.dart`
- Create: `test/services/translation/headless_validation_rescan_service_test.dart`

**Context:** This task is a **port**, not a greenfield implementation. The editor's `_performRescan()` (in `editor_actions_validation.dart` lines 73–319, ~246 lines) is editor-scoped — it pulls the project language from the editor's state via `getProjectLanguageId()`, and it publishes progress to a `progressNotifier`. We need a pure function that does the same validation rescan work but accepts the `projectLanguageId` as a parameter and drops the UI side effects (progress notifier updates and dialog calls).

**The executor must read `editor_actions_validation.dart` lines 73–319 in full and reproduce the same algorithm.** The plan cannot inline 246 lines of ported code. The goals of the port are: (1) same DB reads / writes, (2) same validation logic, (3) same result shape, (4) zero dependence on editor state or `BuildContext`.

Return a result record:

```dart
typedef RescanResult = ({
  int scanned,
  int newIssues,
  int cleared,
  int unchanged,
  int needsReviewTotal,
});
```

- [ ] **Step 1: Write the failing test with a mocked `TranslationVersionRepository`**

```dart
// test/services/translation/headless_validation_rescan_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/services/translation/headless_validation_rescan_service.dart';

class _MockRepo extends Mock implements TranslationVersionRepository {}

void main() {
  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
  });

  test('returns zero-valued result when no translated units', () async {
    when(() => repo.getTranslatedVersions(projectLanguageId: any(named: 'projectLanguageId')))
        .thenAnswer((_) async => const Ok([]));
    final container = ProviderContainer(overrides: [
      translationVersionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final result = await runHeadlessValidationRescan(
      ref: container,
      projectLanguageId: 'pl-1',
    );

    expect(result.scanned, 0);
    expect(result.needsReviewTotal, 0);
  });

  // Additional tests for the happy path will be added once the internals
  // mirror `_performRescan`. Minimum requirement for green: the function
  // exists, is callable, and handles the empty-units path.
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Scaffold the public API of the service**

Create `lib/services/translation/headless_validation_rescan_service.dart` with exactly this public shape (the private body is ported from the reference file in Step 4):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
// Add the same domain imports used by editor_actions_validation.dart
// (validation engine, translation version repository, etc.) — list them
// after reading the reference file.

typedef RescanResult = ({
  int scanned,
  int newIssues,
  int cleared,
  int unchanged,
  int needsReviewTotal,
});

Future<RescanResult> runHeadlessValidationRescan({
  required Ref ref,
  required String projectLanguageId,
}) async {
  final repo = ref.read(translationVersionRepositoryProvider);
  final translatedResult =
      await repo.getTranslatedVersions(projectLanguageId: projectLanguageId);
  final translated = translatedResult.unwrap();
  if (translated.isEmpty) {
    return (scanned: 0, newIssues: 0, cleared: 0, unchanged: 0, needsReviewTotal: 0);
  }
  // Step 4 of this task ports the rest of _performRescan here: iterate
  // `translated`, run the validation engine on each, accumulate the four
  // counters, compute `needsReviewTotal`, and call
  // `repo.updateValidationBatch(pendingUpdates)` when there are changes
  // (pattern from editor_actions_validation.dart lines 73-319).
  throw UnimplementedError('Port _performRescan body (step 4)');
}
```

- [ ] **Step 4: Port the full algorithm from `_performRescan`**

Open `lib/features/translation_editor/screens/actions/editor_actions_validation.dart` at line 73 and read through line 319. Reproduce the same steps in the function above:

1. Fetch translated versions for the project-language (already done in Step 3).
2. For each version, run the validation engine (same class and method calls as the editor) to detect issues.
3. Compare against the previously stored `validation_issues` to compute `newIssues`, `cleared`, and `unchanged`.
4. Build the list of updates with `{versionId, status, validationIssues, schemaVersion}`.
5. Call `repo.updateValidationBatch(updates)` if non-empty.
6. Compute `needsReviewTotal` (count of versions in `needsReview` status after the update).
7. Return the five-field record.

Every UI-bound call (`progressNotifier.value = …`, `showDialog(...)`, etc.) is dropped — this function is headless. The progress is reported back to the bulk notifier via the existing `onProgress` callback at the handler level, not here.

Remove the `throw UnimplementedError(...)` line once the port is complete.

- [ ] **Step 4: Run — expect PASS on the empty-units case**

- [ ] **Step 5: Commit**

```bash
git add lib/services/translation/headless_validation_rescan_service.dart \
        test/services/translation/headless_validation_rescan_service_test.dart
git commit -m "feat(translation): add headless validation rescan service"
```

---

### Task 5: Add headless awaitable batch translation runner

**Files:**
- Create: `lib/services/translation/headless_batch_translation_runner.dart`
- Create: `test/services/translation/headless_batch_translation_runner_test.dart`

**Context:** The current batch flow goes through `TranslationProgressScreen` (UI-driven). For bulk we need a programmatic runner that:
1. Calls `TranslationBatchHelper.createAndPrepareBatch()` (returns `batchId`).
2. Builds the translation context via `TranslationBatchHelper.buildTranslationContext()`.
3. Calls `translationOrchestratorService.translateBatchesParallel(batchIds: [batchId], context, maxParallel: settings.parallelBatches)` — returns a `Stream<Result<TranslationProgress, …>>`.
4. Listens to the stream, surfaces progress via `onProgress` callback, and completes the returned `Future` when the stream emits a final `completed` or `failed` event.
5. Supports cancellation by exposing the `batchId` so the caller can invoke `orchestrator.stopTranslation(batchId: …)`.

**Read first:**
- `lib/services/translation/i_translation_orchestrator.dart` — the interface (especially `translateBatchesParallel` and `stopTranslation`)
- `lib/features/translation_editor/utils/translation_batch_helper.dart` — `createAndPrepareBatch` and `buildTranslationContext`
- `lib/services/translation/models/translation_progress.dart` — `TranslationProgressStatus` enum values

Public API:

```dart
class HeadlessBatchTranslationRunner {
  HeadlessBatchTranslationRunner(this._ref);
  final Ref _ref;

  /// Non-null while a batch is running.
  String? get currentBatchId;

  /// Runs a single batch end-to-end. Completes when orchestrator emits
  /// a terminal event. Throws on failure, returns count of translated
  /// units on success.
  Future<int> run({
    required String projectLanguageId,
    required List<String> unitIds,
    required bool skipTM,
    required String providerId,
    void Function(String step, double progress)? onProgress,
  });

  /// Aggressively stops any currently running batch. Safe to call even
  /// if nothing is running.
  Future<void> stop();
}

final headlessBatchTranslationRunnerProvider =
    Provider<HeadlessBatchTranslationRunner>(
      (ref) => HeadlessBatchTranslationRunner(ref),
    );
```

- [ ] **Step 1: Write the failing test (with mocked orchestrator)**

```dart
// test/services/translation/headless_batch_translation_runner_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';

class _MockOrchestrator extends Mock implements ITranslationOrchestrator {}

void main() {
  late _MockOrchestrator orchestrator;

  setUp(() {
    orchestrator = _MockOrchestrator();
    registerFallbackValue(TranslationContext.empty());
  });

  test('completes when stream emits completed status', () async {
    final controller = StreamController<Result<TranslationProgress,
        TranslationOrchestrationException>>();
    when(() => orchestrator.translateBatchesParallel(
          batchIds: any(named: 'batchIds'),
          context: any(named: 'context'),
          maxParallel: any(named: 'maxParallel'),
        )).thenAnswer((_) => controller.stream);

    final container = ProviderContainer(overrides: [
      translationOrchestratorServiceProvider.overrideWithValue(orchestrator),
      // Override createAndPrepareBatch + buildTranslationContext via a
      // test-level seam (see implementation hint below).
    ]);
    addTearDown(container.dispose);

    final runner = container.read(headlessBatchTranslationRunnerProvider);

    final future = runner.run(
      projectLanguageId: 'pl-1',
      unitIds: ['u1', 'u2'],
      skipTM: false,
      providerId: 'openai',
    );

    controller.add(Ok(TranslationProgress(
      batchId: 'b1',
      status: TranslationProgressStatus.completed,
      totalUnits: 2,
      processedUnits: 2,
      successfulUnits: 2,
      failedUnits: 0,
      skippedUnits: 0,
    )));
    await controller.close();

    final translated = await future;
    expect(translated, 2);
  });

  test('stop() calls orchestrator.stopTranslation with current batch id', () async {
    // similar setup; after run() starts, call runner.stop() and verify
    // orchestrator.stopTranslation was invoked with the same batchId
    // returned by createAndPrepareBatch.
  }, skip: 'Fill in after basic happy path passes');
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement the runner**

```dart
// lib/services/translation/headless_batch_translation_runner.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/utils/translation_batch_helper.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';

class HeadlessBatchTranslationRunner {
  HeadlessBatchTranslationRunner(this._ref);
  final Ref _ref;

  String? _currentBatchId;
  String? get currentBatchId => _currentBatchId;

  Future<int> run({
    required String projectLanguageId,
    required List<String> unitIds,
    required bool skipTM,
    required String providerId,
    void Function(String step, double progress)? onProgress,
  }) async {
    final batchId = await TranslationBatchHelper.createAndPrepareBatch(
      ref: _ref,
      projectLanguageId: projectLanguageId,
      unitIds: unitIds,
      providerId: providerId,
      onError: () => throw StateError('Batch preparation failed'),
    );
    if (batchId == null) {
      throw StateError('createAndPrepareBatch returned null');
    }
    _currentBatchId = batchId;

    final context = await TranslationBatchHelper.buildTranslationContext(
      ref: _ref,
      projectLanguageId: projectLanguageId,
      skipTM: skipTM,
    );
    final settings = _ref.read(translationSettingsProvider);
    final orchestrator = _ref.read(translationOrchestratorServiceProvider);

    final stream = orchestrator.translateBatchesParallel(
      batchIds: [batchId],
      context: context,
      maxParallel: settings.parallelBatches,
    );

    int translated = 0;
    try {
      await for (final event in stream) {
        if (event.isErr) {
          throw event.unwrapErr();
        }
        final progress = event.unwrap();
        onProgress?.call(
          'Translating (${progress.processedUnits}/${progress.totalUnits})',
          progress.totalUnits == 0 ? -1 : progress.processedUnits / progress.totalUnits,
        );
        if (progress.status == TranslationProgressStatus.completed) {
          translated = progress.successfulUnits;
          break;
        }
        if (progress.status == TranslationProgressStatus.failed) {
          throw StateError('Batch failed: batchId=$batchId');
        }
      }
    } finally {
      _currentBatchId = null;
    }
    return translated;
  }

  Future<void> stop() async {
    final id = _currentBatchId;
    if (id == null) return;
    final orchestrator = _ref.read(translationOrchestratorServiceProvider);
    await orchestrator.stopTranslation(batchId: id);
  }
}

final headlessBatchTranslationRunnerProvider =
    Provider<HeadlessBatchTranslationRunner>(
      (ref) => HeadlessBatchTranslationRunner(ref),
    );
```

Exact member names on `TranslationProgress` (`processedUnits`, `successfulUnits`, etc.) must match the existing model; adjust if the model uses different names.

- [ ] **Step 4: Run — expect PASS on the happy path**

- [ ] **Step 5: Commit**

```bash
git add lib/services/translation/headless_batch_translation_runner.dart \
        test/services/translation/headless_batch_translation_runner_test.dart
git commit -m "feat(translation): add headless awaitable batch translation runner"
```

---

## Phase 3 — Core Orchestration

### Task 6: Bulk operation handlers (4 pure functions)

**Files:**
- Create: `lib/features/projects/services/bulk_operations_handlers.dart`
- Create: `test/features/projects/services/bulk_operations_handlers_test.dart`

**Context:** One function per `BulkOperationType`. Each takes `(ref, project, targetLanguageCode)`, skips on the documented condition, runs the core action, returns `ProjectOutcome`.

**API shape:**

```dart
typedef HandlerResult = Future<ProjectOutcome>;

HandlerResult runBulkTranslate({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  void Function(String step, double progress)? onProgress,
});

HandlerResult runBulkRescan(...); // same signature shape
HandlerResult runBulkForceValidate(...);
HandlerResult runBulkGeneratePack(...);
```

- [ ] **Step 1: Write failing tests — one per handler, covering happy path + skip case**

```dart
// test/features/projects/services/bulk_operations_handlers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';

class _FakeProjectWithDetails extends Fake implements ProjectWithDetails {
  _FakeProjectWithDetails({required this.languageCodes});
  final List<String> languageCodes;

  @override
  List<ProjectLanguageWithInfo> get languages => languageCodes
      .map((c) => _FakeProjectLanguage(c))
      .toList();
}

class _FakeProjectLanguage extends Fake implements ProjectLanguageWithInfo {
  _FakeProjectLanguage(String code) : _code = code;
  final String _code;
  @override
  Language? get language => _FakeLanguage(_code);
}

class _FakeLanguage extends Fake implements Language {
  _FakeLanguage(this.code);
  @override
  final String code;
}

void main() {
  group('runBulkTranslate', () {
    test('skips when project has no target language configured', () async {
      final project = _FakeProjectWithDetails(languageCodes: ['en']);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final outcome = await runBulkTranslate(
        ref: container,
        project: project,
        targetLanguageCode: 'fr',
      );

      expect(outcome.status, ProjectResultStatus.skipped);
      expect(outcome.message, contains('language not configured'));
    });

    // Happy path test to be added once the handler shape is stable;
    // stub the headless runner provider + untranslated ids helper.
  });

  // Analogous skipped-case tests for rescan / forceValidate / generatePack
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement the handlers**

```dart
// lib/features/projects/services/bulk_operations_handlers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/translation_editor/providers/llm_model_providers.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/utils/translation_batch_helper.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/services/translation/headless_validation_rescan_service.dart';

typedef HandlerCallback = void Function(String step, double progress);

ProjectLanguageWithInfo? _findLanguage(
  ProjectWithDetails project,
  String code,
) {
  for (final l in project.languages) {
    if (l.language?.code == code) return l;
  }
  return null;
}

Future<ProjectOutcome> runBulkTranslate({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final projectLang = _findLanguage(project, targetLanguageCode);
  if (projectLang == null) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'language not configured',
    );
  }
  final projectLanguageId = projectLang.projectLanguage.id;

  final untranslated = await TranslationBatchHelper.getUntranslatedUnitIds(
    ref: ref,
    projectLanguageId: projectLanguageId,
  );
  if (untranslated.isEmpty) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'no untranslated units',
    );
  }

  final settings = ref.read(translationSettingsProvider);
  final providerId = ref.read(selectedLlmModelProvider);
  if (providerId == null) {
    return const ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: 'no LLM model selected',
    );
  }

  try {
    final runner = ref.read(headlessBatchTranslationRunnerProvider);
    final translated = await runner.run(
      projectLanguageId: projectLanguageId,
      unitIds: untranslated,
      skipTM: settings.skipTranslationMemory,
      providerId: providerId,
      onProgress: onProgress,
    );
    // Auto-rescan the same project after translate.
    final rescan = await runHeadlessValidationRescan(
      ref: ref,
      projectLanguageId: projectLanguageId,
    );
    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '$translated units translated · ${rescan.needsReviewTotal} flagged',
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

Future<ProjectOutcome> runBulkRescan({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final projectLang = _findLanguage(project, targetLanguageCode);
  if (projectLang == null) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'language not configured',
    );
  }
  if (projectLang.translatedUnits == 0) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'no translated units',
    );
  }
  try {
    onProgress?.call('Rescanning reviews', -1);
    final result = await runHeadlessValidationRescan(
      ref: ref,
      projectLanguageId: projectLang.projectLanguage.id,
    );
    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '${result.needsReviewTotal} flagged for review',
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

Future<ProjectOutcome> runBulkForceValidate({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final projectLang = _findLanguage(project, targetLanguageCode);
  if (projectLang == null) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'language not configured',
    );
  }
  if (projectLang.needsReviewUnits == 0) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'no review flags',
    );
  }
  try {
    onProgress?.call('Validating review flags', -1);
    final repo = ref.read(translationVersionRepositoryProvider);
    final ids = await repo.getNeedsReviewIds(
      projectLanguageId: projectLang.projectLanguage.id,
    );
    final unwrapped = ids.unwrap();
    final count = (await repo.acceptBatch(unwrapped)).unwrap();
    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '$count flags cleared',
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

Future<ProjectOutcome> runBulkGeneratePack({
  required Ref ref,
  required ProjectWithDetails project,
  required String targetLanguageCode,
  HandlerCallback? onProgress,
}) async {
  final projectLang = _findLanguage(project, targetLanguageCode);
  if (projectLang == null) {
    return const ProjectOutcome(
      status: ProjectResultStatus.skipped,
      message: 'language not configured',
    );
  }
  try {
    onProgress?.call('Generating pack', -1);
    final exporter = ref.read(exportOrchestratorServiceProvider);
    // `outputPath` is a dummy value here — the export service writes the
    // pack to the game data folder based on project metadata. This matches
    // BatchPackExportNotifier (see that file's call site for confirmation).
    final result = await exporter.exportToPack(
      projectId: project.project.id,
      languageCodes: [targetLanguageCode],
      outputPath: 'exports',
      validatedOnly: false,
      generatePackImage: true,
      onProgress: (step, progress, {currentLanguage, currentIndex, total}) =>
          onProgress?.call(step, progress),
    );
    if (result.isErr) {
      return ProjectOutcome(
        status: ProjectResultStatus.failed,
        message: result.unwrapErr().message,
        error: result.unwrapErr(),
      );
    }
    final ok = result.unwrap();
    return ProjectOutcome(
      status: ProjectResultStatus.succeeded,
      message: '${ok.entryCount} entries · ${ok.fileSize} bytes',
    );
  } catch (e) {
    return ProjectOutcome(
      status: ProjectResultStatus.failed,
      message: e.toString(),
      error: e,
    );
  }
}

```

Notes for executor:
- If `TranslationVersionRepository.getNeedsReviewIds` does not exist under that name, search for the equivalent query (it may be `getVersionsWithStatus('needsReview', projectLanguageId)` or similar). Add a method if truly missing — one-line SQL wrapping `SELECT id FROM translation_versions WHERE project_language_id=? AND status='needsReview'`.
- No `computePackOutputPath` helper is needed: `BatchPackExportNotifier` passes `outputPath: 'exports'` as a dummy and the export service writes to the game data folder based on project metadata.

- [ ] **Step 2: Run — expect FAIL on skip-case tests**

- [ ] **Step 3: Implement (above).**

- [ ] **Step 4: Run tests — expect PASS on all skip cases**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/services/bulk_operations_handlers.dart \
        test/features/projects/services/bulk_operations_handlers_test.dart
git commit -m "feat(projects): add bulk operations handlers"
```

---

### Task 7: `BulkOperationsNotifier`

**Files:**
- Create: `lib/features/projects/providers/bulk_operations_notifier.dart`
- Create: `test/features/projects/providers/bulk_operations_notifier_test.dart`

**Context:** The top-level orchestrator. Owns the state, iterates projects, dispatches handlers, respects cancellation. Exposes `run(...)`, `cancel()`, `reset()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/projects/providers/bulk_operations_notifier_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
// Import the handlers module to override each handler with a test double
// via the bulkHandlersProvider seam (added in implementation).

void main() {
  test('runs through all projects and reports succeeded', () async {
    // seed a test container with bulkHandlersProvider overridden to
    // return succeeded for every project
    // call run(...) and assert final state:
    //   - isComplete = true
    //   - countByStatus(succeeded) == 3
    //   - currentIndex == 3
  }, skip: 'Fill in after notifier shape is stable');

  test('cancel mid-run marks remaining projects cancelled', () async {
    // seed handlers that await a controllable completer, so the second
    // project is in-progress when cancel() is invoked; assert the
    // third project never runs and ends up with status cancelled
  }, skip: 'Fill in after notifier shape is stable');

  test('handler exception marks project failed, loop continues', () async {
    // middle handler throws; outer state still progresses to the last
    // project; final counts: 2 succeeded, 1 failed
  }, skip: 'Fill in after notifier shape is stable');
}
```

- [ ] **Step 2: Run — expect FAIL (compile error)**

- [ ] **Step 3: Implement the notifier**

```dart
// lib/features/projects/providers/bulk_operations_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/services/bulk_operations_handlers.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';

/// Seam for testing: in production this returns the real handlers;
/// in tests, override to inject doubles.
class BulkHandlers {
  const BulkHandlers();
  Future<ProjectOutcome> translate({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) => runBulkTranslate(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );
  Future<ProjectOutcome> rescan({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) => runBulkRescan(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );
  Future<ProjectOutcome> forceValidate({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) => runBulkForceValidate(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );
  Future<ProjectOutcome> generatePack({
    required Ref ref,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    HandlerCallback? onProgress,
  }) => runBulkGeneratePack(
        ref: ref,
        project: project,
        targetLanguageCode: targetLanguageCode,
        onProgress: onProgress,
      );
}

final bulkHandlersProvider = Provider<BulkHandlers>((_) => const BulkHandlers());

class BulkOperationsNotifier extends Notifier<BulkOperationState> {
  @override
  BulkOperationState build() => BulkOperationState.idle();

  Future<void> run({
    required BulkOperationType type,
    required String targetLanguageCode,
    required List<ProjectWithDetails> projects,
  }) async {
    if (state.operationType != null && !state.isComplete) {
      throw StateError('A bulk operation is already in progress');
    }

    final ids = projects.map((p) => p.project.id).toList();
    final results = <String, ProjectOutcome>{
      for (final id in ids)
        id: const ProjectOutcome(status: ProjectResultStatus.pending),
    };
    state = BulkOperationState(
      operationType: type,
      targetLanguageCode: targetLanguageCode,
      projectIds: ids,
      results: results,
    );

    final handlers = ref.read(bulkHandlersProvider);
    final projectById = {for (final p in projects) p.project.id: p};

    for (var i = 0; i < ids.length; i++) {
      if (state.isCancelled) {
        final updated = {...state.results};
        for (final remaining in ids.sublist(i)) {
          updated[remaining] = const ProjectOutcome(
            status: ProjectResultStatus.cancelled,
          );
        }
        state = state.copyWith(results: updated);
        break;
      }

      final project = projectById[ids[i]]!;
      state = state.copyWith(
        currentIndex: i,
        currentProjectId: project.project.id,
        currentProjectName: project.project.name,
        currentStep: 'Starting…',
        currentProjectProgress: -1,
        results: {
          ...state.results,
          project.project.id: const ProjectOutcome(
            status: ProjectResultStatus.inProgress,
          ),
        },
      );

      ProjectOutcome outcome;
      try {
        outcome = await _runOne(
          handlers: handlers,
          type: type,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: (step, progress) {
            state = state.copyWith(
              currentStep: step,
              currentProjectProgress: progress,
            );
          },
        );
      } catch (e) {
        outcome = ProjectOutcome(
          status: ProjectResultStatus.failed,
          message: e.toString(),
          error: e,
        );
      }

      state = state.copyWith(
        results: {...state.results, project.project.id: outcome},
      );

      // Invalidate project list so cards refresh their stats live.
      ref.invalidate(projectsWithDetailsProvider);
    }

    state = state.copyWith(
      isComplete: true,
      currentStep: null,
      currentProjectProgress: -1,
    );
  }

  Future<ProjectOutcome> _runOne({
    required BulkHandlers handlers,
    required BulkOperationType type,
    required ProjectWithDetails project,
    required String targetLanguageCode,
    required HandlerCallback onProgress,
  }) {
    switch (type) {
      case BulkOperationType.translate:
        return handlers.translate(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
      case BulkOperationType.rescan:
        return handlers.rescan(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
      case BulkOperationType.forceValidate:
        return handlers.forceValidate(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
      case BulkOperationType.generatePack:
        return handlers.generatePack(
          ref: ref,
          project: project,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
        );
    }
  }

  Future<void> cancel() async {
    if (state.operationType == null || state.isComplete) return;
    state = state.copyWith(isCancelled: true);

    // If currently running a translate, stop the in-flight batch.
    if (state.operationType == BulkOperationType.translate) {
      final runner = ref.read(headlessBatchTranslationRunnerProvider);
      await runner.stop();
    }
  }

  void reset() {
    state = BulkOperationState.idle();
  }
}

final bulkOperationsProvider =
    NotifierProvider<BulkOperationsNotifier, BulkOperationState>(
      BulkOperationsNotifier.new,
    );
```

- [ ] **Step 4: Flesh out the skipped tests with handler overrides and run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/providers/bulk_operations_notifier.dart \
        test/features/projects/providers/bulk_operations_notifier_test.dart
git commit -m "feat(projects): add BulkOperationsNotifier with cancel and auto-rescan"
```

---

## Phase 4 — UI: Bulk Menu Panel

### Task 8: `BulkInfoCard`

**Files:**
- Create: `lib/features/projects/widgets/bulk_info_card.dart`
- Create: `test/features/projects/widgets/bulk_info_card_test.dart`

**Context:** Muted warning-style card with info icon, 3-line message, dismiss chevron. Watches `bulkInfoCardDismissedProvider`. When dismissed, the card returns `SizedBox.shrink()` (the "Show info" reset affordance lives in the panel footer, Task 13).

- [ ] **Step 1: Write failing widget test**

```dart
// test/features/projects/widgets/bulk_info_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/widgets/bulk_info_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders message and dismiss button when not dismissed', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: BulkInfoCard())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('partially translated'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('hides card when pref is dismissed', (tester) async {
    SharedPreferences.setMockInitialValues({'projects_bulk_info_dismissed': true});
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: BulkInfoCard())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('partially translated'), findsNothing);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// lib/features/projects/widgets/bulk_info_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';
// Use the project's design tokens helper (same as ProjectsBulkMenuPanel).
// Adapt to the real token getter name if different.

class BulkInfoCard extends ConsumerWidget {
  const BulkInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(bulkInfoCardDismissedProvider).valueOrNull ?? false;
    if (dismissed) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Bulk actions are designed for projects already partially '
              'translated. The bulk of the work should be done project by '
              'project in the editor — bulk is here to finish up or harmonise.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            iconSize: 16,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: () =>
                ref.read(bulkInfoCardDismissedProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/widgets/bulk_info_card.dart \
        test/features/projects/widgets/bulk_info_card_test.dart
git commit -m "feat(projects): add dismissible bulk info card"
```

---

### Task 9: `BulkTargetLanguageSelector`

**Files:**
- Create: `lib/features/projects/widgets/bulk_target_language_selector.dart`
- Create: `test/features/projects/widgets/bulk_target_language_selector_test.dart`

**Context:** `DropdownMenu<String>` listing supported languages (use `allLanguagesProvider` from `projects_screen_providers.dart` or the shared language registry). Selecting a value calls `bulkTargetLanguageProvider.notifier.setLanguage(code)`.

- [ ] **Step 1: Write failing widget test** — verify the dropdown is present and selecting a value updates the provider.

```dart
// Simplified test stub
testWidgets('selecting a language updates provider', (tester) async {
  SharedPreferences.setMockInitialValues({});
  // pump with a ProviderScope override that provides a fake language list
  // tap the dropdown, select 'French', verify
  // container.read(bulkTargetLanguageProvider).value == 'fr'
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// lib/features/projects/widgets/bulk_target_language_selector.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
    // for allLanguagesProvider — adapt if located elsewhere

class BulkTargetLanguageSelector extends ConsumerWidget {
  const BulkTargetLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languagesAsync = ref.watch(allLanguagesProvider);
    final current = ref.watch(bulkTargetLanguageProvider).valueOrNull;

    return languagesAsync.when(
      data: (languages) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: DropdownMenu<String>(
          width: 296,
          label: const Text('Target language'),
          initialSelection: current,
          dropdownMenuEntries: [
            for (final l in languages)
              DropdownMenuEntry<String>(value: l.code, label: l.displayName),
          ],
          onSelected: (code) => ref
              .read(bulkTargetLanguageProvider.notifier)
              .setLanguage(code),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Failed to load languages: $e'),
      ),
    );
  }
}
```

Field names on `Language` (`code`, `displayName`) must match the real model — verify against `lib/models/domain/language.dart` and adjust.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/widgets/bulk_target_language_selector.dart \
        test/features/projects/widgets/bulk_target_language_selector_test.dart
git commit -m "feat(projects): add bulk target language selector"
```

---

### Task 10: `visibleProjectsForBulkProvider` + `BulkScopeIndicator`

**Files:**
- Create: `lib/features/projects/providers/visible_projects_for_bulk_provider.dart`
- Create: `lib/features/projects/widgets/bulk_scope_indicator.dart`
- Create: `test/features/projects/providers/visible_projects_for_bulk_provider_test.dart`

**Context:** Derived provider returning `({List<ProjectWithDetails> visible, List<ProjectWithDetails> matching})` — `visible` is the current filtered/paginated list, `matching` is the subset that has the target language configured. `BulkScopeIndicator` displays `"Will affect X visible projects (Y match target language)."`

- [ ] **Step 1: Write failing test**

```dart
// test/features/projects/providers/visible_projects_for_bulk_provider_test.dart
// Override paginatedProjectsProvider with a fixed list.
// Set bulkTargetLanguageProvider to 'fr'.
// Expect: visible count == fixed list length,
//         matching count == number of those with a 'fr' language.
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// lib/features/projects/providers/visible_projects_for_bulk_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';

typedef BulkScope = ({
  List<ProjectWithDetails> visible,
  List<ProjectWithDetails> matching,
});

final visibleProjectsForBulkProvider = Provider<AsyncValue<BulkScope>>((ref) {
  final visibleAsync = ref.watch(paginatedProjectsProvider);
  final targetCode = ref.watch(bulkTargetLanguageProvider).valueOrNull;

  return visibleAsync.when(
    data: (visible) {
      final matching = targetCode == null
          ? <ProjectWithDetails>[]
          : visible.where((p) => p.languages.any(
              (l) => l.language?.code == targetCode,
            )).toList();
      return AsyncValue.data((visible: visible, matching: matching));
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});
```

```dart
// lib/features/projects/widgets/bulk_scope_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';

class BulkScopeIndicator extends ConsumerWidget {
  const BulkScopeIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeAsync = ref.watch(visibleProjectsForBulkProvider);
    return scopeAsync.when(
      data: (scope) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Will affect ${scope.visible.length} visible projects '
          '(${scope.matching.length} match target language).',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/providers/visible_projects_for_bulk_provider.dart \
        lib/features/projects/widgets/bulk_scope_indicator.dart \
        test/features/projects/providers/visible_projects_for_bulk_provider_test.dart
git commit -m "feat(projects): add bulk scope provider and indicator"
```

---

### Task 11: `BulkActionButtons` (includes force-validate confirm dialog)

**Files:**
- Create: `lib/features/projects/widgets/bulk_action_buttons.dart`
- Create: `test/features/projects/widgets/bulk_action_buttons_test.dart`

**Context:** Four full-width `FilledButton`s, disabled when (a) no target language, (b) op already running, or (c) zero matching projects. The force-validate button first opens an `AlertDialog` confirmation; on confirm it opens the progress dialog (added in Task 14) and calls `bulkOperationsProvider.notifier.run(...)`.

- [ ] **Step 1: Write failing widget test**

```dart
// test/features/projects/widgets/bulk_action_buttons_test.dart
testWidgets('all four buttons disabled when no target language', (tester) async {
  // pump with ProviderScope default (no language selected)
  // expect the four buttons to be present but disabled (onPressed == null)
});

testWidgets('buttons enabled when target language selected and projects match', (tester) async {
  // override bulkTargetLanguageProvider to 'fr'
  // override visibleProjectsForBulkProvider with non-empty matching list
  // verify buttons enabled
});

testWidgets('force validate shows confirm dialog before running', (tester) async {
  // tap the force-validate button
  // expect AlertDialog with "cannot be undone" in text
  // tap Cancel → dialog closes, bulkOperationsProvider.state unchanged
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// lib/features/projects/widgets/bulk_action_buttons.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';

class BulkActionButtons extends ConsumerWidget {
  const BulkActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetLang = ref.watch(bulkTargetLanguageProvider).valueOrNull;
    final bulkState = ref.watch(bulkOperationsProvider);
    final scopeAsync = ref.watch(visibleProjectsForBulkProvider);
    final scope = scopeAsync.valueOrNull;

    final isRunning =
        bulkState.operationType != null && !bulkState.isComplete;
    final hasMatching = (scope?.matching.isNotEmpty ?? false);
    final canAct = targetLang != null && !isRunning && hasMatching;

    String? disabledTooltip;
    if (targetLang == null) disabledTooltip = 'Select a target language';
    else if (isRunning) disabledTooltip = 'An operation is already running';
    else if (!hasMatching) disabledTooltip = 'No visible projects match';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BulkButton(
            icon: Icons.translate,
            label: 'Translate all',
            enabled: canAct,
            tooltip: disabledTooltip,
            onPressed: () => _start(context, ref, BulkOperationType.translate),
          ),
          const SizedBox(height: 8),
          _BulkButton(
            icon: Icons.refresh,
            label: 'Rescan reviews',
            enabled: canAct,
            tooltip: disabledTooltip,
            onPressed: () => _start(context, ref, BulkOperationType.rescan),
          ),
          const SizedBox(height: 8),
          _BulkButton(
            icon: Icons.verified,
            label: 'Force validate reviews',
            enabled: canAct,
            tooltip: disabledTooltip,
            danger: true,
            onPressed: () => _confirmThenStart(context, ref),
          ),
          const SizedBox(height: 8),
          _BulkButton(
            icon: Icons.inventory_2,
            label: 'Generate pack',
            enabled: canAct,
            tooltip: disabledTooltip,
            onPressed: () =>
                _start(context, ref, BulkOperationType.generatePack),
          ),
        ],
      ),
    );
  }

  void _start(BuildContext context, WidgetRef ref, BulkOperationType type) {
    final targetLang = ref.read(bulkTargetLanguageProvider).valueOrNull!;
    final matching = ref.read(visibleProjectsForBulkProvider).valueOrNull!.matching;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const BulkOperationProgressDialog(),
    );
    ref.read(bulkOperationsProvider.notifier).run(
      type: type,
      targetLanguageCode: targetLang,
      projects: matching,
    );
  }

  Future<void> _confirmThenStart(BuildContext context, WidgetRef ref) async {
    final matching = ref.read(visibleProjectsForBulkProvider).valueOrNull!.matching;
    final targetLang = ref.read(bulkTargetLanguageProvider).valueOrNull!;

    // Cheap count: sum needsReviewUnits for target language across matching projects.
    var units = 0;
    for (final p in matching) {
      final l = p.languages.firstWhere(
        (l) => l.language?.code == targetLang,
        orElse: () => throw StateError('unreachable'),
      );
      units += l.needsReviewUnits;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force validate reviews?'),
        content: Text(
          'This will mark $units units across ${matching.length} projects '
          'as validated for $targetLang, clearing all review flags. '
          'This cannot be undone from here. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Force validate'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      _start(context, ref, BulkOperationType.forceValidate);
    }
  }
}

class _BulkButton extends StatelessWidget {
  const _BulkButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      label: Text(label),
      style: danger
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
    );
    if (!enabled && tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/widgets/bulk_action_buttons.dart \
        test/features/projects/widgets/bulk_action_buttons_test.dart
git commit -m "feat(projects): add bulk action buttons with force-validate confirm"
```

---

### Task 12: Rewire `ProjectsBulkMenuPanel` — assemble the 5 sections

**Files:**
- Modify: `lib/features/projects/widgets/projects_bulk_menu_panel.dart`

**Context:** Replace the empty container with a `Column` holding the five sections. Keep the width/border chrome intact.

- [ ] **Step 1: Rewrite the widget**

```dart
// lib/features/projects/widgets/projects_bulk_menu_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_action_buttons.dart';
import 'package:twmt/features/projects/widgets/bulk_info_card.dart';
import 'package:twmt/features/projects/widgets/bulk_scope_indicator.dart';
import 'package:twmt/features/projects/widgets/bulk_target_language_selector.dart';
import 'package:twmt/features/translation_editor/widgets/editor_toolbar_batch_settings.dart';
import 'package:twmt/features/translation_editor/widgets/editor_toolbar_model_selector.dart';
import 'package:twmt/features/translation_editor/widgets/editor_toolbar_skip_tm.dart';
// Import the tokens helper the existing panel uses.

class ProjectsBulkMenuPanel extends ConsumerWidget {
  const ProjectsBulkMenuPanel({super.key});

  static const double width = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoDismissed =
        ref.watch(bulkInfoCardDismissedProvider).valueOrNull ?? false;
    final tokens = context.tokens; // match existing helper

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BulkInfoCard(),
            const BulkTargetLanguageSelector(),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: EditorToolbarModelSelector(compact: true),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: EditorToolbarSkipTm(compact: true),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: EditorToolbarBatchSettings(),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const BulkActionButtons(),
            const BulkScopeIndicator(),
            if (infoDismissed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(bulkInfoCardDismissedProvider.notifier).reset(),
                  icon: const Icon(Icons.info_outline, size: 14),
                  label: const Text('Show info'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run Flutter analyzer**

```bash
flutter analyze
```

Expect: no new warnings. Fix any unresolved imports (e.g. real path of `tokens`).

- [ ] **Step 3: Manual smoke test — launch app**

```bash
flutter run -d windows
```

Open Projects screen → toggle bulk menu. Verify:
- Info card appears at top.
- Target language dropdown populated.
- Settings widgets render (same as editor toolbar).
- Four buttons present, all disabled (no target language yet).
- Scope indicator visible at bottom with "0 match target language" text.

- [ ] **Step 4: Commit**

```bash
git add lib/features/projects/widgets/projects_bulk_menu_panel.dart
git commit -m "feat(projects): wire bulk menu panel with 5 sections"
```

---

## Phase 5 — Progress Modal

### Task 13: `BulkOperationProgressDialog`

**Files:**
- Create: `lib/features/projects/widgets/bulk_operation_progress_dialog.dart`
- Create: `test/features/projects/widgets/bulk_operation_progress_dialog_test.dart`

**Context:** Modal watching `bulkOperationsProvider`. Three states (running / cancelling / complete) drive the footer. On Close, resets the notifier and pops.

- [ ] **Step 1: Write failing widget test**

```dart
// test/features/projects/widgets/bulk_operation_progress_dialog_test.dart
testWidgets('shows Cancel button while running', (tester) async {
  // seed notifier state: operationType set, isComplete false
  // pump a MaterialApp that opens the dialog
  // expect finder for "Cancel" button
});

testWidgets('shows Close + summary when isComplete', (tester) async {
  // seed with results: 2 succeeded, 1 failed; isComplete: true
  // expect: text "2 succeeded", "1 failed", Close button
  // expect Retry failed button visible
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// lib/features/projects/widgets/bulk_operation_progress_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';

class BulkOperationProgressDialog extends ConsumerWidget {
  const BulkOperationProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bulkOperationsProvider);
    final title = _titleFor(s.operationType);
    final subtitle = 'Target language: ${s.targetLanguageCode ?? '—'}';

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          Text(subtitle, style: const TextStyle(fontSize: 12)),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: s.projectIds.isEmpty ? 0 : s.currentIndex / s.projectIds.length,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${s.currentIndex}/${s.projectIds.length} projects'),
              ),
            ),
            const SizedBox(height: 12),
            if (!s.isComplete) _CurrentProjectBlock(state: s),
            const SizedBox(height: 12),
            Expanded(child: _TimelineList(state: s)),
          ],
        ),
      ),
      actions: _footerActions(context, ref, s),
    );
  }

  String _titleFor(BulkOperationType? type) {
    switch (type) {
      case BulkOperationType.translate: return 'Translating projects';
      case BulkOperationType.rescan: return 'Rescanning reviews';
      case BulkOperationType.forceValidate: return 'Force-validating reviews';
      case BulkOperationType.generatePack: return 'Generating packs';
      case null: return 'Bulk operation';
    }
  }

  List<Widget> _footerActions(BuildContext context, WidgetRef ref, BulkOperationState s) {
    if (s.isComplete) {
      final failed = s.countByStatus(ProjectResultStatus.failed);
      return [
        Expanded(
          child: Text(
            '${s.countByStatus(ProjectResultStatus.succeeded)} succeeded · '
            '${s.countByStatus(ProjectResultStatus.skipped)} skipped · '
            '$failed failed',
          ),
        ),
        if (failed > 0)
          TextButton(
            onPressed: () => _retryFailed(context, ref, s),
            child: const Text('Retry failed'),
          ),
        FilledButton(
          onPressed: () {
            ref.read(bulkOperationsProvider.notifier).reset();
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ];
    }
    if (s.isCancelled) {
      return [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Cancelling…'),
          ]),
        ),
      ];
    }
    return [
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => _confirmCancel(context, ref),
        child: const Text('Cancel'),
      ),
    ];
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the current operation?'),
        content: const Text('Projects already processed will keep their changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep running')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(bulkOperationsProvider.notifier).cancel();
    }
  }

  void _retryFailed(BuildContext context, WidgetRef ref, BulkOperationState s) {
    final scope = ref.read(visibleProjectsForBulkProvider).valueOrNull;
    if (scope == null) return;
    final failedIds = s.failedProjectIds.toSet();
    final failedProjects =
        scope.matching.where((p) => failedIds.contains(p.project.id)).toList();
    ref.read(bulkOperationsProvider.notifier).reset();
    ref.read(bulkOperationsProvider.notifier).run(
      type: s.operationType!,
      targetLanguageCode: s.targetLanguageCode!,
      projects: failedProjects,
    );
  }
}

class _CurrentProjectBlock extends StatelessWidget {
  const _CurrentProjectBlock({required this.state});
  final BulkOperationState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.currentProjectName ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(state.currentStep ?? ''),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: state.currentProjectProgress < 0
              ? null
              : state.currentProjectProgress,
        ),
      ],
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.state});
  final BulkOperationState state;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: state.projectIds.length,
      itemBuilder: (ctx, i) {
        final id = state.projectIds[i];
        final outcome = state.results[id];
        return ListTile(
          dense: true,
          leading: _statusIcon(outcome?.status ?? ProjectResultStatus.pending),
          title: Text(id), // swap to project name if we snapshot it
          trailing: outcome?.message != null
              ? Text(outcome!.message!, style: const TextStyle(fontSize: 11))
              : null,
          enabled: state.isComplete,
        );
      },
    );
  }

  Widget _statusIcon(ProjectResultStatus s) {
    switch (s) {
      case ProjectResultStatus.pending: return const Icon(Icons.circle_outlined, size: 16);
      case ProjectResultStatus.inProgress:
        return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
      case ProjectResultStatus.succeeded: return const Icon(Icons.check, color: Colors.green, size: 16);
      case ProjectResultStatus.skipped: return const Icon(Icons.remove, size: 16);
      case ProjectResultStatus.failed: return const Icon(Icons.close, color: Colors.red, size: 16);
      case ProjectResultStatus.cancelled: return const Icon(Icons.stop, size: 16);
    }
  }
}
```

Note: the timeline's `ListTile.title` should show project names rather than IDs. Add `currentProjectNames` (a `Map<String, String>`) to `BulkOperationState` seeded from the snapshot, or pass the `visible_projects_for_bulk_provider` scope down. (If adding to state: update Task 3's state class + its copyWith.)

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/widgets/bulk_operation_progress_dialog.dart \
        test/features/projects/widgets/bulk_operation_progress_dialog_test.dart
git commit -m "feat(projects): add bulk operation progress dialog"
```

---

## Phase 6 — Integration & Validation

### Task 14: Names in timeline + state polish

**Files:**
- Modify: `lib/features/projects/providers/bulk_operation_state.dart`
- Modify: `lib/features/projects/providers/bulk_operations_notifier.dart`
- Modify: `lib/features/projects/widgets/bulk_operation_progress_dialog.dart`
- Modify: `test/features/projects/providers/bulk_operation_state_test.dart`

**Context:** Add `Map<String, String> projectNames` to state so the timeline shows names instead of IDs. Seed it in `run(...)` from the snapshot.

- [ ] **Step 1: Extend `BulkOperationState` with `projectNames`, updating `copyWith` and `idle()`.**
- [ ] **Step 2: Update `BulkOperationsNotifier.run()` to seed `projectNames = { for (final p in projects) p.project.id: p.project.name }`.**
- [ ] **Step 3: Update the timeline widget to use `state.projectNames[id] ?? id`.**
- [ ] **Step 4: Update / extend tests; run — expect PASS.**
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(projects): show project names in bulk timeline"
```

---

### Task 15: Manual end-to-end validation in `flutter run`

**Files:** none

**Context:** Verify the full flow against a real DB and UI. This is not a code change; it's the gate before shipping.

- [ ] **Step 1: Run `flutter run -d windows`.**

- [ ] **Step 2: Open the Projects screen, show the bulk menu panel.**

- [ ] **Step 3: Walk through each scenario and check behaviour:**
    - Info card visible at top; dismiss → disappears; "Show info" → reappears.
    - Select target language → dropdown persists value across panel re-open.
    - Settings widgets reflect editor state; changes here also affect the editor.
    - Scope indicator updates as filters change.
    - Action buttons enabled only when target language + matching projects present.
    - Click Translate all → modal opens, progress advances, timeline fills, summary shows.
    - Click Cancel mid-translate → confirm dialog → Stop → current batch is stopped, remaining projects marked cancelled, summary shows.
    - Click Rescan reviews → scope limited to projects with translated units, counts refresh on cards.
    - Click Force validate → confirm dialog shows accurate count → proceed → review flags cleared, cards update.
    - Click Generate pack → packs written to expected locations.
    - Retry failed after a failure → only failed projects are rerun.
    - Close → reset; reopen on a fresh operation → state is clean.

- [ ] **Step 4: File any follow-up bugs found as separate TODOs in the repo issue tracker (not in this plan).**

- [ ] **Step 5: Commit nothing (validation step only).**

---

## Appendix — Files Touched

### Created — 13 source files

```
lib/features/projects/providers/bulk_target_language_provider.dart
lib/features/projects/providers/bulk_info_card_dismissed_provider.dart
lib/features/projects/providers/bulk_operation_state.dart
lib/features/projects/providers/bulk_operations_notifier.dart
lib/features/projects/providers/visible_projects_for_bulk_provider.dart
lib/features/projects/services/bulk_operations_handlers.dart
lib/features/projects/widgets/bulk_info_card.dart
lib/features/projects/widgets/bulk_target_language_selector.dart
lib/features/projects/widgets/bulk_scope_indicator.dart
lib/features/projects/widgets/bulk_action_buttons.dart
lib/features/projects/widgets/bulk_operation_progress_dialog.dart
lib/services/translation/headless_validation_rescan_service.dart
lib/services/translation/headless_batch_translation_runner.dart
```

### Created — 12 test files

```
test/features/projects/providers/bulk_target_language_provider_test.dart
test/features/projects/providers/bulk_info_card_dismissed_provider_test.dart
test/features/projects/providers/bulk_operation_state_test.dart
test/features/projects/providers/bulk_operations_notifier_test.dart
test/features/projects/providers/visible_projects_for_bulk_provider_test.dart
test/features/projects/services/bulk_operations_handlers_test.dart
test/features/projects/widgets/bulk_info_card_test.dart
test/features/projects/widgets/bulk_target_language_selector_test.dart
test/features/projects/widgets/bulk_action_buttons_test.dart
test/features/projects/widgets/bulk_operation_progress_dialog_test.dart
test/services/translation/headless_validation_rescan_service_test.dart
test/services/translation/headless_batch_translation_runner_test.dart
```

### Modified — 1

```
lib/features/projects/widgets/projects_bulk_menu_panel.dart
```

### Not touched

```
lib/features/translation_editor/widgets/editor_toolbar_model_selector.dart
lib/features/translation_editor/widgets/editor_toolbar_skip_tm.dart
lib/features/translation_editor/widgets/editor_toolbar_batch_settings.dart
lib/features/translation_editor/screens/actions/editor_actions_validation.dart  # rescan logic extracted/ported, original method unchanged
lib/features/translation_editor/screens/actions/editor_actions_translation.dart
lib/services/translation/translation_orchestrator_impl.dart
```
