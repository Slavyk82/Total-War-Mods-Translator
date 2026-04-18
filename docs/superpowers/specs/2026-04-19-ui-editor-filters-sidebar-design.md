# Translation Editor — filters as pills, actions in sidebar

**Date:** 2026-04-19
**Scope:** Rework `TranslationEditorScreen` layout to match the `§7.1 Filterable list` archetype shipped on the Projects screen. Filters move out of the left sidebar and into a `FilterToolbar` above the body. The left sidebar is repurposed to host every control previously in `EditorActionBar` (search, model/context toggles, action buttons, settings).

## 1. Motivation

The editor currently splits controls in a way that no longer matches the rest of the app:

- Filters live in a custom left panel (checkbox-style, with Status + TM source groups + a "Clear filters" button). This is the only screen still doing that after Plan 5a shipped pill-based filters everywhere.
- Actions live in a dense 56 px top bar (`EditorActionBar`) that stacks a model selector, a skip-TM toggle, a Rules chip, 4 action buttons (Selection · Translate all · Validate ▾ · Pack ▾), a Settings icon and a search field. At 1600 px and below it has to shrink labels and horizontally scroll.

Moving to the §7.1 archetype brings two wins: filters look and behave exactly like everywhere else (Projects / Mods / Steam Publish / Glossary / TM), and the action bar decomposes into a readable vertical column that no longer has to fight for horizontal space.

## 2. User-visible shape (top to bottom)

```
┌─────────────────────────────────────────────────────────────┐
│ DetailScreenToolbar   ← back + crumb + NextStepCta          │  (unchanged)
├─────────────────────────────────────────────────────────────┤
│ FilterToolbar row 1 (48 px)   📁 <project name>             │  NEW
│ FilterToolbar row 2 (40 px)   STATUS [pills]  TM SOURCE […] │  NEW
├──────────────┬──────────────────────────┬───────────────────┤
│ Sidebar 240  │   EditorDataGrid         │ EditorInspector   │
│ (actions)    │                          │       320         │
├──────────────┴──────────────────────────┴───────────────────┤
│ EditorStatusBar (28 px)                                      │  (unchanged)
└─────────────────────────────────────────────────────────────┘
```

The editor keeps its stacked header (`DetailScreenToolbar` above the new filter toolbar) and its status bar. The middle body keeps the three-panel row (sidebar · grid · inspector) but the left panel's content is entirely rebuilt.

## 3. Filter toolbar (new)

Reuses `lib/widgets/lists/filter_toolbar.dart` as-is — same `FilterToolbar` / `FilterPillGroup` / `FilterPill` primitives used on the Projects screen. No new list primitive is introduced.

### 3.1 Leading

`ListToolbarLeading(icon: FluentIcons.folder_24_regular, title: <projectName>)`. No count (unit counts already live in `EditorStatusBar`). Project name is pulled from `currentProjectProvider(projectId)` exactly as the screen already does.

### 3.2 Trailing

Empty list (the toolbar has no trailing slot widgets on this screen — search moves to the sidebar).

### 3.3 Pill groups

Two groups, laid out identically to Projects:

**STATUS** (label `STATUS`)
- Pending · Translated · Needs review (3 pills)
- Each pill shows its count via `FilterPill.count`, sourced from `editorStatsProvider(projectId, languageId)` — same provider the ex-panel used.
- `onClear` clears the 3-status set on `editorFilterProvider`.
- No coloured status dot on the pill — matches Projects' visual grammar strictly. Selection state uses the pill's own accent.

**TM SOURCE** (label `TM SOURCE`)
- Exact match · Fuzzy match · LLM · Manual · None (5 pills)
- No `count` (no provider today — same as the ex-panel).
- `onClear` clears the tm-source set on `editorFilterProvider`.

The old global `_ClearFiltersButton` in `EditorFilterPanel` is removed. Each group's terminator clear pill handles its own reset, matching Projects.

### 3.4 Provider wiring

No changes to `editorFilterProvider` — the same `setStatusFilters` / `setTmSourceFilters` / `clearFilters` API is called from the new pill toggles. `editorFilterProvider.hasActiveFilters` stays in place (still used by the screen to gate other behaviours).

## 4. Left sidebar (replaces `EditorFilterPanel`)

A new widget `EditorActionSidebar` replaces the file at `lib/features/translation_editor/widgets/editor_filter_panel.dart`. It is renamed to `editor_action_sidebar.dart` to reflect the new role. The panel shell (`Container` 240 px wide, `tokens.panel` background, right `tokens.border`, `SingleChildScrollView` with 18 px vertical / 16 px horizontal padding) stays structurally similar.

Width grows from 200 px to **240 px**.

The section header primitive (`_SectionHeader`) used in the ex-filter panel is preserved (caps-italic accent label + gradient rule) and reused for all sections below, to keep the visual grammar continuous.

### 4.1 § SEARCH

- Full-width `TokenTextField` (primitive already in `lib/widgets/wizard/token_text_field.dart`), hint `Search · filter · run`, `fontMono` style.
- 200 ms debounce on change, writing to `editorFilterProvider.setSearchQuery` (moved from `_EditorActionBarState`).
- `FocusNode` owned by the sidebar state. `Ctrl+F` shortcut continues to request focus on this field — the Actions/Shortcuts map on the screen now points to the sidebar's focus node instead of the ex-top-bar one.

### 4.2 § CONTEXT

Three existing widgets, each wrapped to take the full sidebar width. All three already expose a `compact: true` flag from Plan 4, which we set.

- `EditorToolbarModelSelector(compact: true)`
- `EditorToolbarSkipTm(compact: true)`
- `EditorToolbarModRule(compact: true, projectId: widget.projectId)`

These are placed in a `Column(crossAxisAlignment: stretch)` so they expand horizontally to 208 px (240 − 2×16 padding). Spacing between them is 10 px.

### 4.3 § ACTIONS

Six entries, in order. Primary buttons are full-width `_SidebarActionButton`s (new private widget in the sidebar file, derived from the ex-`_ActionButton` of `editor_action_bar.dart`). Secondary entries use `SmallTextButton` so they read as a ligne secondaire under their primary.

Layout:

1. **Translate all** — full-width primary (`tokens.accent` background, `tokens.accentFg` foreground), icon `FluentIcons.translate_24_regular`. Shortcut `Ctrl+T`.
2. **Selection** — full-width secondary, icon `FluentIcons.translate_24_filled`. Disabled when `editorSelectionProvider.selectedCount == 0`. Shortcut `Ctrl+Shift+T`.
3. 8 px gap.
4. **Validate selected** — full-width secondary, icon `FluentIcons.checkmark_circle_24_regular`. Shortcut `Ctrl+Shift+V`.
5. **Rescan all** — `SmallTextButton`, centered or leading-aligned to match the parent button's text alignment. No shortcut.
6. 8 px gap.
7. **Generate pack** — full-width secondary, icon `FluentIcons.box_24_regular`.
8. **Import pack** — `SmallTextButton`.

The 3 split-buttons of the old action bar are decomposed into 6 explicit rows (3 primary + 3 secondary-style `SmallTextButton`). No `PopupMenuButton` / chevron dropdown anywhere in the sidebar.

`_SidebarActionButton` dimensions: 36 px height, radius `tokens.radiusSm`, padding horizontal 12 px, leading icon 14 px, label `fontBody` 12.5 px weight 500.

### 4.4 § SETTINGS

Single full-width `_SidebarActionButton` labelled `Translation settings`, icon `FluentIcons.settings_24_regular`, secondary styling. Calls the same `onTranslationSettings` handler as today.

## 5. Screen glue (`TranslationEditorScreen`)

Changes in `translation_editor_screen.dart`:

1. Remove the `EditorActionBar` widget from the `Column` children.
2. Insert a `FilterToolbar` between `DetailScreenToolbar` and the body `Expanded(Row(...))`, configured per §3.
3. Replace `EditorFilterPanel(...)` with `EditorActionSidebar(...)` in the body `Row`. Props unchanged in spirit (projectId / languageId / all the `onXxx` callbacks that were passed to the old action bar — they now arrive at the sidebar instead).
4. Shortcuts (`Ctrl+F` / `Ctrl+T` / `Ctrl+Shift+T` / `Ctrl+Shift+V`) stay wired at screen scope (unchanged from the Plan 4 lift). The `Ctrl+F` target focus node is exposed via a `GlobalKey<State>` on the sidebar or via a `FocusNode` owned by the screen and handed down — we pick whichever is cleanest against the existing `translation_editor_actions.dart` plumbing; an implementation detail.

All the `TranslationEditorActions` handlers (`handleTranslateAll`, `handleTranslateSelected`, `handleValidate`, `handleRescanValidation`, `handleExport`, `handleImportPack`, `handleTranslationSettings`) stay unchanged — only the widget that invokes them moves.

## 6. Files touched

**Added**
- `lib/features/translation_editor/widgets/editor_action_sidebar.dart` (new, replaces the ex-filter panel file).
- `test/features/translation_editor/widgets/editor_action_sidebar_test.dart` (new).

**Deleted**
- `lib/features/translation_editor/widgets/editor_filter_panel.dart`
- `lib/features/translation_editor/widgets/editor_action_bar.dart`
- `test/features/translation_editor/widgets/editor_filter_panel_test.dart`
- `test/features/translation_editor/widgets/editor_action_bar_test.dart`

**Modified**
- `lib/features/translation_editor/screens/translation_editor_screen.dart` (insert `FilterToolbar`, swap panel, drop `EditorActionBar` import).
- `test/features/translation_editor/screens/translation_editor_screen_test.dart` (assert new layout).
- Editor goldens (4 files under `test/features/translation_editor/screens/goldens/` or similar — regenerate per existing convention: 2 themes × 2 states).

**Untouched**
- `EditorToolbarModelSelector`, `EditorToolbarSkipTm`, `EditorToolbarModRule` (reused with `compact: true`).
- `EditorDataGrid`, `EditorInspectorPanel`, `EditorStatusBar`.
- `DetailScreenToolbar`, `NextStepCta`.
- All editor providers (`editorFilterProvider`, `editorSelectionProvider`, `editorStatsProvider`, `translationSettingsProvider`, `currentProjectProvider`, `currentLanguageProvider`).
- `TranslationEditorActions`.

## 7. Tests

### 7.1 `editor_action_sidebar_test.dart` (replaces filter panel test)

- Renders `§ SEARCH · CONTEXT · ACTIONS · SETTINGS` headers.
- Typing in the search field debounces and writes to `editorFilterProvider.searchQuery`.
- Each action button invokes the correct callback. `Selection` is disabled with `onTap == null` when `editorSelectionProvider.selectedCount == 0`.
- `Rescan all` and `Import pack` (secondary rows) invoke their callbacks.

### 7.2 `translation_editor_screen_test.dart` (updated)

- Asserts the presence of `FilterToolbar` between `DetailScreenToolbar` and the body Row.
- Asserts `EditorActionSidebar` is the leftmost panel at 240 px.
- Asserts `EditorActionBar` is no longer in the tree.
- Verifies `Ctrl+F` focuses the sidebar's search field.

### 7.3 New filter-toolbar interaction test

A small widget test (co-located in `editor_action_sidebar_test.dart` or a dedicated `editor_filter_toolbar_test.dart`) that:

- Renders the screen with a stub project.
- Taps a `STATUS · Pending` pill and asserts `editorFilterProvider.statusFilters` now contains `pending`.
- Taps the group's clear pill and asserts the set is empty.

### 7.4 Goldens

Regenerate the 4 editor goldens (2 themes × empty/populated states) to capture the new stacked header + sidebar layout. Thresholds unchanged.

## 8. Out of scope / follow-ups

- **`Fichier loc` pill group** — still deferred (no provider to enumerate loc files per project). Tracked in Plan 4 follow-ups.
- **`Ctrl+K` command palette** — deferred, unchanged from Plan 4.
- **Token/cost tracker in status bar** — deferred, unchanged.
- **Status dot a11y** — dot is removed from the new pills entirely, so the a11y follow-up from Plan 4 (`Semantics` wrapper on `StatusCellRenderer`) is orthogonal and stays open.
- **Settings retokenisation sweep** — already done in Plan 5e, not touched here.

## 9. Risks

- **`EditorToolbarModRule` rendering at full width** — the widget is currently shown in a horizontally scrolling row. In a 208 px vertical slot it must wrap/ellipsize the rule name gracefully. Mitigation: the `compact: true` branch already uses a short label; if not, a width constraint + `TextOverflow.ellipsis` in our wrapper covers it.
- **`SmallTextButton` visual weight for secondary actions** — `Rescan all` and `Import pack` read as tertiary but are real actions. If users miss them we can promote to a `_SidebarActionButton` with no icon and lower padding in a follow-up.
- **Search focus hand-off** — the `Ctrl+F` shortcut today targets the top-bar search. Moving the field without re-wiring the intent would silently break the shortcut. Mitigation: the screen-scope `Actions` map must point at the new focus node; covered by §7.2.
