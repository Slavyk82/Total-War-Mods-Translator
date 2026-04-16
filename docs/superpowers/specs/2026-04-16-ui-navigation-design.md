# TWMT — UI redesign · Plan 2 · Navigation restructure — design spec

**Date:** 2026-04-16
**Status:** design · pending implementation plan
**Parent spec:** [`2026-04-14-ui-redesign-design.md`](2026-04-14-ui-redesign-design.md)
**Branch:** `feat/ui-navigation`
**Worktree:** `.worktrees/ui-navigation/`

---

## 1. Intent

Second of five staged plans. Restructure the navigation so it reflects the information architecture locked in the parent spec: five named groups in the sidebar, a nested URL scheme, and a reusable breadcrumb resolver.

This plan is an **invisible refactor from the user's perspective**. The existing screens keep their current look; only the sidebar and the breadcrumb bar change, plus all route paths are rewritten. Visual redesign of each screen's toolbar is the job of Plans 3–5.

**Non-goals**
- Redesigning any screen's content or toolbar layout.
- Fusing `Game Translation` and `Mods` into a single screen (see §11, interpretation γ).
- Adding collapsible sidebar groups or per-session UI state persistence.
- Deep-link redirects beyond a minimal legacy-URL compat layer.

---

## 2. Information architecture

Five groups, labels in English (parent spec §11 locks UI to EN-only for this redesign):

```
Brand
GameSelectorDropdown              (existing — kept as-is)

SOURCES
  ├── Mods                        → /sources/mods
  └── Game Files                  → /sources/game-files

WORK
  ├── Home                        → /work/home
  └── Projects                    → /work/projects
        ├── :projectId            → /work/projects/:projectId
        │     └── editor/:languageId
        └── batch-export          → /work/projects/batch-export

RESOURCES
  ├── Glossary                    → /resources/glossary
  └── Translation Memory          → /resources/tm

PUBLISHING
  ├── Pack Compilation            → /publishing/pack
  └── Steam Workshop              → /publishing/steam
        ├── single                → /publishing/steam/single
        └── batch                 → /publishing/steam/batch

SYSTEM
  ├── Settings                    → /system/settings
  └── Help                        → /system/help
```

**Root redirect:** `/` → `/work/home` via `GoRouter.redirect`.

**Fusion rationale (interpretation γ):** The parent spec §3 mentions a fusion of "Game Translation" and "Game Files". In the current codebase there is no separate "Game Files" screen — only `mods_screen.dart` (Workshop detection) and `game_translation_screen.dart` (base-game translation projects). We treat the parent spec's fusion as obsolete: `Mods` stays on its own, `game_translation_screen.dart` moves to `Sources / Game Files` with no content change. A future plan can revisit a raw-LOC-files mode if needed.

---

## 3. Routing

### 3.1 Route table

| Group | Screen | New path | Old path |
|---|---|---|---|
| Sources | Mods | `/sources/mods` | `/mods` |
| Sources | Game Files | `/sources/game-files` | `/game-translation` |
| Work | Home | `/work/home` | `/` |
| Work | Projects | `/work/projects` | `/projects` |
| Work | Project detail | `/work/projects/:projectId` | `/projects/:projectId` |
| Work | Editor | `/work/projects/:projectId/editor/:languageId` | `/projects/:projectId/editor/:languageId` |
| Work | Batch export | `/work/projects/batch-export` | `/projects/batch-export` |
| Resources | Glossary | `/resources/glossary` | `/glossary` |
| Resources | Translation Memory | `/resources/tm` | `/translation-memory` |
| Publishing | Pack Compilation | `/publishing/pack` | `/pack-compilation` |
| Publishing | Steam Workshop | `/publishing/steam` | `/steam-publish` |
| Publishing | Steam single | `/publishing/steam/single` | `/steam-publish/single` |
| Publishing | Steam batch | `/publishing/steam/batch` | `/steam-publish/batch` |
| System | Settings | `/system/settings` | `/settings` |
| System | Help | `/system/help` | `/help` |

### 3.2 Structural decisions

- **Single root `ShellRoute`** kept, as today. Groups are reflected in the URL only, not in the route tree. Nested `ShellRoute`s would add complexity with no visible gain (shared shell chrome is already handled by the root shell).
- **`AppRoutes` constants** are the single source of truth for paths. String literals get migrated to constants.
- **Legacy redirects:** top-level `GoRouter.redirect` maps every old path to its new counterpart. Kept short-term to cover any path that may have been persisted by the app (Windows shortcuts, user config, any cached state). Removable in a later cycle.
- **Unknown route** → existing `FluentErrorPage`, unchanged.

---

## 4. Component design

### 4.1 `NavigationTree` (data, pure)

**File:** `lib/config/router/navigation_tree.dart`

Single source of truth for sidebar structure *and* breadcrumb label resolution. Consumed by both widgets — no duplication.

```dart
class NavGroup {
  final String label;             // e.g. 'Sources'
  final List<NavItem> items;
  const NavGroup(this.label, this.items);
}

class NavItem {
  final String label;             // e.g. 'Mods'
  final String route;             // AppRoutes.mods
  final IconData icon;
  const NavItem(this.label, this.route, this.icon);
}

const List<NavGroup> navigationTree = [
  NavGroup('Sources', [
    NavItem('Mods', AppRoutes.mods, Icons.extension_outlined),
    NavItem('Game Files', AppRoutes.gameFiles, Icons.folder_outlined),
  ]),
  NavGroup('Work', [...]),
  NavGroup('Resources', [...]),
  NavGroup('Publishing', [...]),
  NavGroup('System', [...]),
];
```

Pure helper — no Flutter imports needed beyond `IconData`.

### 4.2 `NavigationTreeResolver` (pure helper)

**File:** `lib/config/router/navigation_tree_resolver.dart`

- `findActive(String path) → (NavGroup?, NavItem?)`: longest-`startsWith` match across the tree. Used by the sidebar to highlight the current item.
- `labelForSegment(String segment) → String?`: maps a single URL segment (`'sources'`, `'work'`, `'mods'`, `'projects'`, …) to its display label. Used by the breadcrumb for static segments.

Both functions are synchronous, side-effect free, fully unit-testable.

### 4.3 `NavigationSidebar` (new widget)

**File:** `lib/widgets/navigation/navigation_sidebar.dart`

Replaces `NavigationSidebarRouter`. Stateless `ConsumerWidget`. Reads `GoRouterState.of(context).uri.path`.

Structure:
```
Brand header                      (existing visual)
GameSelectorDropdown              (existing widget, unchanged)
──────────────────────────────
SOURCES                           (NavGroupHeader, caps-mono text-dim)
  • Mods                          (NavItemTile, active if startsWith match)
  • Game Files
──────────────────────────────
WORK
  …
──────────────────────────────
SidebarUpdateChecker              (existing, pinned bottom)
```

Visual rules:
- `NavGroupHeader`: `font-display` via tokens. Atelier = italic serif, Forge = uppercase letter-spaced. Text colour `text-dim`. Not interactive.
- `NavItemTile`: active = accent border-left + `accent-bg` background + accent fg; inactive = text colour, hover border → `text-dim`.
- **No hard-coded colours.** `context.tokens` only.
- No collapsible groups (keeps state simple, 10 items fit comfortably).

### 4.4 `Breadcrumb` (new widget)

**File:** `lib/widgets/navigation/breadcrumb.dart`

Stateless `ConsumerWidget`. Reads the current path, splits on `/`, resolves each segment:

| Segment type | Resolution |
|---|---|
| Static group (`sources`, `work`, `resources`, `publishing`, `system`) | `NavigationTreeResolver.labelForSegment` → `'Sources'` etc. |
| Static item (`mods`, `projects`, `glossary`, …) | Same resolver → `'Mods'` etc. |
| UUID (project id, matches `^[0-9a-f-]{36}$`) | Skipped (not rendered as a crumb; included only in the accumulated path for clickable navigation up) |
| Language id or unknown non-UUID segment | Rendered in `fontMono` + `textDim` as raw text (fallback) |
| Sub-route leaf (`editor`, `single`, `batch`, `batch-export`) | `labelForSegment` with dedicated entries |

Visual: chevrons in `text-dim` between segments, non-last segments `text-mid`, last segment `text` strong, per parent spec §6.8.

Consumed **by `MainLayoutRouter` for this plan** — the global breadcrumb bar stays in place above the content. Plans 3-5 will move it into each screen's toolbar, at which point `MainLayoutRouter` stops rendering it.

### 4.5 `AppRoutes` (refactor)

**File:** `lib/config/router/app_router.dart`

- All constants renamed to match new paths. Existing accessor pattern kept.
- New constant `AppRoutes.rootRedirect = '/work/home'`.
- Legacy-redirect table:
  ```dart
  static const Map<String, String> legacyRedirects = {
    '/': '/work/home',
    '/mods': '/sources/mods',
    '/game-translation': '/sources/game-files',
    '/projects': '/work/projects',
    '/glossary': '/resources/glossary',
    '/translation-memory': '/resources/tm',
    '/pack-compilation': '/publishing/pack',
    '/steam-publish': '/publishing/steam',
    '/settings': '/system/settings',
    '/help': '/system/help',
  };
  ```
  Wired via `GoRouter.redirect` with longest-prefix match so `/projects/abc/editor/fr` also redirects cleanly.

### 4.6 `MainLayoutRouter` (refactor)

**File:** `lib/widgets/layouts/main_layout_router.dart`

- Inline `_buildBreadcrumbs` + `_BreadcrumbItem` removed.
- Replace sidebar widget reference: `NavigationSidebar()` instead of `NavigationSidebarRouter()`.
- Replace breadcrumb inline with `const Breadcrumb()`.
- Everything else unchanged.

### 4.7 Deletions

- `lib/widgets/navigation_sidebar_router.dart` — replaced by new sidebar.
- `lib/widgets/navigation_sidebar.dart` (legacy index-based) — already stale, now dead.

---

## 5. Test plan

### 5.1 New unit tests

- `test/config/router/navigation_tree_resolver_test.dart`
  - `findActive`: every route resolves to correct `(group, item)`; sub-routes resolve to parent item; unknown path → `(null, null)`; longest-prefix wins.
  - `labelForSegment`: every known segment → label; unknown segment → `null`.

### 5.2 New widget tests

- `test/widgets/navigation/navigation_sidebar_test.dart`
  - Renders five group headers in correct order.
  - Renders `GameSelectorDropdown`.
  - Item is highlighted for each top-level path.
  - Item remains highlighted on sub-routes (e.g. `/work/projects/xyz`).
  - Clicking an item triggers `context.go` with the item's route.

- `test/widgets/navigation/breadcrumb_test.dart`
  - Static path `/sources/mods` → `Sources › Mods`.
  - Deep path with UUID `/work/projects/<uuid>/editor/fr-FR` → `Work › Projects › Editor` (UUID skipped, language id rendered as mono fallback).
  - Unknown segment → mono text-dim fallback, no crash.
  - Tapping a non-last crumb navigates to its accumulated path (spy via `onCrumbTap`).

### 5.3 New router tests

- `test/config/router/app_router_test.dart`
  - `/` redirects to `/work/home`.
  - Each legacy URL (`/mods`, `/game-translation`, `/projects/abc`, `/projects/abc/editor/fr`, `/glossary`, etc.) resolves to its new equivalent.
  - New URLs route to the expected screen widget.
  - Unknown URL → `FluentErrorPage`.

### 5.4 Existing tests impact

- Zero router-layer tests today → no regressions from restructuring itself.
- 4 screen-isolation tests mention sidebar labels (`mods_screen_test`, `projects_screen_test`, `game_translation_screen_test`, `help_screen_test`) — none of them navigate via router or reference route constants. No updates expected.
- `test/widget_test.dart` (smoke): verify boot with new routes.

### 5.5 Baseline expectation

- Plan 1 baseline: **1165 passing / 30 failing** (pre-existing failures documented in `project_refactoring_progress`). New tests are expected to land on top without touching the 30 failures.

---

## 6. Migration plan (high-level ordering)

Detailed by the implementation plan (next step). Sketch:

1. **`NavigationTree` data + `NavigationTreeResolver`** + unit tests. No wiring yet.
2. **`Breadcrumb` widget** + tests. Render in isolation.
3. **`NavigationSidebar` widget** + tests. Render in isolation.
4. **New `AppRoutes` constants** + legacy redirect table + router tests. Existing screens still wired to old paths — routes resolve both.
5. **Literal path migration** across `lib/` and `test/`. Single commit, mechanical.
6. **`MainLayoutRouter` wiring:** switch to new sidebar + new breadcrumb. Delete legacy sidebar files.
7. **Manual smoke test** (`flutter run -d windows`): navigate through every new URL + every legacy URL redirect; confirm no regression in screens.
8. **Tests green** + **no new `dart analyze` warnings**.

---

## 7. Scope

**In scope**
- New 5-group `NavigationSidebar` widget (replaces legacy).
- `NavigationTree` + resolver (shared data for sidebar + breadcrumb).
- Reusable `Breadcrumb` widget (consumed by `MainLayoutRouter` this plan).
- Full route-path rename to nested URLs with `AppRoutes` constants.
- Legacy-URL redirect compat layer.
- Tests for sidebar, breadcrumb, and router behaviour.

**Out of scope**
- Screen-level toolbar redesign (Plans 3-5).
- Moving the breadcrumb into per-screen toolbars (Plans 3-5).
- Sidebar collapsibility or persisted UI state.
- Game-files fused mode (§11 γ, revisited later if needed).
- Localization or non-EN sidebar labels.

---

## 8. Open questions

None at design time. All decisions made during brainstorming:
- Sidebar labels: EN.
- URL structure: nested by group.
- Breadcrumb: global (MainLayoutRouter) for now, extracted as reusable widget for future plans.
- Fusion: none (interpretation γ).
- Game switcher: existing `GameSelectorDropdown` unchanged.
