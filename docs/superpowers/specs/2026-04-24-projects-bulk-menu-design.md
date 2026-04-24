# Projects Screen — Bulk Menu Design

**Date:** 2026-04-24
**Status:** Approved (pending implementation plan)
**Area:** `lib/features/projects/` (Flutter desktop)

## 1. Context and Goal

The Projects screen already has a "Show bulk menu" toggle that opens an empty
320 px right-side panel. The panel must be populated with actions that operate
on **the projects currently visible through the existing filters** of the
screen (search, game, language, quick filter, sort).

The bulk menu is explicitly a complement to — not a replacement for — per-
project work in the translation editor. The bulk actions are meant to finish
off already partially translated projects, run maintenance passes, or batch
generate packs. Heavy translation work is expected to continue happening one
project at a time in the editor.

## 2. Scope

The bulk menu panel will provide:

- An informative header card explaining the intended use.
- A target-language selector (applies to all bulk actions).
- Shared translation settings (LLM model, Use TM, batch size + parallel
  batches), reusing the widgets already present in the editor toolbar and
  bound to the same providers.
- Four actions:
    1. **Translate all** — translates only units not yet translated, for the
       target language, across all visible projects. Auto-chains a rescan on
       each project after translation.
    2. **Rescan reviews** — runs validation rescan on all visible projects +
       target language and refreshes `needsReviewUnits` counts.
    3. **Force validate reviews** — destructive action that, after a
       confirmation dialog, clears all `needsReview` flags for the target
       language across visible projects.
    4. **Generate pack** — generates one `.pack` per visible project for the
       target language.
- A progress modal dialog shown during any bulk operation, with per-project
  status, cancel button, and a final summary with retry-on-failure.

Out of scope: multi-language bulk operations in a single run; parallel-
project execution; reorganising how filters work; exposing bulk state in any
screen other than the Projects screen.

## 3. Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Target language is a **dedicated selector in the bulk panel** (not reused from the filter bar). | Clear separation between "which projects are visible" and "what the bulk actions target". Matches the single-language contract of `BatchPackExportNotifier`. |
| D2 | Bulk settings (LLM model, Use TM, batch size, parallel batches) **share providers with the editor**. | Single source of truth for these values; in practice users tune them once. Isolating would just create two places to configure the same thing. |
| D3 | Progress UI is a **modal dialog** over the Projects screen, not an in-panel dashboard. | User asked for a modal explicitly; it centralises progress, cancel, and the final summary in one predictable place. |
| D4 | "Review" encompasses **three flows**: (a) auto-rescan after a Translate all, (b) a standalone Rescan button, (c) a Force validate button with confirmation that wipes `needsReview` flags. | All three are useful and composable; the user asked for the force-validate flow explicitly. |
| D5 | Orchestration uses **one unified `BulkOperationsNotifier` with a `BulkOperationType` enum**, not one notifier per action. | All four operations share the same outer loop (iterate visible projects, track per-project progress, handle cancel). A single notifier keeps the pattern in one place. |
| D6 | Project execution is **sequential**, not parallel. | LLM rate-limit safety, simpler cancellation, clearer progress UX. Each project already has internal parallelism via `parallelBatches`. |
| D7 | Cancellation is **guaranteed between projects, best-effort within a project**. | Matches the existing `BatchPackExportNotifier.isCancelled` pattern; the batch translate service already has a `cancel()` we can call on the current batch. |
| D8 | Bulk info card is **dismissible and persisted** (SharedPrefs), with a small "Show info" affordance to bring it back. | Lets repeat users reclaim the vertical space; preserves the guidance for new users. |

## 4. UI — Bulk Menu Panel

The existing `ProjectsBulkMenuPanel` widget (320 px, left border, already
mounted in the Projects screen row) is rewritten as a scrollable `Column`
with five sections, from top to bottom:

### 4.1 Info card (sticky header, not scrolled)

- Muted warning background (`tokens.warning` attenuated), info icon.
- ~3 lines, wording:
    > Bulk actions are designed for projects **already partially translated**.
    > The bulk of the work should be done project by project in the editor —
    > bulk is here to finish up or harmonise.
- Trailing chevron/X to dismiss. Dismissal persisted under SharedPrefs key
  `projects_bulk_info_dismissed`. When dismissed, a small discreet "Show
  info" button in the panel footer brings it back.

### 4.2 Target language selector

- `DropdownMenu<String>` labelled "Target language".
- Options sourced from the same language registry used by the screen's
  existing `languageFilters` dropdown.
- State held by `bulkTargetLanguageProvider` (persisted SharedPrefs key
  `projects_bulk_target_lang`).
- While `null`: all action buttons are disabled with tooltip "Select a
  target language".

### 4.3 Settings section (widgets reused as-is)

- `EditorToolbarModelSelector(compact: true)` — LLM model.
- `EditorToolbarSkipTm(compact: true)` — Use TM toggle (inverted display,
  warns when TM is skipped).
- `EditorToolbarBatchSettings(compact: true)` — auto toggle, units per
  batch, parallel batches.

These three widgets already read and write the shared providers
(`selectedLlmModelProvider`, `translationSettingsProvider`). No new
providers needed.

### 4.4 Actions section — four `FilledButton`s, full width

| Button | Icon | Style | Behaviour |
|--------|------|-------|-----------|
| Translate all | `Icons.translate` | Primary | Iterates visible projects with target language, translates units where `status != translated`. Auto-chains a rescan per project. |
| Rescan reviews | `Icons.refresh` | Secondary | Runs validation rescan for target language on every visible project, updates `needsReviewUnits` in DB. |
| Force validate reviews | `Icons.verified` | Danger (`tokens.danger`) | Opens a confirm dialog first (section 5.3). On confirm, clears `needsReview` flags for target language across visible projects. |
| Generate pack | `Icons.inventory_2` | Primary | Generates one `.pack` per visible project for the target language; output goes to the game data folder (existing export service behaviour). |

Each button is disabled when any of:
- `bulkTargetLanguageProvider == null`
- `bulkOperationsProvider.state.operationType != null` (another op running)
- 0 visible projects match the target language

Tooltips explain the disabled reason.

### 4.5 Scope indicator (footer)

Discreet text under the buttons: `"Will affect 12 visible projects
(3 match target language)."` Watches `paginatedProjectsProvider` + the
target language to update live. Gives the user an immediate sense of blast
radius before clicking an action.

## 5. Orchestration — `BulkOperationsNotifier`

### 5.1 State shape

```dart
enum BulkOperationType { translate, rescan, forceValidate, generatePack }

enum ProjectResultStatus {
  pending, inProgress, succeeded, skipped, failed, cancelled
}

class ProjectOutcome {
  final ProjectResultStatus status;
  final String? message;    // "42 units translated", "language not configured", …
  final Object? error;      // non-null when failed
}

class BulkOperationState {
  final BulkOperationType? operationType;       // null = idle
  final String? targetLanguageCode;
  final List<String> projectIds;                 // snapshot, ordered
  final int currentIndex;
  final String? currentProjectId;
  final String? currentProjectName;
  final String? currentStep;
  final double currentProjectProgress;           // 0..1, -1 = indeterminate
  final Map<String, ProjectOutcome> results;
  final bool isCancelled;
  final bool isComplete;
}
```

### 5.2 Lifecycle — `BulkOperationsNotifier.run(type, targetLanguageCode)`

1. Guard: if `state.operationType != null && !state.isComplete` → throw
   `StateError('A bulk operation is already in progress')`.
2. Seed the state (`operationType`, `targetLanguageCode`, snapshot of
   `paginatedProjectsProvider` filtered by target language, all outcomes =
   `pending`).
3. For each `projectId` in `projectIds`, in order:
    - If `state.isCancelled` → mark remaining as `cancelled`, break.
    - Mark the current project `inProgress`, publish `currentStep`.
    - Dispatch to the type's handler (section 5.3).
    - On success → mark `succeeded` with a summary message and the relevant
      counts.
    - On `SkipReason` → mark `skipped` with the reason.
    - On any other exception → mark `failed(error)` and continue.
    - After each project, invalidate `projectsWithDetailsProvider` so the
      list below the modal reflects fresh counts live.
4. After the loop: `isComplete = true`. Keep `operationType` populated so
   the modal keeps showing the summary until the user closes it.

### 5.3 Handlers (`bulk_operations_handlers.dart` — pure functions, mockable)

All handlers are scoped to `(Project project, String targetLanguageCode)`
and return a `ProjectOutcome`.

| Handler | Action | Skip condition | Post-action |
|---------|--------|----------------|-------------|
| `translate` | Get untranslated unit IDs via `TranslationBatchHelper.getUntranslatedUnitIds()`, create and start a batch via the existing batch service, await completion. | Project has no target language configured, or 0 untranslated units. | Calls `rescan` handler on the same project before returning (auto-rescan). |
| `rescan` | Calls the validation rescan service (the one used behind `handleValidate()`), scoped to project + target language. | 0 translated units. | Updates `needsReviewUnits` in DB. |
| `forceValidate` | Batch `UPDATE translation_versions SET status='translated' WHERE project_id=? AND language_id=? AND status='needsReview'`. | 0 `needsReview` units. | Updates counts via the same invalidation. |
| `generatePack` | Calls `exportOrchestratorServiceProvider.exportToPack(projectId, languageCodes: [targetLanguageCode])` directly (not via `BatchPackExportNotifier`, which owns its own state machine). | Project has no exportable assets for the target language. | Pack written to game data folder. |

**Awaiting the translate batch.** The current batch service is fire-and-
forget from the editor's point of view. The implementation plan will pick
one of:

- (A) Extend the batch service with a `Future<void>` that resolves on
  completion (preferred if it's a small refactor).
- (B) Poll the batch state until `isComplete` (fallback).

### 5.4 Cancellation

`BulkOperationsNotifier.cancel()`:

1. Set `isCancelled = true`.
2. If the current handler is `translate`: call `cancel()` on the in-flight
   batch.
3. If the current handler is `rescan` / `forceValidate` / `generatePack`:
   let the current project finish (these operations are short), then break
   out of the outer loop.
4. Remaining projects get marked `cancelled` by the outer loop.

### 5.5 New providers

- `bulkOperationsProvider` — `NotifierProvider<BulkOperationsNotifier,
  BulkOperationState>`, not autoDispose.
- `bulkTargetLanguageProvider` — `NotifierProvider<BulkTargetLanguageNotifier,
  String?>`, persisted SharedPrefs.
- `bulkInfoCardDismissedProvider` — `NotifierProvider<BulkInfoCardDismissedNotifier,
  bool>`, persisted SharedPrefs.
- `visibleProjectsForBulkProvider` — derived `Provider<List<ProjectWithDetails>>`
  combining `paginatedProjectsProvider` with `bulkTargetLanguageProvider`.

## 6. UI — Progress Modal (`BulkOperationProgressDialog`)

Opened via `showDialog(barrierDismissible: false, …)` immediately before
calling `bulkOperationsProvider.notifier.run(...)`. Watches
`bulkOperationsProvider` and rebuilds on every state change.

### 6.1 Layout (~540 × ~460 px, scrollable body)

1. **Header** — dynamic title by `operationType` ("Translating 12 projects",
   "Rescanning reviews", "Force-validating reviews", "Generating packs").
   Subtitle: `"Target language: French"`. The top-right close (X) is
   disabled while the operation is running — user must go through the
   Cancel button.
2. **Global progress bar** — `LinearProgressIndicator(value =
   currentIndex / projectIds.length)` + text `"3/12 projects"`.
3. **Current project block** (shown only while `!isComplete`):
    - Project name in bold.
    - `currentStep` text.
    - `LinearProgressIndicator(value = currentProjectProgress)` (or
      indeterminate when `-1`).
4. **Timeline list** — scrollable, one row per project in the snapshot:
    - Status icon: spinner (`inProgress`), check (`succeeded`), dash
      (`skipped`), cross (`failed`), stop icon (`cancelled`), hollow dot
      (`pending`).
    - Project name (left).
    - Short message (right), e.g. `"42 units translated"`, `"no
      untranslated units"`, `"language not configured"`, `"3 flagged for
      review"`, `"error: quota exceeded"`.
    - Clicking a row (only when `isComplete == true`) navigates to the
      project — especially useful for inspecting a `failed` row. Rows are
      non-interactive during the run.
5. **Footer** — conditional by state:
    - **Running** (`!isComplete && !isCancelled`): a single `Cancel` button
      (outlined, `tokens.danger`) that opens a confirm dialog *"Stop the
      current operation? Projects already processed will keep their
      changes."* before calling `cancel()`.
    - **Cancelling** (`isCancelled && !isComplete`): disabled button
      labelled `"Cancelling…"` with a spinner.
    - **Complete** (`isComplete`):
        - Summary on the left: `"12 succeeded · 2 skipped · 1 failed"`
          with coloured counts.
        - `Retry failed` button (visible when `failed > 0`) — reruns the
          same operation type on the `failed` sublist only.
        - `Close` button (primary) — closes the dialog AND calls
          `bulkOperationsProvider.notifier.reset()` to return state to
          idle.

### 6.2 Force validate confirmation

Before the progress modal opens for `forceValidate`, an `AlertDialog`
confirmation is shown. It counts impacted units live via a DB query
`SELECT COUNT(*) FROM translation_versions WHERE status='needsReview' AND
project_id IN (…) AND language_id=?`. Body:

> This will mark **X units** across **Y projects** as validated for
> French, clearing all review flags. This cannot be undone from here.
> Continue?

Only on confirmation do we open the progress modal and call `run(...)`.

### 6.3 Live sync with the project list

While the modal is open, invalidating `projectsWithDetailsProvider` after
each project ensures the cards behind the modal update their badges
(translated progress, needs-review count) live. When the user closes the
modal, they already see the up-to-date state.

## 7. File Organisation

### 7.1 New files

```
lib/features/projects/
├─ providers/
│  ├─ bulk_operations_notifier.dart
│  ├─ bulk_target_language_provider.dart
│  ├─ bulk_info_card_dismissed_provider.dart
│  └─ visible_projects_for_bulk_provider.dart
├─ widgets/
│  ├─ bulk_info_card.dart
│  ├─ bulk_target_language_selector.dart
│  ├─ bulk_scope_indicator.dart
│  ├─ bulk_action_buttons.dart
│  └─ bulk_operation_progress_dialog.dart
└─ services/
   └─ bulk_operations_handlers.dart
```

### 7.2 Modified files

- `lib/features/projects/widgets/projects_bulk_menu_panel.dart` — empty
  container replaced by the five-section `Column`.
- Possibly the batch translate service, if an awaitable `Future<void>`
  completion is needed (decision deferred to the implementation plan).

### 7.3 Untouched

- `lib/features/translation_editor/widgets/editor_toolbar_*.dart` —
  imported as-is. No changes.
- `BatchPackExportNotifier` — unchanged. Bulk pack generation calls the
  underlying `exportOrchestratorServiceProvider` directly rather than
  going through this notifier (its state machine would be redundant with
  ours).

## 8. Testing Strategy

Pragmatic, aligned with the project's existing test conventions.

### 8.1 Unit tests — `BulkOperationsNotifier` with mocked handlers

- Happy path: 3 projects, all succeed; final state has `isComplete = true`,
  index = 3, all outcomes `succeeded`.
- Cancel mid-run: cancel after project 2 → remaining projects `cancelled`,
  handler never called for them.
- Failing handler: throw on project 2 → outcome = `failed`, loop continues,
  project 3 runs normally.
- Auto-rescan after translate: rescan handler is called once per project
  after the translate handler.

### 8.2 Unit tests — each handler in `bulk_operations_handlers.dart`

One test file per handler, covering:
- Nominal case (succeeds, returns expected message and counts).
- Skip case (empty input).
- Error propagation from underlying service.

### 8.3 Widget tests — light

- `BulkActionButtons`: buttons disabled when `bulkTargetLanguageProvider`
  is `null`; enabled when it has a value and at least one project matches.
- `BulkOperationProgressDialog`: correct footer content for each of the
  three states (running / cancelling / complete).
- `BulkInfoCard`: dismiss updates `bulkInfoCardDismissedProvider` and hides
  the card.

### 8.4 No E2E

No real DB, no real LLM calls. Unit + widget tests cover logic and
rendering; actual LLM/export integration is validated manually in
`flutter run -d windows`.

### 8.5 TDD

Per the superpowers TDD skill, each handler and the orchestrator are
implemented test-first. Widgets are validated interactively.

## 9. Open Questions for the Implementation Plan

- **Translate batch awaiting** — pick between refactoring the batch service
  to expose a completion `Future<void>` vs. polling. Preference is option A
  if the refactor stays small.
- **Scope indicator counts** — the "match target language" count should be
  cheap (derivable from `ProjectWithDetails.languages`); confirm during
  plan whether a memoised derived provider is needed for large project
  lists.
- **SharedPrefs migration** — none expected; the three new keys are new
  and default to sensible values (`null`, `false`).

## 10. Non-Goals (explicit)

- Parallel execution across projects.
- Multi-language bulk runs.
- Bulk operations reachable from any screen other than Projects.
- Background/minimised bulk runs — the modal is always in the foreground.
- Persistence of in-flight bulk state across app restart.
