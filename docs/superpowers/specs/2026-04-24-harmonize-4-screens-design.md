# Harmonize 4 Screens (Translation Editor / Compilation Editor / Publish on Steam / Projects)

Date: 2026-04-24
Scope: **Light harmonization only** — no redesign, no new visual language. The target screens already share the same token system and most list widgets; this spec captures the residual divergences and standardizes them.

## Scope & Non-Goals

**In scope (4 screens):**
- Translation Editor — `lib/features/translation_editor/screens/translation_editor_screen.dart`
- Compilation Editor — `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` (including its inner `compilation_project_selection.dart`)
- Publish on Steam — `lib/features/steam_publish/screens/steam_publish_screen.dart` (+ `steam_publish_toolbar.dart`)
- Projects — `lib/features/projects/screens/projects_screen.dart`

**Not in scope:**
- Compilation **list** screen (`pack_compilation_list_screen.dart`) — not one of the 4 targets.
- Any change to the overall design language, the token system, the wizard layout, or the SfDataGrid of the Translation Editor.
- Renaming `SEVERITY` → anything else (it is a distinct filter group and keeps its label).
- Changing `StickyFormPanel`'s default width (other wizard screens rely on 380).

## Decisions Summary

| # | Topic | Decision |
|---|-------|----------|
| 1 | Filter group title label | Use `STATE` everywhere. Translation Editor changes `STATUS` → `STATE`. |
| 2 | Filter selection model | Radio-like per group. Translation Editor moves from multi-select to single-select per group (STATUS and SEVERITY independently). |
| 3 | Search field width | `200px` in Translation Editor, Publish on Steam, Projects. Compilation editor's inner filter already at 200. |
| 4 | Compilation editor visuals | Inner "Select Projects" section uses the same button / search / row / thumbnail widgets as the Projects screen. |
| 5 | Compilation editor sidebar width | Pass `width: 240` to `StickyFormPanel` (default stays 380 globally). |
| 6 | Publish on Steam row height | Keep 56px. Align paddings / tokens / borders to match Projects' visual rendering. |
| 7 | Search position | In Publish on Steam and Projects, the search field is the last trailing element, placed to the right of all action buttons on the same row. |

## Section 1 — Filter Group Label

**Change:** `translation_editor_screen.dart:357` — string `'STATUS'` → `'STATE'`.

**Unaffected:** The second filter group `'SEVERITY'` keeps its label. Projects and Steam already use `'STATE'`.

## Section 2 — Radio-like Filters in Translation Editor

The two existing pill groups become single-select (per group, independent). Re-clicking the active pill deactivates it; clicking another pill replaces the current selection. Both groups may have an active value at the same time (they remain independent axes).

**Code impact (translation editor filter provider + screen):**
- `Set<TranslationVersionStatus> statusFilters` → `TranslationVersionStatus? statusFilter`.
- `Set<ValidationSeverity> severityFilters` → `ValidationSeverity? severityFilter`.
- `setStatusFilters(Set<...>)` → `setStatusFilter(TranslationVersionStatus?)` (same pattern for severity).
- Pill `onToggle`: `active ? null : pill.value` — mirrors Projects' `ProjectQuickFilter` toggle logic (`projects_screen.dart:153`).
- Filtering logic in the data source / query: replace `set.contains(row.status)` with `filter == null || filter == row.status`.

**Accepted UX trade-off:** Users lose the ability to select "Pending OR Translated" simultaneously in STATUS. Confirmed acceptable.

## Section 3 — Search Field Width (200px)

Three sites change from `ListSearchField()` (default 260) to `ListSearchField(width: 200)`:

- Translation Editor — `translation_editor_screen.dart:232` (inside FilterToolbar trailing).
- Publish on Steam — `steam_publish_toolbar.dart:90`.
- Projects — `projects_screen.dart` inside `_SearchField` wrapper (lines 484–502).

**Not changed:**
- `ListSearchField` default value stays at 260 (other screens, e.g. Compilation list, keep current behavior).
- Compilation editor's `_ProjectFilterField` (200 already) — replaced by `ListSearchField(width: 200)` under Section 4.

## Section 4 — Compilation Editor Visual Alignment with Projects

Target widget: `lib/features/pack_compilation/widgets/compilation_project_selection.dart`.

**Changes:**

4.1 **Buttons** — replace legacy `CompilationSmallButton` ("Select All", "Deselect All") with `SmallTextButton` (shared outlined variant, 28px height).

4.2 **Filter field** — replace legacy `_ProjectFilterField` (custom TextField) with `ListSearchField(width: 200, hintText: 'Search projects...')`, bound to the same `projectFilterProvider`.

4.3 **Project list rows** — replace the current ad-hoc list-tile styling with `ListRow` + `ListRowColumn`, following the column definition used by `_ProjectRow` in `projects_screen.dart:888`. The column shape is adapted to compilation's needs (not a copy):
- `fixed(80)` — cover thumbnail.
- `flex(3)` — project name + meta row.
- `fixed(56)` — selection checkbox cell (keeps existing include/exclude toggle).
  - Exact columns may be tuned during implementation; what matters is the use of `ListRow` + tokens instead of the current custom `Container` + ad-hoc `BoxDecoration`.

4.4 **Cover thumbnail** — extract the existing `_CoverThumbnail` from `projects_screen.dart` (private, lines 1160–1234) into a shared public widget: `lib/widgets/lists/project_cover_thumbnail.dart`. Both `projects_screen.dart` and `compilation_project_selection.dart` consume it. The widget accepts the same inputs it already uses (project entity + game installation context); no behavior change for Projects.

4.5 **Colors / radii** — swap `theme.colorScheme.*` and hard-coded `BorderRadius.circular(...)` for `context.tokens.*` and `tokens.radiusSm` / `radiusPill` as appropriate. This brings the section in line with the rest of the app.

**Out of scope for this section:** any change to filtering semantics (game/language selectors stay as they are), any change to the compilation editor's other sections (BBCode, output, conflicts panel).

## Section 5 — Compilation Editor Sidebar Width (240px)

`pack_compilation_editor_screen.dart` instantiates `StickyFormPanel(...)` inside `WizardScreenLayout`. Pass `width: 240` to that call site.

- **`StickyFormPanel` default stays 380**; other wizard consumers are untouched.
- **Risk:** the compilation editor's sticky form contains text fields (name, packName, prefix) + a `SummaryBox` + action buttons. At 240 the available inner width (after 24px padding on each side) is 192px — tight but workable, matching the translation editor's 240px sidebar which holds buttons only.
- **Mitigation:** during implementation, verify visually; if a label or field overflows, adjust horizontal padding or label text *but not* the 240px target. If a field cannot reasonably fit, raise the issue back to the author rather than silently inflating the width.

## Section 6 — Publish on Steam Row Visual Alignment

`ListRow` keeps `height = 56`. No structural change. Align the following to the Projects row rendering:

- Row padding (horizontal and vertical) — match Projects' `_ProjectRow` values.
- Selection highlight — same left accent border (2px) + `tokens.rowSelected` background.
- Column separators, typography (fontBody for primary, fontMono/textDim for meta).
- Hover color — `tokens.rowHover` (or whatever Projects uses) applied identically.

**Verification:** side-by-side visual comparison of a Steam row and a Projects row should show consistent padding, colors, and typography; only column content differs.

## Section 7 — Search Position in Toolbar

Both screens: the `FilterToolbar` `trailing` array is reordered so that `ListSearchField` is the **last** element (rightmost on the row).

**Projects** (`projects_screen.dart` lines 135–141):
- Before: `[_SearchField, _SortButton, _SelectionModeButton]`.
- After: `[_SortButton, _SelectionModeButton, _SearchField]`.

**Publish on Steam** (`steam_publish_toolbar.dart` lines 70–118):
- Before: `[SelectAll, SelectOutdated, ListSearchField, Sort, SortDir, Publish, Refresh, Settings]`.
- After: `[SelectAll, SelectOutdated, Sort, SortDir, Publish, Refresh, Settings, ListSearchField]`.

Implementation note: the `trailing` list lives in the `FilterToolbar` call; the move is a pure array reorder.

## Testing & Verification

This is a UI-only change. Verification plan:

1. **Static check** — `flutter analyze` passes.
2. **Type check & build** — `flutter build` (or `flutter run` on desktop) starts without error.
3. **Visual smoke test** — for each of the 4 screens, start the app, navigate, confirm:
   - Filter pill group title is `STATE` (where applicable).
   - Translation Editor pills behave as radio-like (clicking one replaces, re-clicking deselects).
   - Search field visibly narrower (200 vs previous 260) and positioned to the right of buttons in Projects & Steam.
   - Compilation editor's sidebar visibly narrower (240 vs previous 380) without field overflow.
   - Compilation editor's "Select Projects" section shows cover thumbnails, harmonized buttons, and a `ListSearchField`.
   - Publish on Steam rows visually match Projects rows (padding, hover, selection highlight).
4. **No regression** — Compilation list screen (out of scope) unchanged; other wizard screens using `StickyFormPanel` at 380 unchanged; existing filter behavior in Steam / Projects unchanged.

Unit tests are not required for this harmonization; existing filter-logic tests for the Translation Editor provider must be updated to reflect the single-value API.

## Risks & Open Questions

- **Sidebar at 240 in Compilation editor** — may feel cramped with text fields. Verified during implementation; fallback plan is label/padding adjustment, not width inflation.
- **Cover thumbnail extraction** — mechanical move from private to public widget. Signature must stay identical so Projects is a no-op change.
- **Translation Editor filter migration** — callers of the old `Set`-based API must all be updated (provider, screen pills, filter predicate). Grep-before-remove to ensure no stray call site remains.

## Out of Scope (explicit)

- Compilation list screen.
- Changing `ListSearchField` default width.
- Changing `StickyFormPanel` default width.
- Redesigning any component visual language.
- Adding new tokens, new widgets beyond the `ProjectCoverThumbnail` extraction.
- Renaming the `SEVERITY` group label. (Its selection model *does* change to single-select per Section 2 — it is a group like STATE, independently toggleable.)
