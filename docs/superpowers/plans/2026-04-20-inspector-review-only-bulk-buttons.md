# Hide review-only bulk buttons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide the inspector panel's `Accept` and `Retranslate` bulk buttons when the current multi-selection contains no `needsReview` rows, keeping `Deselect` always visible.

**Architecture:** Two tiny edits. In `translation_editor_screen.dart`, align the `onBulkRetranslate` null-gate with `onBulkAccept`'s gate so both callbacks become `null` when `selectedNeedsReviewRows.isEmpty`. In `_MultiSelectHeader`, skip rendering each of the two review buttons (and their preceding spacer) when its callback is null.

**Tech Stack:** Flutter desktop, Riverpod 3, existing widget test harness in `test/features/translation_editor/screens/translation_editor_screen_test.dart`.

**Reference spec:** `docs/superpowers/specs/2026-04-20-inspector-review-only-bulk-buttons-design.md`

**Files touched:**

- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart` — change one null-gate on `onBulkRetranslate` (around line 312).
- Modify: `lib/features/translation_editor/widgets/editor_inspector_panel.dart` — make `_MultiSelectHeader`'s two review-button entries conditional on callback non-nullity; collapse the adjacent spacers accordingly.
- Modify: `test/features/translation_editor/screens/translation_editor_screen_test.dart` — add a `translatedRow` helper in the existing `Bulk actions` group and add two tests for the new visibility rule.

No new files. No provider changes. No code-gen.

---

## Task 1: Red — failing tests for the new visibility rule

Add two tests before touching production code. Both go inside the existing `group('Bulk actions', () { ... })` in `translation_editor_screen_test.dart`, next to the `needsReviewRow(...)` helper and the existing three tests.

**Files:**
- Modify: `test/features/translation_editor/screens/translation_editor_screen_test.dart`

- [ ] **Step 1: Add the `translatedRow(...)` helper next to `needsReviewRow`**

Inside the `group('Bulk actions', () { ... })` block (currently around line 304), alongside the existing `needsReviewRow(String id) => TranslationRow(...)` helper (line 305), add a sibling helper for a "normal" (non-review) row:

```dart
      TranslationRow translatedRow(String id) => TranslationRow(
            unit: TranslationUnit(
              id: id,
              projectId: testProjectId,
              key: 'k$id',
              sourceText: 's$id',
              createdAt: 0,
              updatedAt: 0,
            ),
            version: TranslationVersion(
              id: '${id}v',
              unitId: id,
              projectLanguageId: 'pl',
              translatedText: 't$id',
              status: TranslationVersionStatus.translated,
              translationSource: TranslationSource.manual,
              createdAt: 0,
              updatedAt: 0,
            ),
          );
```

No `validationIssues` field → defaults to null → not a review row. Everything else mirrors `needsReviewRow` so the two helpers stay parallel.

- [ ] **Step 2: Add test — selection of only non-review rows hides Accept and Retranslate**

Append the test below after the existing `'Deselect clears the editor selection'` test (currently ending around line 384), still inside `group('Bulk actions', ...)`:

```dart
      testWidgets(
          'Accept and Retranslate are hidden when selection has no needsReview rows',
          (tester) async {
        final rows = [translatedRow('a'), translatedRow('b')];
        await tester.pumpWidget(createTestWidget(rows: rows));
        await tester.pumpAndSettle();

        final element = tester.element(find.byType(TranslationEditorScreen));
        final container = ProviderScope.containerOf(element, listen: false);
        container
            .read(editorSelectionProvider.notifier)
            .toggleSelection('a');
        container
            .read(editorSelectionProvider.notifier)
            .toggleSelection('b');
        await tester.pumpAndSettle();

        // Header still signals a multi-select, but the two review-only
        // actions are not rendered — only the always-present Deselect.
        expect(find.text('2 units selected'), findsOneWidget);
        expect(find.text('Accept'), findsNothing);
        expect(find.text('Retranslate'), findsNothing);
        expect(find.text('Deselect'), findsOneWidget);
      });
```

- [ ] **Step 3: Add test — mixed selection (≥1 needsReview row) still shows all three buttons**

Immediately after the previous test, still inside the same group, add:

```dart
      testWidgets(
          'Accept and Retranslate reappear when at least one selected row is needsReview',
          (tester) async {
        final rows = [translatedRow('a'), needsReviewRow('b')];
        await tester.pumpWidget(createTestWidget(rows: rows));
        await tester.pumpAndSettle();

        final element = tester.element(find.byType(TranslationEditorScreen));
        final container = ProviderScope.containerOf(element, listen: false);
        container
            .read(editorSelectionProvider.notifier)
            .toggleSelection('a');
        container
            .read(editorSelectionProvider.notifier)
            .toggleSelection('b');
        await tester.pumpAndSettle();

        expect(find.text('2 units selected'), findsOneWidget);
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Retranslate'), findsOneWidget);
        expect(find.text('Deselect'), findsOneWidget);
      });
```

- [ ] **Step 4: Run the test file to confirm the new tests fail**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/translation_editor_screen_test.dart`

Expected: the first new test fails on `find.text('Accept')` (today it finds the disabled button, so `findsNothing` fails). The second new test passes incidentally (status quo already renders all three with any selection), but stays green after the implementation lands.

At least the first new test MUST be red before proceeding. Do NOT commit yet.

---

## Task 2: Green — screen-level gate + inspector skip (one commit)

Tighten the screen's null-gate on `onBulkRetranslate` and teach `_MultiSelectHeader` to skip null-callback review buttons.

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Modify: `lib/features/translation_editor/widgets/editor_inspector_panel.dart`

- [ ] **Step 1: Align the `onBulkRetranslate` null-gate**

Open `lib/features/translation_editor/screens/translation_editor_screen.dart`. Find the `onBulkRetranslate:` block around line 312 that currently reads:

```dart
                      onBulkRetranslate: allSelectedRows.isEmpty
                          ? null
                          : () async {
                              await _getActions()
                                  .handleBulkRejectTranslation(
                                      allSelectedRows);
                            },
```

Replace the first line's condition with the same gate that `onBulkAccept` uses (line 305):

```dart
                      onBulkRetranslate: selectedNeedsReviewRows.isEmpty
                          ? null
                          : () async {
                              await _getActions()
                                  .handleBulkRejectTranslation(
                                      allSelectedRows);
                            },
```

Only the condition on the first line changes. The handler body stays identical — it still passes `allSelectedRows` to `handleBulkRejectTranslation` because the review flow intentionally targets every selected row, not just the flagged ones, once at least one is flagged. `selectedCount > 1` is enforced by the enclosing branch in the inspector, so the gate correctly reads "any needs-review rows present".

- [ ] **Step 2: Skip null-callback review buttons in `_MultiSelectHeader`**

Open `lib/features/translation_editor/widgets/editor_inspector_panel.dart`. Find the `_MultiSelectHeader.build` method (starts around line 256) and replace the current `Column(...)` body with the version below. The change: each of the two review `SizedBox` entries is now conditional on its callback being non-null, and the `SizedBox(height: 8)` spacers move inside the conditional branches so they disappear alongside their buttons.

```dart
  @override
  Widget build(BuildContext context) {
    final showAccept = onBulkAccept != null;
    final showRetranslate = onBulkRetranslate != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count units selected',
          style: tokens.fontDisplay.copyWith(
            fontStyle: tokens.fontDisplayStyle,
            fontSize: 16,
            color: tokens.accent,
          ),
        ),
        const SizedBox(height: 16),
        // Bulk buttons stacked full-width so both icon and label always have
        // room at any panel width. Each button is `_bulkButtonHeight` px tall
        // (double the issue-row button height) for a comfortable bulk-click
        // target. Accept and Retranslate are review-only — they collapse out
        // of the layout when no `needsReview` row is in the selection.
        if (showAccept) ...[
          SizedBox(
            height: _bulkButtonHeight,
            child: _InspectorActionButton(
              label: 'Accept',
              icon: FluentIcons.checkmark_24_regular,
              color: tokens.accent,
              onTap: onBulkAccept,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (showRetranslate) ...[
          SizedBox(
            height: _bulkButtonHeight,
            child: _InspectorActionButton(
              label: 'Retranslate',
              icon: FluentIcons.arrow_sync_24_regular,
              color: tokens.warn,
              onTap: onBulkRetranslate,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: _bulkButtonHeight,
          child: _InspectorActionButton(
            label: 'Deselect',
            icon: FluentIcons.dismiss_circle_24_regular,
            color: tokens.textMid,
            onTap: onBulkDeselect,
          ),
        ),
      ],
    );
  }
```

Nothing else in `_MultiSelectHeader` or in the file changes. The expression-body `build(...) =>` becomes a block-body `build(...) { ... }` because we now have two local `final` variables — that's the only structural change.

- [ ] **Step 3: Run the editor screen test file**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/screens/translation_editor_screen_test.dart`

Expected: all tests in the file pass, including the two new ones and the three pre-existing Bulk-actions tests (which use `needsReviewRow` and so still see all three buttons).

- [ ] **Step 4: Run the inspector panel test file**

Run: `C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_inspector_panel_test.dart`

Expected: green. `_MultiSelectHeader` isn't exercised by these tests today (the file focuses on single-selection bodies and per-issue action callbacks), but run it anyway to make sure the expression-to-block build refactor didn't introduce a compile-level issue that propagates.

- [ ] **Step 5: Run the full test suite**

Run: `C:/src/flutter/bin/flutter test`

Expected: the full suite stays at its previous pass count plus the two new tests added in Task 1. Any unrelated failure is a signal to stop and investigate, not to patch.

- [ ] **Step 6: Commit**

```bash
git add lib/features/translation_editor/screens/translation_editor_screen.dart lib/features/translation_editor/widgets/editor_inspector_panel.dart test/features/translation_editor/screens/translation_editor_screen_test.dart
git commit -m "feat: hide review-only bulk buttons outside review selection"
```

---

## Task 3: Manual smoke check

- [ ] **Step 1: Launch the app**

Run: `C:/src/flutter/bin/flutter run -d windows`

- [ ] **Step 2: Verify the three selection states**

Open a project/language with a mix of translated and `needsReview` rows.

1. **Zero selection:** inspector shows the empty placeholder (unchanged).
2. **Multi-select of only translated rows:** header text `N units selected`
   + `Deselect` only. No `Accept`, no `Retranslate`. Layout is tight (no
   empty slots, no orphaned spacers).
3. **Multi-select that includes at least one `needsReview` row:** all
   three buttons visible, same layout as before the change.

- [ ] **Step 3: Report**

If the three states behave as specified, the feature is done. If layout has orphaned spacers or the header stretches oddly, fix and commit on its own.
