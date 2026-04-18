# Clickable crumbs in detail/wizard toolbars

Status: draft
Owner: Slavyk
Date: 2026-04-18

## Context

`DetailScreenToolbar` (lib/widgets/detail/detail_screen_toolbar.dart) renders a
single `String crumb` in a `Text` widget — e.g. `Work › Projects › MyMod ›
English`. Nothing is clickable today. A user sitting in the translation editor
cannot jump back to the project detail or the projects list from the toolbar;
the only affordance is the back arrow (one step) or the sidebar.

The infrastructure for click resolution already exists in
`NavigationTreeResolver` (`defaultRouteForGroupSegment`, `labelForSegment`),
with a comment explicitly stating it was meant for clickable breadcrumbs.

## Goal

Make every crumb segment that is **neither the first nor the last** clickable,
navigating to the corresponding route. The current (last) segment is rendered
in bold so the user sees where they are.

Applies to all five detail/wizard screens:

- `project_detail_screen.dart`
- `translation_editor_screen.dart`
- `glossary_screen.dart`
- `pack_compilation_editor_screen.dart`
- `workshop_publish_screen.dart` (single + empty-state cases)
- `batch_workshop_publish_screen.dart` (batch + empty-state cases)

## Non-goals

- No refactor of `NavigationTreeResolver`. Routes are supplied by the caller,
  not parsed from strings. The resolver stays as-is for sidebar use.
- No change to the back arrow behaviour.
- No change to the sidebar or global layout.
- No new "home" crumb or omission of group segment — the first segment stays
  visible, just non-clickable.

## Design

### Data model

New value type, colocated with `DetailScreenToolbar`:

```dart
class CrumbSegment {
  final String label;
  final String? route; // null → non-clickable
  const CrumbSegment(this.label, {this.route});
}
```

`route == null` ⇒ rendered as plain text. `route != null` ⇒ rendered with
pointer cursor, underline on hover, tap handler.

### Widget API change

```dart
// before
DetailScreenToolbar({ required String crumb, ... })

// after
DetailScreenToolbar({ required List<CrumbSegment> crumbs, ... })
```

Breaking change — all five callers updated in the same PR.

### Rendering

- Horizontal row of segments, auto-interspersed with a `›` separator (U+203A).
  The existing toolbars mix `›` and `>`; normalise on `›` as part of this
  change.
- Base style: unchanged — `fontMono` 12px, letterSpacing 0.5.
- **Non-clickable (first segment):** `color: tokens.textDim`, regular weight.
- **Clickable middle segments:** `color: tokens.textDim`, regular weight,
  `MouseRegion(cursor: SystemMouseCursors.click)`, underline on hover only
  (via a local `StatefulWidget` or `HoverBuilder`-style helper).
- **Last segment (current):** `color: tokens.text`, `FontWeight.w600`, no
  underline, no pointer.
- Separators: unchanged style — `fontMono` with `tokens.textFaint`.
- `Expanded` wrapper keeps ellipsis behaviour overall; individual segments
  stay on one line and the row ellipsises at the end if too long (acceptable
  since the last segment is the most context-rich and bold; truncating the
  start is worse UX).

### Click handling

On tap of a clickable segment:

1. Check navigation guards (same rules as `MainLayoutRouter._canNavigate`):
   - if `translationInProgressProvider` → show "Translation in progress"
     toast and abort.
   - if `compilationInProgressProvider` → show "Pack generation in progress"
     toast and abort.
2. Otherwise `context.go(segment.route!)`.

Extract the guard into a shared helper rather than duplicating it. Candidate
location: `lib/config/router/navigation_guard.dart` with a function
`bool canNavigateNow(BuildContext, WidgetRef)` that encapsulates the provider
reads + toast. Update `MainLayoutRouter` to call it too so there's a single
source of truth.

The toolbar needs a `WidgetRef`, so either:

- change `DetailScreenToolbar` to a `ConsumerWidget`, or
- expose an `onNavigate: ValueChanged<String>?` callback that screens wire up
  using their already-available `ref`.

Preferred: make `DetailScreenToolbar` a `ConsumerWidget`. The guard is
cross-cutting; threading a callback through every caller is just boilerplate.

### Callers — crumb lists

All routes below are from `AppRoutes`. `⊘` = non-clickable (first or last).

- **Project detail** (`project_detail_screen.dart`):
  - `[ (Work, ⊘), (Projects, /work/projects), (${p.name}, ⊘) ]`
- **Translation editor** (`translation_editor_screen.dart`):
  - `[ (Work, ⊘), (Projects, /work/projects), (${projectName}, /work/projects/${projectId}), (${languageName}, ⊘) ]`
- **Glossary detail** (`glossary_screen.dart`):
  - `[ (Resources, ⊘), (Glossary, /resources/glossary), (${glossary.name}, ⊘) ]`
- **Pack compilation editor** (`pack_compilation_editor_screen.dart`):
  - `[ (Publishing, ⊘), (Pack compilation, /publishing/pack), (name-or-"New", ⊘) ]`
- **Workshop publish single** (`workshop_publish_screen.dart`):
  - `[ (Publishing, ⊘), (Steam Workshop, /publishing/steam), (${projectName or "No pack staged"}, ⊘) ]`
- **Workshop publish batch** (`batch_workshop_publish_screen.dart`):
  - `[ (Publishing, ⊘), (Steam Workshop, /publishing/steam), (Batch (${n} packs) or "No items staged", ⊘) ]`

Two-segment crumbs (group + current) don't exist in this set. If they appear
later, the rule "all-except-first-and-last" yields zero clickable segments,
which is correct.

## Testing

Extend `test/widgets/detail/detail_meta_banner_test.dart` (or add a new
`detail_screen_toolbar_test.dart` — the toolbar has no dedicated file yet;
add one):

- Renders N segments with `›` separators between them.
- First segment has no pointer cursor, no underline on hover, non-bold.
- Middle segments have pointer cursor, underline visible on hover, tap
  triggers navigation.
- Last segment is bold, no pointer.
- Navigation guard: with `translationInProgressProvider` overridden to
  `true`, tapping a middle segment emits the warning toast and does **not**
  call `context.go`.

Update existing callers' widget tests that assert on the crumb text — they
currently expect the full string; switch to checking for the last segment
(bold) and that intermediate segment labels are present.

## Migration notes

- Delete the `String crumb` field and its references.
- No data migration; pure UI change.
- No impact on `NavigationTreeResolver` — the resolver methods keep their
  existing contract.

## Open questions

None at spec time.
