# Set Workshop ID before pack generation — Design

**Date**: 2026-04-24
**Scope**: `lib/features/steam_publish/widgets/steam_publish_action_cell.dart` + associated tests.

## Problem

On the "Publish on Steam" screen, the per-row action cell (`SteamActionCell`) prevents a user from associating a project (or compilation) with an existing Steam Workshop ID as long as the local `.pack` file has not been generated.

Current state machine (three rendering modes):

| State | Condition | Rendering |
|---|---|---|
| A | `!hasPack` | `[Generate pack]` (+ `[Open in Steam]` when a `publishedSteamId` already exists) |
| B | `hasPack && !hasPublishedId` | Inline Workshop-ID text field + launcher + save |
| C | `hasPack && hasPublishedId` | `[Update] [Open in Steam] [Edit id]` |

**The gap**: in State A there is no UI to set the Workshop ID. Users who want to pre-link a project to an existing Workshop entry (e.g., imported a project from Steam, or already published via an earlier workflow) must first generate a pack before they can paste the Workshop URL/ID. Additionally, when `!hasPack && hasPublishedId` (State A with an id carried over from a previous publish), the id is not editable — there is no way to fix a wrong id without first regenerating a pack.

## Goal

Allow saving/editing the Workshop ID of a `PublishableItem` from the action cell in all states, including when no pack is generated yet.

Non-goals:
- Batch-setting Workshop IDs for multiple items at once.
- Adding a "Set Workshop ID" affordance on the Projects screen or elsewhere outside the action cell.
- Changing `_publishDisabledTooltip` semantics (pack + id still required to publish).
- Changing persistence — `publishedSteamId` is already an independent field on `Project` and `Compilation`.

## Solution

Extend the state machine with two new sub-modes (A₀ / A₁), both reusing the existing inline Workshop-ID input widget (`_buildSteamIdInput`) when in editing mode.

| State | Condition | Rendering |
|---|---|---|
| A₀ | `!hasPack && !hasPublishedId && !editing` | `[Generate pack] [✎]` |
| A₁ | `!hasPack && hasPublishedId && !editing` | `[Generate pack] [Open in Steam] [✎]` |
| A-edit | `!hasPack && _isEditingSteamId` | Inline input (shared with State B) |
| B | `hasPack && !hasPublishedId` | Inline input — unchanged |
| C | `hasPack && hasPublishedId && !_isEditingSteamId` | `[Update] [Open in Steam] [✎]` — unchanged |
| C-edit | `hasPack && _isEditingSteamId` | Inline input (shared with State B) — unchanged |

### UI details

- **Pencil icon** (`FluentIcons.edit_24_regular`) reuses the existing `_iconButton` helper. Tooltip:
  - `'Set Workshop id'` in **A₀** (no id yet).
  - `'Edit Workshop id'` in **A₁** and **C** (existing id being changed).
- **Inline input** is the existing `_buildSteamIdInput`. Kept verbatim:
  - Text field with hint `'Paste Workshop URL or ID...'`.
  - `[▶ Open launcher]` button — kept in all edit modes (user's choice, validated during brainstorming). Visual consistency with State B and useful for users who want to open Steam even without a pack.
  - `[💾 Save]` button calling `_saveSteamId`.
  - `[✕ Cancel]` visible whenever `_isEditingSteamId` is true, reverts to the pre-edit rendering.
  - Helper text `'1. Publish from the launcher · 2. Copy the mod URL here'` — kept unchanged.

### Code changes (`steam_publish_action_cell.dart`)

1. **Modify the top of `build()`** so that entering the input branch no longer requires `hasPack`:

   ```dart
   if (_isEditingSteamId || (hasPack && !hasPublishedId)) {
     return _buildSteamIdInput(context);
   }
   ```

2. **State A branch (`!hasPack`)** — modify the two existing Row compositions to append a pencil `_iconButton`:

   - **A₀ (no id)**: currently returns `_buildGenerateButton(context)`. Change to a Row with `[Expanded(generateBtn), ✎]`.
   - **A₁ (has id)**: currently returns a Row with `[Expanded(generateBtn), [Open in Steam]]` (lines 64–80). Append `✎` after the Open-in-Steam button.

3. **Pencil tap handler** (reused in A₀/A₁ and already existing in C):

   ```dart
   () {
     _steamIdController.text = widget.item.publishedSteamId ?? '';
     setState(() => _isEditingSteamId = true);
   }
   ```

4. **No changes to `_saveSteamId`** — the existing persistence path handles both `ProjectPublishItem` and `CompilationPublishItem` independently of pack presence.

5. **No changes to provider layer, no new providers**. `ref.invalidate(publishableItemsProvider)` already runs after a successful save, which recomputes `hasPack` / `publishedSteamId` and drives the cell back to the correct non-edit state (A₀ → A₁, or A₁ with updated id).

### Tests — new cases in `test/features/steam_publish/widgets/steam_publish_action_cell_state_test.dart`

TDD order:

1. **`State A (no pack, no id) shows the Set-id icon button`** — render `_project()` unchanged; assert `find.byTooltip('Set Workshop id')` exists, and `[Generate pack]` still renders.
2. **`State A (no pack, with id) shows Open in Steam + Edit id`** — render `_project(publishedSteamId: '123')`; assert all three affordances (`Generate pack`, `Open in Steam` tooltip, `Edit Workshop id` tooltip) are visible.
3. **`State A edit-id tap reveals the inline input`** — tap the pencil, `pumpAndSettle`, assert the `TextField` with hint `'Paste Workshop URL or ID...'` is visible and the launcher tooltip `'Open the in-game launcher'` is present.
4. **`State A saves a Workshop URL without a pack`** — mirror of existing State-B URL test, but for a pack-less `_project()`. Inject a fake `ProjectRepository` via `projectRepositoryProvider` override, tap the pencil, enter a Workshop URL, tap Save, assert the extracted numeric id was persisted via `projectRepo.update`.
5. **`State A cancel returns to the non-edit rendering`** — tap the pencil, tap `✕`, assert the input is gone and `[Generate pack]` is back.

Existing State B / State C tests must continue to pass without modification (the input condition `hasPack && !hasPublishedId` still matches the same scenarios, and `_isEditingSteamId` still drives State C edits).

## Risks & mitigations

- **Risk**: Adding a widget to the right of `[Generate pack]` in a narrow cell could overflow. **Mitigation**: the existing `Row` already wraps `[Generate pack]` in `Expanded` (State A₁). We reuse the same pattern for A₀ and keep the pencil at fixed width (28px like existing `_iconButton`). The existing `SingleChildScrollView` inside the button handles text clipping if needed.
- **Risk**: Entering the input mode in State A re-uses `_buildSteamIdInput` which contains `Open launcher` — meaningful only with a Steam install. **Mitigation**: launcher was explicitly kept for visual consistency and pre-existing behaviour when Steam is missing (toast warning, already implemented).
- **Risk**: Two new sub-modes could make the state machine harder to reason about. **Mitigation**: the docstring at the top of the class is updated to describe the 5-mode split and call out that A-edit / C-edit share the same widget.

## Rollout

Single PR on the current branch area (or a dedicated branch off `main`). No data migration, no feature flag — purely additive UI.
