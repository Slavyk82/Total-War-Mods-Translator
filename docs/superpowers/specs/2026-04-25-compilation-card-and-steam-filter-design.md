# Compilation card metadata + Steam Publish "Compilations" filter

## Goal

Two small UI improvements:

1. On the **Pack compilations** list screen, surface compilation metadata that
   today is hidden behind the editor: the target language, the date the pack
   was last generated, and a clear visual when the pack is stale because one
   of the bundled projects changed after the last generation.
2. On the **Publish on Steam** screen, let the user filter the list to show
   only compilations (alongside the existing All / Outdated / No pack pills).

Scope is limited to display changes and one new state-filter case. No new
persistence, no migration, no behavior changes around pack generation or
publishing.

## Context

Existing data already supports everything we need:

- `Compilation.languageId` (FK to `Language`) — at
  `lib/models/domain/compilation.dart:30`.
- `Compilation.lastGeneratedAt` (Unix ms) — at
  `lib/models/domain/compilation.dart:38`. Set by
  `CompilationRepository.updateAfterGeneration()` after a successful pack
  build (`lib/repositories/compilation_repository.dart:254-276`).
- `Project.updatedAt` (Unix ms) — at `lib/models/domain/project.dart:69`.
- `compilationsWithDetailsProvider`
  (`lib/features/pack_compilation/providers/pack_compilation_providers.dart:74-128`)
  already loads each compilation's projects, so we can compute "needs
  regeneration" without an extra round-trip.
- `Steam Publish` already separates `ProjectPublishItem` from
  `CompilationPublishItem` via `PublishableItem.isCompilation`
  (`lib/features/steam_publish/providers/steam_publish_providers.dart:44-168`),
  so a "compilations only" filter is a one-line predicate.

## Design

### 1. Compilation card

#### Data layer

- Add a nullable `Language? language` field to `CompilationWithDetails`
  (`lib/features/pack_compilation/models/compilation_with_details.dart`).
- In `compilationsWithDetailsProvider`, after resolving the projects, if
  `compilation.languageId != null` resolve the language via the existing
  `languageRepositoryProvider` and pass it to `CompilationWithDetails`.

#### Visual layout

The current row has three columns:

```
[ name + packName (flex) ] [ X packs (120) ] [ updated_at (100) ]
```

We add a fourth column for pack status and place the language as a small
chip next to the title. The new layout is:

```
[ name (+ FR chip)
  packName                                                (flex) ]
[ X packs                                                  (120) ]
[ Pack outdated | Last pack: 3d ago | Never generated     (140) ]
[ updated_at                                               (100) ]
```

- **Language chip**: rendered to the right of the name on the same line, a
  bordered pill with `language.code.toUpperCase()` (e.g. `FR`). Only shown
  when `details.language` is non-null. Uses `tokens.panel2` background and
  `tokens.border` outline so it stays visually quiet.
- **Pack status column** (140px, right-aligned):
  - `lastGeneratedAt == null`              → text `Never generated`, color
    `tokens.textFaint` mono.
  - any `project.updatedAt > lastGeneratedAt` → small badge
    `Pack outdated` using a warning color (orange) with a faint background
    fill. Tooltip: `One or more projects changed after the last pack
    generation`.
  - otherwise                               → `Last pack: <relative>`
    formatted with the existing `formatRelativeSince()` helper.
- **Updated_at column** (100px, right-aligned, unchanged): kept as today —
  reflects the last edit to the compilation entity itself, distinct from
  the last pack generation.

The "needs regeneration" check runs in the row widget against the already-
loaded `details.projects` list; no extra provider, no extra IO.

### 2. Steam Publish "Compilations" filter

The existing filter is single-choice; "Compilations" becomes a 4th option.
Combining "Compilations" with "Outdated" or "No pack" is out of scope for
this change — the UX stays consistent with the current radio-style group.

#### Provider layer

In `lib/features/steam_publish/providers/steam_publish_providers.dart`:

- Extend the enum:
  ```dart
  enum SteamPublishDisplayFilter { all, outdated, noPackGenerated, compilations }
  ```
- Extend the switch in `filteredPublishableItemsProvider`:
  ```dart
  case SteamPublishDisplayFilter.compilations:
    result = result.where((e) => e.isCompilation).toList();
  ```
- Add a count provider mirroring the existing two:
  ```dart
  @riverpod
  int compilationsPublishableItemsCount(Ref ref) {
    final asyncItems = ref.watch(publishableItemsProvider);
    final items = asyncItems.asData?.value ?? const <PublishableItem>[];
    return items.where((e) => e.isCompilation).length;
  }
  ```

#### Toolbar

In `lib/features/steam_publish/widgets/steam_publish_toolbar.dart`:

- Accept a new `int compilationsCount` constructor parameter and forward it
  to the new pill.
- Add a `Compilations` `FilterPill` after `No pack` with the toggle pattern
  used by the others (clicking when active deselects back to `all`).

In `lib/features/steam_publish/screens/steam_publish_screen.dart`:

- Watch the new `compilationsPublishableItemsCountProvider` and pass it
  into `SteamPublishToolbar`.

## Out of scope

- Combining filters (e.g. "outdated compilations only").
- Changing the structure of the existing STATE pill group into a multi-
  select.
- Surfacing compilation language anywhere outside the list card.
- Any change to compilation generation, conflict analysis, or publishing
  flow.

## Testing

- Manual: open Pack compilations with at least one compilation that has
  never been generated, one freshly generated, and one whose member project
  was edited since `lastGeneratedAt`. Verify the three pack-status states
  render correctly. Toggle the language to confirm the chip appears /
  hides.
- Manual: open Publish on Steam, click the new `Compilations` pill and
  confirm only compilations remain in the list and the count badge matches
  the result. Toggle off, confirm the list returns to `All`.
- Existing `pack_compilation_list_screen` and `steam_publish_toolbar`
  widget tests should keep passing; update fixtures where `_CompilationRow`
  consumers / toolbar constructor changed.
