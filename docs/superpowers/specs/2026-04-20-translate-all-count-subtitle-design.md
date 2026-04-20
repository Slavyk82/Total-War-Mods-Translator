# Translate-all button count subtitle — Design

## Problem

The sidebar's primary `Translate all` button does not tell the user how many
units it will actually queue. The count only surfaces once the confirmation
dialog opens (`Translate N untranslated units?`). Users want to know *before*
clicking whether there is anything meaningful to translate, so they can skip
the click entirely when the count is misleading (stale cache, wrong filter
expectation, etc.).

## Scope

- **In:** a short count subtitle rendered directly under the sidebar's
  `Translate all` button.
- **Out:** any change to the `Translate selection` variant, the confirmation
  dialog text, the screen-scope `Ctrl+T` behaviour, or the `editorStats`
  provider.

## Design

### Count source

Reuse `editorStatsProvider(projectId, languageId).pendingCount` (defined in
`lib/features/translation_editor/providers/grid_data_providers.dart`). This
provider already powers the top-bar `Pending` pill, so the sidebar subtitle
will always match what the user sees on the pill.

`pendingCount` is derived from `getLanguageStatistics` (status priority ≤ 2),
which is not byte-identical to `getUntranslatedIds` (content-based: empty
`translated_text`, non-obsolete, non-`[HIDDEN]`). In normal operation these
two answers agree; any drift is a pre-existing data-integrity concern, not a
new inconsistency introduced by this feature. Keeping the sidebar in step
with the `Pending` pill is the priority.

### Visibility rules

The subtitle renders **only** when all of the following hold:

1. No rows are selected (label reads `Translate all`).
2. `editorStatsProvider` is in a `data` state (no subtitle while loading or on
   error — we do not flash placeholders).
3. `pendingCount > 0`.

When any rule fails, no subtitle is rendered and the layout collapses back to
the bare button. This keeps `Translate selection` visually identical to the
current design and avoids a stale "0 units" line when there is nothing to
translate (the existing `showNoUntranslatedDialog` already covers that path).

### Layout & style

- Rendered as a separate `Text` widget **below** `_SidebarActionButton`, not
  nested inside the button's 36 px box. This preserves vertical rhythm with
  the other primary buttons (`Validate`, `Generate pack`).
- A small vertical gap (`SizedBox(height: 4)`) between the button and the
  subtitle.
- Style: `tokens.fontBody`, `fontSize: 10.5`, `color: tokens.textDim`,
  `fontWeight: FontWeight.w400`, centered. Matches the dim-caption register
  used elsewhere in the sidebar.
- Content: `"$pendingCount unit"` for 1, `"$pendingCount units"` otherwise.

### Component boundary

The subtitle is rendered inline in `EditorActionSidebar.build`, inside the
same `Consumer` that already decides the button label. That `Consumer` gains
one extra watch (`editorStatsProvider`) and emits a `Column` containing the
button plus the conditional subtitle widget. No changes to the
`_SidebarActionButton` API.

## Test plan

Extend `test/features/translation_editor/widgets/editor_action_sidebar_test.dart`:

1. No selection + `pendingCount = 42` → subtitle `"42 units"` visible.
2. No selection + `pendingCount = 1` → subtitle `"1 unit"` visible
   (singular).
3. No selection + `pendingCount = 0` → no subtitle widget rendered.
4. Selection present → label is `Translate selection`; no subtitle.
5. `editorStatsProvider` in loading state → no subtitle.

Existing tests for the sidebar stay green (button label, routing, shortcut
hint) because `_SidebarActionButton` is unchanged.

## Risks

- **Stats drift vs. actual click count.** `pendingCount` and the dialog's
  count can differ in pathological cases (e.g. stale status after a manual
  SQL edit). Documented above; acceptable for a UX hint.
- **Count flicker after translation batches complete.** `editorStats` already
  watches `translationRowsProvider`, so the subtitle will refresh along with
  the rest of the editor without extra wiring.
