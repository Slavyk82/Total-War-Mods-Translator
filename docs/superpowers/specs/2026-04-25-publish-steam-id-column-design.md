---
title: Steam ID column on the Publish on Steam list
date: 2026-04-25
status: design
---

# Steam ID column on the Publish on Steam list

## Goal

Surface every mod's Workshop Steam ID directly in the *Publish on Steam* list, and move the inline edit pencil into a dedicated column so the ID becomes a first-class, always-visible, always-editable field — instead of hiding behind a pencil tucked inside the action cell.

## Context

The *Publish on Steam* screen renders a row per publishable item (Project or Compilation) using the shared `ListRow` archetype. Today the columns are:

| # | Column            | Width        |
|---|-------------------|--------------|
| 1 | checkbox          | 40           |
| 2 | cover             | 80           |
| 3 | title + filename  | flex(3)      |
| 4 | subs              | 100          |
| 5 | status            | 160          |
| 6 | last published    | 180          |
| 7 | action            | 180          |

The Workshop Steam ID is currently invisible in the list — it only appears (a) inside the *Status* tooltip and (b) inside the action cell whenever the inline TextField is showing (state B, or after the user clicks the pencil in states A₀/A₁/C). The pencil lives in the **action cell**: clicking it transforms the entire action cell into an inline editor (TextField + Save + Cancel + sometimes Open launcher).

## Design

### Column changes

Insert a new **`Steam ID`** column between *Pack* (col 3) and *Subs* (col 4), fixed width **180 px**:

| # | Column            | Width        |
|---|-------------------|--------------|
| 1 | checkbox          | 40           |
| 2 | cover             | 80           |
| 3 | title + filename  | flex(3)      |
| **4** | **Steam ID**  | **180**      |
| 5 | subs              | 100          |
| 6 | status            | 160          |
| 7 | last published    | 180          |
| 8 | action            | 180          |

Header label: `Steam ID`.

### New widget: `SteamIdCell`

A `ConsumerStatefulWidget` rendered in the new column. It owns three rendering modes — picked deterministically from `(hasPack, hasPublishedId, _isEditing)`:

#### Mode 1 — Read

Triggered when: `!_isEditing && hasPublishedId`.

Layout: monospace ID + pencil icon button right-aligned.

```
[ 3024186382                       ✏️ ]
```

- ID style: `tokens.fontMono`, size 12, color `tokens.textMid`
- Pencil: same `_iconButton` square as the action cell uses today (28 × 28, `FluentIcons.edit_24_regular`, tooltip `Edit Workshop id`)
- Tap on pencil → switches to Mode 3 (manual edit), pre-filling the TextField with the current ID

#### Mode 2 — Read (no ID)

Triggered when: `!_isEditing && !hasPublishedId && (!hasPack || _autoEditDismissed)` — i.e. whenever there's no ID and we're **not** in the auto-open state-B case.

Layout: dim `—` + pencil icon button. Same shape as Mode 1, just with `—` (color `tokens.textFaint`) instead of an ID.

Tap on pencil → switches to Mode 3 (manual edit), TextField empty.

> **Note on `_autoEditDismissed`:** in state B (pack + no ID) the cell auto-opens into Mode 3 (see below). If the user explicitly cancels that auto-edit, we don't want the cell to immediately re-open the editor on the next rebuild. A local `_autoEditDismissed` flag keeps the cell in Mode 2 for the rest of the row's lifetime. (The flag resets when the row is rebuilt from a fresh `PublishableItem`, e.g. after a successful save invalidates the provider — but at that point `hasPublishedId` is true and we're in Mode 1 anyway, so the flag is moot.)

#### Mode 3 — Edit

Triggered when:
- `_isEditing == true` (manual entry via pencil), **or**
- `hasPack && !hasPublishedId && !_autoEditDismissed` (state B auto-open)

Layout: TextField + Save + Cancel inline (Cancel only when manually triggered or auto-edit can be dismissed; see "Cancel visibility" below).

```
[ Paste Workshop URL or ID...     ] [💾] [✖]
  1. Publish from launcher · 2. Copy the mod URL here    ← only in state-B auto-open
```

- TextField: same shape as the current `_buildSteamIdInput` in the action cell — `tokens.fontMono` 12, `tokens.panel2` background, height 28, hint `Paste Workshop URL or ID...`
- Save icon: `FluentIcons.save_24_regular`, accent style, disabled / spinner while saving
- Cancel icon: `FluentIcons.dismiss_24_regular` — see **Cancel visibility** below
- 2-step hint: rendered in the column **only** when the cell auto-opened from state B (i.e. there's no prior ID — so the user is being walked through the first publish). In manual edit (existing ID being changed), the hint is hidden.

**Cancel visibility:**

| Scenario                                  | Show Cancel? | Why                                                              |
|-------------------------------------------|:-:|---------------------------------------------------------------------------|
| Manual edit (pencil click) on an ID       | ✅ | Cancel reverts to the prior ID                                            |
| Manual edit (pencil click) without an ID  | ✅ | Cancel returns to Mode 2 (`—` + pencil)                                   |
| Auto-open in state B                      | ✅ | Cancel sets `_autoEditDismissed = true` and returns to Mode 2             |

So Cancel is **always shown in edit mode**.

### Save semantics

`SteamIdCell` reuses the exact same parsing + persistence logic as the current `_saveSteamId` in `SteamActionCell`:

1. Trim the input. If empty, no-op.
2. `parseWorkshopId(raw)` — accepts bare numeric IDs and full Workshop URLs. Returns `null` on garbage; in that case raise a `FluentToast.warning("Couldn't read a Workshop ID from that value.")`.
3. Persist:
    - `ProjectPublishItem` → `projectRepository.update(...)` with `publishedSteamId: parsed`
    - `CompilationPublishItem` → `compilationRepository.updateAfterPublish(item.compilation.id, parsed, item.publishedAt ?? 0)`
4. `ref.invalidate(publishableItemsProvider)` — triggers row rebuild; `hasPublishedId` becomes true → cell flips to Mode 1.

The save logic is **lifted into a top-level helper** in a new `steam_id_editing.dart`, so the heavy lifting lives in one place even though the only caller (for now) is `SteamIdCell`. Signature:

```dart
/// Parses [rawInput] into a Workshop id, persists it on the right
/// repository, invalidates [publishableItemsProvider]. Surfaces a warning
/// toast on parse failure and an error toast on repository failure.
/// Returns true on success, false otherwise. Safe to await on a
/// disposed widget — caller checks `mounted` before calling `setState`.
Future<bool> saveWorkshopId({
  required WidgetRef ref,
  required BuildContext context,
  required PublishableItem item,
  required String rawInput,
});
```

### `SteamActionCell` changes

The action cell loses its inline editor. Its new state machine:

| State | Condition                       | Action cell renders                                   |
|-------|---------------------------------|-------------------------------------------------------|
| A₀    | `!hasPack && !hasPublishedId`   | `[Generate pack]` (full width)                        |
| A₁    | `!hasPack && hasPublishedId`    | `[Generate pack] [Open in Steam]`                     |
| **B** | `hasPack && !hasPublishedId`    | **`[Update (disabled)] [Open launcher]`**             |
| C     | `hasPack && hasPublishedId`     | `[Update] [Open in Steam]`                            |

Removed from the action cell entirely:
- `_buildSteamIdInput` and the inline TextField path
- The pencil icon button in A₀/A₁/C (`FluentIcons.edit_24_regular`)
- The Cancel branch tied to `_isEditingSteamId`
- Local state: `_isSavingSteamId`, `_isEditingSteamId`, `_steamIdController`

The "Open launcher" play button (`FluentIcons.play_24_regular`) survives — it now lives in state B's row alongside the disabled Update button. The 2-step hint text moves to the new `SteamIdCell` (state-B auto-open mode).

The disabled `Update` button in state B reuses the existing Update visual but with:
- `MouseRegion` cursor `SystemMouseCursors.basic`
- `onTap: null`
- Foreground / border / background colors switched to `tokens.textFaint` / `tokens.border` / `tokens.panel2` (same shape, dimmer)
- Tooltip: `Set the Steam ID first to enable updating`

### Header

The `_SteamPublishListHeader` labels list grows from 7 to 8 entries:

```dart
labels: const [
  '',           // checkbox
  '',           // cover
  'Pack',
  'Steam ID',   // ← new
  'Subs',
  'Status',
  'Last published',
  '',           // action
],
```

### Layout fit & total width

Adding a 180 px column widens the row's fixed footprint by 180 px. The list shares the `ListRow` archetype, which lays out fixed columns first then gives the remaining space to flex columns; the title block (col 3, `flex(3)`) absorbs any remaining width and shrinks gracefully when the viewport is narrow. We don't change any other column's width or flex weight.

## Out of scope

- Editing the Steam ID from anywhere outside the *Publish on Steam* list (the Project / Compilation detail screens keep their own editors as-is, no parity change).
- Validating the Steam ID against Steam's Workshop API at save time. Today we only parse the shape — that doesn't change.
- Bulk edit of Steam IDs across multiple rows. Pencil edits are one-row-at-a-time.
- Persisting `_autoEditDismissed` across screen navigations / app restarts. It's per-row in-memory state; once the screen is rebuilt, an item still in state B will auto-open again. This matches the spirit of the "first-publish guidance" UX.

## Files touched

- `lib/features/steam_publish/widgets/steam_publish_list_cells.dart` — add `steamPublishColumns` entry, add `SteamIdCell` widget
- `lib/features/steam_publish/widgets/steam_publish_list.dart` — wire the new cell in `SteamPublishList`, add the `Steam ID` header label
- `lib/features/steam_publish/widgets/steam_publish_action_cell.dart` — strip the inline editor + pencils, add the disabled-Update + Open-launcher pair for state B
- `lib/features/steam_publish/widgets/steam_id_editing.dart` *(new)* — shared save helper

## Risks & considerations

- **Auto-open cancel UX**: dismissing the auto-open via Cancel and falling back to Mode 2 (`—` + pencil) is a deliberate escape hatch. Without it, state B would feel "stuck" once the user accidentally focuses the field. The `_autoEditDismissed` flag ships with the cell.
- **Disabled Update discoverability**: a tooltip on the disabled Update button will explain the gating ("Set the Steam ID first to enable updating") so users don't get confused why nothing happens.
- **Action-cell cleanup risk**: the Action cell is large — careful surgical removal of `_buildSteamIdInput`, `_steamIdController`, `_isEditingSteamId`, `_isSavingSteamId`, `_saveSteamId` ensures we don't leave dead state. The Open-launcher path needs to remain reachable from state B.
