# Publish screen — display subscriber counts of published translation mods

**Date:** 2026-04-25
**Scope:** Steam Publish screen + app boot sequence
**Status:** Draft for review

---

## Context

The Steam Publish screen lists translation mods the user has built from this
app — projects (`ProjectPublishItem`) and compilations (`CompilationPublishItem`).
Each item carries a `publishedSteamId` (Workshop id of the *published translation*,
distinct from `project.modSteamId` which points at the *original* mod). Today the
list shows pack metadata (export date, status, last-published) but no popularity
signal, so the user has no way to see which of their published translations are
gaining traction without leaving the app.

The Steam Workshop API the app already uses (`WorkshopApiServiceImpl.getMultipleModInfo`)
returns a `subscriptions` field per item, and the **Mods** screen already displays
this for the original game mods. The infrastructure is in place — the work is to
plumb it through to the Publish screen.

## Goals

- Show, per row in the Publish list, the current number of subscribers of the
  *published translation mod*.
- Show, in the Publish toolbar leading text, a cumulative subscriber total over
  the currently filtered list.
- Refresh subscriber counts **once per app session**, folded into the existing
  bootstrap mod-scan dialog — no extra popup, no per-screen refresh.
- Zero schema changes: subscriber counts live in an in-memory cache that resets
  on app restart.

## Non-goals

- Persisting subscriber counts in the SQLite DB (no migrations, no new columns).
- A dedicated "Refresh subs" button in the Publish toolbar (the existing
  Refresh button rebuilds the items list; subs are not refetched mid-session).
- Historical/time-series tracking of subscriber growth.
- Subscriber counts for the *original* mods (already shown on the Mods screen).
- Showing subs for items where `publishedSteamId` is null/empty (an `–` is
  displayed instead).

## Architecture

### 1. In-memory subscriber cache

A new Riverpod notifier provider, kept alive for the app session:

```
PublishedSubsCache (keepAlive: true)
  state: Map<String, int>  — publishedSteamId -> subscriber count
  + refreshFromWorkshop({Set<String>? ids}) async
```

- `state` starts empty.
- `refreshFromWorkshop` fetches subscriber counts for every published Workshop
  id known to the DB (or a caller-provided subset). On success it **replaces**
  `state` wholesale with the freshly-fetched map (per-chunk results merged
  before the assignment). On failure `state` is left untouched. It is the only
  mutation path.
- Lookups by consumers are pure reads against `state`.
- Reset boundary: only on app restart (the provider is `keepAlive: true`).

Location: `lib/features/steam_publish/providers/published_subs_cache_provider.dart`.

### 2. Subscriber refresh service

A small helper that the cache notifier delegates to. It:

1. Reads `Project` and `Compilation` rows for the *currently selected game*
   from the existing repos and collects the non-empty `publishedSteamId`s into
   a deduped set.
2. Splits the set into chunks of ≤100 ids (Steam API limit, already enforced
   by `getMultipleModInfo`).
3. Calls `IWorkshopApiService.getMultipleModInfo(workshopIds: chunk, appId: 1142710)`
   per chunk, awaiting them sequentially (rate limiter is per-instance and
   already shared, so parallelism here would just queue up against itself).
4. Builds a `Map<String, int>` from each `WorkshopModInfo.workshopId` →
   `subscriptions ?? 0`. Items the API skipped (deleted/private mods) are
   simply absent from the map.
5. Returns the merged map; the notifier replaces `state` with it.

Errors (network, rate-limit, malformed response) are caught, logged via
`ILoggingService`, and result in the cache being left in its prior state. No
toast, no dialog — subs are ornamental.

Location: same file as the cache provider, as a private function.

### 3. Bootstrap integration — fold into existing scan dialog

The user requirement is explicit: **same popup as the mod scan, not a new one.**

`ModScanBootDialog` (`lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart`)
becomes a two-phase orchestrator:

- **Phase 1 — mod scan** (unchanged behaviour). The dialog watches
  `detectedModsProvider` until it resolves with a value or errors.
- **Phase 2 — subscriber refresh** (new). On phase-1 resolution, instead of
  closing the dialog immediately, the state advances to "fetching subs":
  - The terminal widget gets a final appended status line:
    `Refreshing subscriber counts for N published translations…`
    where `N` is the number of non-empty `publishedSteamId`s discovered.
    If `N == 0` (user has not published anything), phase 2 is skipped and the
    dialog closes immediately as before.
  - `await ref.read(publishedSubsCacheProvider.notifier).refreshFromWorkshop()`.
  - A second status line is appended on completion: `Done.` (or
    `Failed — subscriber counts unavailable.` on error). The dialog then
    closes via `addPostFrameCallback`.

Implementation: the dialog converts its current `ref.listen(detectedModsProvider, …)`
collapse-on-resolve into an explicit `_runPhases()` async sequence kicked off
in `initState`. The terminal continues to render the existing scan log stream;
the phase-2 status lines are emitted into a small `ValueNotifier<List<String>>`
displayed beneath the terminal (or, if cleaner, appended to the same log stream
via a small "publish subs" channel — the simpler `ValueNotifier` route is the
default unless we discover the scan terminal can't render an extra status line
without restructuring it).

Trade-off note: phase 2 lengthens the boot dialog by one batched HTTP call (≤1s
for the typical user; rate limiter caps at 100 ids per request, so a user with
≥101 published translations pays a multi-second wait). Acceptable because the
existing mod scan is already the slow part of bootstrap.

Caller (`main.dart`): no change beyond the existing
`await ModScanBootDialog.showAndRun(modScanContext, ref);` line — the dialog
encapsulates both phases internally.

### 4. List column — `SUBS` (left of `STATUS`)

`steamPublishColumns` in `lib/features/steam_publish/widgets/steam_publish_list_cells.dart`
gains one fixed-width column at index 3 (between title and status):

```
[checkbox · cover · title+filename · SUBS · STATUS · last published · action]
ListRowColumn.fixed(40),    // checkbox
ListRowColumn.fixed(80),    // cover
ListRowColumn.flex(3),      // title + filename
ListRowColumn.fixed(100),   // SUBS  ← new
ListRowColumn.fixed(160),   // status
ListRowColumn.fixed(180),   // last published
ListRowColumn.fixed(180),   // action
```

A new `SteamSubsCell extends ConsumerWidget` reads
`publishedSubsCacheProvider` and renders:

- `–` (faint mono) when `item.publishedSteamId` is null/empty (= unpublished).
- `–` when published but cache has no entry for this id (deleted/private mod
  on Steam, or fetch failed).
- The count formatted as `1 234` (mono, `tokens.textMid`) when the cache has a
  value. Same format helper as `mods_list.dart:392`
  (`NumberFormat('#,###', 'en_US').format(n).replaceAll(',', ' ')`).
- Tooltip: `'Workshop subscribers — last refreshed at app start.'`

The column header is added to the existing list header (same file/component
where the column titles live for the Publish list).

### 5. Toolbar leading — cumulative total

`SteamPublishToolbarLeading` already shows `total / filtered / selected /
search`. Append a `· N subs` segment **only when the sum is > 0**.

The sum is computed from the currently-filtered list
(`filteredPublishableItemsProvider`) by summing
`publishedSubsCacheProvider.state[item.publishedSteamId] ?? 0` across each
item. This is the right denominator: it tracks the user's filter (e.g. when
they filter to "Outdated", the cumulative total reflects what they're looking
at, not the global total).

Implementation: a new derived `riverpod` provider
`filteredPublishableItemsSubsTotal` watches both
`filteredPublishableItemsProvider` and `publishedSubsCacheProvider`, returns
an `int`, and is consumed by `SteamPublishToolbarLeading`.

Format: `12 items · 3 selected · 4 567 subs`. The `subs` segment is dropped
entirely (not shown as `0 subs`) when the sum is zero.

### 6. Refresh button behaviour

The existing toolbar Refresh button (`onRefresh`,
`steam_publish_screen.dart:107`) currently calls
`ref.invalidate(publishableItemsProvider)`. That stays as-is — refresh
re-reads the local DB but does **not** refetch subs.

This is consistent with the user requirement "OK pour pas de bouton 'Refresh
subs'": the only refresh point for subs is app restart.

## Data flow

```
App start
  └─ main._runStartupTasks
      └─ ModScanBootDialog.showAndRun
          ├─ Phase 1: detectedModsProvider
          │             ↓ writes
          │           detected_mods table (via existing scanner)
          └─ Phase 2: PublishedSubsCache.refreshFromWorkshop
                        ├─ reads projects + compilations from repos
                        ├─ collects unique publishedSteamIds
                        ├─ batches into chunks of ≤100
                        ├─ calls workshopApi.getMultipleModInfo per chunk
                        └─ replaces state with merged map

Steam Publish screen
  ├─ SteamSubsCell                 → reads cache.state[item.publishedSteamId]
  ├─ filteredPublishableItemsSubsTotal → sums cache.state across filtered list
  └─ SteamPublishToolbarLeading    → reads the sum, renders "· N subs" if > 0
```

## Error handling

| Case                                    | Behaviour                                                       |
|-----------------------------------------|-----------------------------------------------------------------|
| No game selected at boot                | `ModScanBootDialog.showAndRun` already returns early. No phase 2. |
| User has no published translations      | Phase 2 skipped (terminal shows no extra line). Dialog closes.  |
| Steam API timeout / network failure     | Logged. Cache untouched (= empty). Cells show `–`. No toast.    |
| Steam API rate-limit / 429              | Same as above. The rate limiter on `WorkshopApiServiceImpl` already throttles upstream, so a single boot call shouldn't trigger this. |
| Workshop id deleted/private             | Item simply absent from API response → cell shows `–`.          |
| App backgrounded for hours, comes back  | Cache is whatever it was at boot. No automatic re-fetch (by design). |

## Testing

- **Unit (cache provider):** stub `IWorkshopApiService.getMultipleModInfo`,
  call `refreshFromWorkshop()`, assert `state` matches expected map; assert
  errors leave prior state intact.
- **Unit (totals provider):** seed cache + filtered items, assert sum across
  representative cases (all published, mix, none, items missing from cache).
- **Widget (`SteamSubsCell`):** golden-style assertions for the three render
  paths (`–` unpublished, `–` cache miss, `1 234` populated).
- **Widget (`SteamPublishToolbarLeading`):** assert the `· N subs` segment
  appears iff sum > 0.
- **Boot dialog:** the existing dialog test is extended to assert the dialog
  stays open through phase 2 and closes after the cache populates; a fault-
  injection test asserts the dialog still closes on phase-2 failure.

No DB-level tests needed — no schema changes.

## Files touched

**New:**
- `lib/features/steam_publish/providers/published_subs_cache_provider.dart`

**Modified:**
- `lib/features/bootstrap/widgets/mod_scan_boot_dialog.dart` — add phase 2
- `lib/features/steam_publish/widgets/steam_publish_list_cells.dart` — add
  `SteamSubsCell`, update `steamPublishColumns`
- `lib/features/steam_publish/widgets/steam_publish_list.dart` — wire the new
  cell into the row builder + list header
- `lib/features/steam_publish/widgets/steam_publish_toolbar.dart` — append
  `· N subs` to `SteamPublishToolbarLeading`
- `lib/features/steam_publish/providers/steam_publish_providers.dart` — add
  `filteredPublishableItemsSubsTotal` derived provider

No changes to: schema.sql, repositories, models, main.dart.

## Open questions

None at design-approval time. The ValueNotifier-vs-scan-log-stream choice for
the phase-2 status lines is an implementation detail decided in the plan.
