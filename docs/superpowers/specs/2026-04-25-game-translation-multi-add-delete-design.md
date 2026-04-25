# Game Translation — multi-create + delete + Projects-style toolbar

**Date**: 2026-04-25
**Status**: Approved (brainstorm)

## Problem

The Game Translation screen (`lib/features/game_translation/screens/game_translation_screen.dart`) only exposes a "Create Game Translation" button on its **empty state**. Once at least one game translation exists, the user has no way to:

- Create another game translation (e.g. a different source pack or different target languages).
- Delete an existing game translation.

The Projects screen (`lib/features/projects/screens/projects_screen.dart`) already solves the same problem with a toolbar that carries the screen title + count, persistent actions, and a per-row delete affordance. Since a game translation is conceptually a project (`projectType == 'game'`), the Game Translation screen should adopt the same UX patterns.

The existing per-language progress bars on `ProjectCard` are kept as-is — no progress-bar work needed.

## Goals

1. Make "create" persistently reachable when projects already exist.
2. Add per-card delete with confirmation, matching the Projects screen's destructive-action pattern.
3. Show a count of existing game translations in the toolbar leading slot.
4. Keep the change minimal — reuse existing widgets, no new screens.

## Non-goals

- Search, filter pills, sort, bulk operations.
- Switching from cards to the row layout used by Projects.
- Optimistic delete + undo.
- Cleanup of generated pack files on disk (matches current Projects delete behavior).
- Automated widget tests (none exist for this screen today).

## Architecture (chosen approach: hybrid)

Keep the existing card layout (`ProjectGrid`/`ProjectCard`). Add a toolbar row that mirrors the Projects screen, and a delete trailing icon on each card.

```
FluentScaffold
├─ HomeBackToolbar  (existing) — leading: ListToolbarLeading(icon, title, count)   ← count added
├─ FilterToolbar    (NEW)      — leading: SizedBox.shrink, trailing: [CreateBtn]
└─ Expanded body
   ├─ Empty state (existing)   — keeps its big "Create" button as primary CTA
   └─ ProjectGrid (existing)   — each ProjectCard shows a delete icon
```

`FilterToolbar` is reused with `pillGroups: const []` so its second row collapses (see `lib/widgets/lists/filter_toolbar.dart:48`).

## Components to change

### 1. `lib/features/game_translation/screens/game_translation_screen.dart`

- Add `count` to `ListToolbarLeading`: `'$n ${n == 1 ? 'translation' : 'translations'}'`. Source: `gameTranslationProjectsProvider`'s data length.
- Insert a `FilterToolbar` below `HomeBackToolbar`:
  - `leading: const SizedBox.shrink()`
  - `expandLeading: false`
  - `trailing: [_CreateGameTranslationButton(...)]`
  - `pillGroups: const []`
- The Create button watches `hasLocalPacksProvider`:
  - If packs available → enabled, opens `CreateGameTranslationDialog` via the existing `_showCreateDialog`.
  - If not → disabled, with tooltip `"No localization packs found for this game"`.
- Add `_handleDeleteProject(ProjectWithDetails details)` that mirrors `projects_screen.dart:376-405`:
  - Show `TokenConfirmDialog` with title `"Delete Game Translation"`, message `'Are you sure you want to delete "${details.project.name}"?'`, warning `"This action cannot be undone."`, confirm label `"Delete"`, icon `delete_24_regular`, `destructive: true`.
  - On confirm: `await ref.read(projectRepositoryProvider).delete(details.project.id)`.
  - On success: `ref.invalidate(gameTranslationProjectsProvider)` and `FluentToast.success(context, 'Game translation "${details.project.name}" deleted')`.
  - On error: `FluentToast.error(context, 'Failed to delete game translation: ${result.error}')`.
- Pass `onDelete` through to `ProjectGrid`.

The empty state and existing _buildContent split is preserved.

### 2. `lib/features/projects/widgets/project_grid.dart`

- Add a `Function(String projectId)? onDelete` prop alongside the existing `onResync` / selection props.
- Forward it to each `ProjectCard` as `onDelete: () => onDelete?.call(projectId)`.
- Default `null` keeps current call sites (Projects screen uses its own row layout, not `ProjectGrid`, so no behavior change there).

### 3. `lib/features/projects/widgets/project_card.dart`

- Add `final VoidCallback? onDelete;` to the constructor (nullable).
- In `_buildHeader`, after the existing trailing widgets (Steam ID block, resync button), append a small delete `IconButton`:
  - Icon `FluentIcons.delete_24_regular`, size 16.
  - Color `theme.colorScheme.error`.
  - Tooltip `"Delete"`.
  - Constraints `BoxConstraints(minWidth: 28, minHeight: 28)`, `padding: EdgeInsets.zero`.
  - Wrapped so the tap doesn't propagate to the card's `onTap` (use `GestureDetector` with `behavior: HitTestBehavior.opaque` if needed, mirroring the existing `_buildResyncButton`).
- Render only when `onDelete != null` so other call sites are unaffected.

## Data flow

```
[Toolbar Create button] ──tap──▶ showDialog(CreateGameTranslationDialog)
                                          │
                                          ▼
                       (dialog already invalidates gameTranslationProjectsProvider on success)

[Card delete icon] ──tap──▶ TokenConfirmDialog (destructive)
                                  │ confirmed
                                  ▼
                          projectRepositoryProvider.delete(id)
                                  │ Ok
                                  ▼
                          ref.invalidate(gameTranslationProjectsProvider)
                                  │
                                  ▼
                          FluentToast.success(...)
```

The `gameTranslationProjectsProvider` is a plain `FutureProvider` (not a notifier). Invalidation is the simplest correct refresh given the small list size; no optimistic patch needed.

## UI states

| State | Toolbar count | Toolbar Create | Body | Card delete icon |
|-------|---------------|----------------|------|------------------|
| Loading | (no count yet) | enabled if packs available | spinner | n/a |
| Error | (no count) | enabled if packs available | error message | n/a |
| Empty + packs available | `0 translations` | enabled | empty-state CTA | n/a |
| Empty + no packs | `0 translations` | disabled (tooltip) | empty-state warning | n/a |
| 1+ projects | `N translation(s)` | enabled or disabled per packs availability | grid of cards | visible on every card |

When the last project is deleted, the body returns to the empty-state branch automatically.

## Edge cases

- **Tap on card vs tap on delete icon**: the delete icon's gesture must not bubble. Match the existing `_buildResyncButton` pattern in `project_card.dart` (`HitTestBehavior.opaque` inside a `GestureDetector`).
- **No local packs**: Create button is rendered but **disabled** (tooltip `"No localization packs found for this game"`). The affordance stays discoverable; the empty state already explains the underlying issue.
- **Delete in flight**: ignored (no concurrency issue at this list size; matches Projects screen).
- **Delete failure**: error toast surfaces `result.error`; the project remains in place because we only invalidate on `isOk`.

## Reused widgets / providers

- `HomeBackToolbar`, `ListToolbarLeading` — already in use on the screen.
- `FilterToolbar` — accepts empty `pillGroups`; second row collapses.
- `TokenConfirmDialog` (`lib/widgets/dialogs/token_confirm_dialog.dart`) — destructive variant.
- `FluentToast` — success/error toasts.
- `projectRepositoryProvider`, `gameTranslationProjectsProvider`, `hasLocalPacksProvider` — already wired.

## Test plan

Manual, on Windows debug (`flutter run -d windows`):

1. Start with no game translations for the selected game → verify empty state still works (regression check).
2. Create one translation → toolbar shows `1 translation`, toolbar Create button visible, card shows delete icon.
3. Click toolbar Create → wizard opens, create a second translation → toolbar shows `2 translations`.
4. Click delete on a card → confirmation dialog shows correct project name → confirm → success toast, count drops to `1 translation`.
5. Delete the last one → empty state returns; the empty-state Create button still works.
6. Disable / remove game install path so `hasLocalPacksProvider` is false → toolbar Create button is disabled with the tooltip; empty state shows the existing warning.
7. Click directly on the delete icon → only the confirm dialog appears (no card-tap navigation).
8. Cancel the confirm dialog → no change, no toast.

## Out-of-scope follow-ups (not for this PR)

- Bulk delete / bulk operations on Game Translation.
- Optimistic delete with notifier-style provider.
- Cleanup of pack files generated in the game's `data/` folder when a project is deleted.
