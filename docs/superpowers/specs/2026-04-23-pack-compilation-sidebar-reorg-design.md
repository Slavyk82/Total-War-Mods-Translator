# Pack Compilation — sidebar reorganization

**Date:** 2026-04-23
**Status:** Approved
**Area:** `lib/features/pack_compilation/` + `lib/widgets/wizard/`

## Problem

The "Pack Compilation" editor stacks three sections vertically inside the wizard's dynamic zone:

1. Select Projects (primary action)
2. Conflicting Projects (advisory, only visible with 2+ projects + language)
3. Steam Workshop BBCode (advisory, only visible when any project is selected)

With both advisory panels stacked below the selection list, the primary list is cramped (fixed 420 px) and the user must scroll past it to see BBCode output. The conflicts panel is the advisory users need to glance at *while* choosing projects — stacking it below defeats that.

## Goal

- Free up the dynamic zone for the project selection list (primary).
- Put advisory/output panels in dedicated side areas:
  - **Conflicting Projects → right sidebar** (companion to selection; visible alongside the list).
  - **Steam Workshop BBCode → left sidebar** (grouped with the other meta/output fields).

## Non-Goals

- No behavioral changes to conflict analysis, BBCode generation, or compile flow.
- No changes to the compiling view (log terminal + progress card stays unchanged).
- No redesign of the individual panels — only their placement.

## Design

### Layout changes

Current `WizardScreenLayout`:

```
┌─ toolbar ────────────────────────────────────────────┐
│                                                      │
├────────┬─────────────────────────────────────────────┤
│ sticky │ dynamic zone (Column):                      │
│ form   │   - Project selection (h=420)               │
│ panel  │   - Conflicting Projects (h=240) (cond.)    │
│ (380)  │   - BBCode section (cond.)                  │
└────────┴─────────────────────────────────────────────┘
```

New `WizardScreenLayout`:

```
┌─ toolbar ────────────────────────────────────────────────────┐
│                                                              │
├────────┬─────────────────────────────────────┬───────────────┤
│ sticky │ dynamic zone:                       │  right panel  │
│ form   │   - Project selection (expanded)    │  (380, opt.)  │
│ panel  │                                     │  Conflicting  │
│ (380)  │                                     │  Projects     │
│ + BB-  │                                     │  (cond.)      │
│ Code   │                                     │               │
└────────┴─────────────────────────────────────┴───────────────┘
```

### Widget changes

**`lib/widgets/wizard/wizard_screen_layout.dart`**
- Add optional `Widget? rightPanel` parameter.
- When non-null, render it as the third child of the Row (after the dynamic zone). When null, dynamic zone expands as today.

**`lib/widgets/wizard/sticky_form_panel.dart`**
- Add optional `Widget? extras` parameter, rendered below the action buttons inside the same `SingleChildScrollView` column.
- Rationale for a dedicated slot (vs. reusing `FormSection`): BBCode is a 200-px-tall scrollable text area with its own card styling, not a label+field row. A `FormSection` would force an awkward nesting of two card borders.

**`lib/widgets/wizard/right_sticky_panel.dart` (new)**
- Mirrors `StickyFormPanel` visual treatment: fixed-width pane (default 380), left hairline border (vs. right on the left panel), internal vertical scroll. Takes a `List<Widget> children`.
- A new widget rather than reusing `StickyFormPanel` because the form panel carries form-specific props (sections / summary / actions) that aren't relevant to a right-hand advisory pane.

**`lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart`**
- In `_PackCompilationEditorScreenState.build`:
  - Compute `showConflicts = state.selectedProjectIds.length >= 2 && state.selectedLanguageId != null` at the top.
  - Pass `CompilationBBCodeSection()` into `StickyFormPanel.extras` (unchanged — it already self-hides when no projects are selected).
  - Pass `RightStickyPanel(children: [ConflictingProjectsPanel(...)])` into `WizardScreenLayout.rightPanel` only when `showConflicts` is true. Otherwise omit.
- `_EditingView` is simplified to: optional success banner + `Expanded(child: CompilationProjectSelectionSection(...))`. Remove the `SizedBox(height: 420)` wrapper — the selection list fills the dynamic zone.
- Remove the old `if (showConflicts)` and `if (hasSelection)` sub-trees (moved to sidebars).

### Conditional visibility

| Condition | Left `extras` (BBCode) | Right panel (Conflicts) |
|---|---|---|
| No projects selected | hidden (self) | omitted |
| 1 project selected | visible | omitted |
| 2+ projects, no language | visible | omitted |
| 2+ projects + language | visible | visible |

When the right panel is omitted, the dynamic zone (project selection) gets the reclaimed width.

### BBCode in a 380-px column

The section already uses `maxHeight: 200` + `SingleChildScrollView` + `SelectableText` — it fits a narrow column. The Copy button stays in the header row. No width-specific tweaks required.

### Compiling view

During compilation, the right sidebar should disappear so the progress card + log terminal can use the full dynamic width. Implementation: `rightPanel` is computed based on `!state.isCompiling && showConflicts`. The `extras` BBCode section stays — it provides useful links once a pack has been built.

## Architecture & Testing

**Isolation:** The three widget changes are decoupled.
- `WizardScreenLayout` and `StickyFormPanel` gain additive optional params (backward compatible with other callers).
- `RightStickyPanel` is new and self-contained.
- `PackCompilationEditorScreen` is the only consumer touching all three.

**Testing:**
- Manual smoke test in `flutter run -d windows`: empty state, 1 project, 2+ projects with/without language, during compilation, and post-compile success.
- Check other `WizardScreenLayout` consumers still render unchanged (additive param, so no compile-time break).

## Risks

- **Panel width in narrow windows.** With two 380-px sidebars + a dynamic zone, the minimum usable width is ~1000 px. The app is Windows desktop; current behavior already assumes a wide window. No responsive fallback planned — document as known limitation if needed.
- **`StickyFormPanel.extras` + BBCode scroll.** The form panel is a `SingleChildScrollView` + column; BBCode's inner `SingleChildScrollView` (maxHeight 200) nests fine because the outer scroll view never reaches the BBCode's content (bounded height). Verified by inspection, not tested.
