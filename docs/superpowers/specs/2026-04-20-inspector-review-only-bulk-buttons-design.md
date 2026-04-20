# Hide review-only bulk buttons from non-review multi-select — Design

## Problem

The inspector panel's multi-select header (shown when ≥2 grid rows are
selected) currently renders three stacked bulk buttons — `Accept`,
`Retranslate`, `Deselect` — regardless of whether the selection contains
any `needsReview` rows.

Both `Accept` and `Retranslate` are semantically review-only:

- `Accept` → `handleBulkAcceptTranslation(selectedNeedsReviewRows)` — only
  acts on rows whose status is `needsReview`.
- `Retranslate` → `handleBulkRejectTranslation(allSelectedRows)` — wipes the
  current translation so the row can be re-queued. Destructive for
  already-validated translations; the non-review retranslation path is the
  grid's `onForceRetranslate` → `handleForceRetranslateSelected`.

Showing the two buttons when no selected row is in `needsReview` makes the
inspector look like "review mode" even when the user is just multi-selecting
to clear, copy, or queue a fresh translation. The user reads the panel as a
review UI appearing out of context.

## Scope

- **In:** hide `Accept` and `Retranslate` in the multi-select header when
  the current selection contains no `needsReview` rows. `Deselect` remains
  always.
- **Out:** renaming `Retranslate` → `Reject` (confusing label is real but
  orthogonal), relocating the buttons, or changing `Accept`'s handler.

## Design

### Visibility rule

The multi-select header renders:

- **Any selection with at least one `needsReview` row:** `Accept`,
  `Retranslate`, `Deselect` — same as today.
- **Any selection with zero `needsReview` rows:** `Deselect` only.
- **`selectedCount == 0`:** header is not rendered at all (unchanged).
- **`selectedCount == 1`:** single-selection body renders (unchanged).

### Implementation surface

Two files change:

1. **`lib/features/translation_editor/screens/translation_editor_screen.dart`:**
   Align the `onBulkRetranslate` null-gate with `onBulkAccept`'s — both
   become `null` when `selectedNeedsReviewRows.isEmpty`. Today
   `onBulkRetranslate` is only null when the full selection is empty, which
   is impossible inside the `selectedCount > 1` branch of the inspector, so
   the current gate is effectively always non-null.

2. **`lib/features/translation_editor/widgets/editor_inspector_panel.dart`:**
   In `_MultiSelectHeader.build`, render the `Accept` and `Retranslate`
   `SizedBox` entries (and their preceding `SizedBox(height: 8)` spacer,
   where applicable) only when the corresponding callback is non-null.
   `Deselect` always renders. The `_bulkButtonHeight` constant stays.

The `onBulkAccept` wiring already uses the correct gate
(`selectedNeedsReviewRows.isEmpty ? null : …`) and does not need to change.

### Spacer handling

Today the header is `header text → Accept → spacer → Retranslate → spacer →
Deselect`. When `Accept` and `Retranslate` are hidden, the output must
collapse to `header text → Deselect` with the 16 px gap between header text
and the first visible button preserved. Concretely: we keep the
`SizedBox(height: 16)` after the header text, and the two interior
`SizedBox(height: 8)` spacers move inside the conditional branches so they
disappear alongside their associated buttons.

## Test plan

Extend `test/features/translation_editor/screens/translation_editor_screen_test.dart`
in the same `group` that already tests the multi-select header:

1. Selecting 2 **non-`needsReview`** rows → `Accept` absent,
   `Retranslate` absent, `Deselect` present, `"2 units selected"` text
   present.
2. Selecting 1 `needsReview` row + 1 non-`needsReview` row → all three
   buttons present (rule is "at least one needsReview in selection").

Existing tests (both `needsReview` rows selected → all three visible;
nothing selected → none visible; `Deselect` clears the selection) stay
green because their fixture rows are already `needsReview`.

## Risks

- **Hidden affordance.** A user looking at a non-review selection who wants
  to force-retranslate will no longer see the inspector's `Retranslate`
  button. The grid's context menu `Force retranslate` and the sidebar's
  `Translate selection` both still exist and cover this path. Acceptable —
  the inspector button was doing the wrong thing for this case anyway
  (clearing text via reject-translation).
- **Test fixture dependency.** Tests use `needsReviewRow(...)`. New tests
  will need a similar helper for a non-review row (likely status
  `translated`) — the plan will specify the exact builder to reuse.
