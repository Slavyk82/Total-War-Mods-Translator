# Home back-toolbar on top-level screens

**Status:** approved
**Date:** 2026-04-25

## Goal

Add a thin top toolbar on every top-level screen reachable from the sidebar,
in the visual style of the editor's `DetailScreenToolbar`: a back arrow on
the left and the screen identity (icon + title + count) right next to it.
The back arrow returns to the Home screen. The screen identity moves UP from
each screen's secondary toolbar — so the title is no longer duplicated below.

This gives users an explicit "go back to Home" affordance on every screen,
even though the sidebar already exposes Home — the discoverable back arrow
matches the chrome rhythm of the editor.

**Iteration history:**
- v1: proposed a `Home › <Screen>` breadcrumb. Rejected as redundant with
  the screen titles already shown below.
- v2: only the back arrow. Rejected as too sparse.
- v3 (current): back arrow + the screen's icon/title/count moved up from
  the secondary toolbar's leading slot.

## Scope

Eight screens get the toolbar, with the icon+title relocated from their
existing secondary toolbar:

| Screen              | Icon                              | Title                |
|---------------------|-----------------------------------|----------------------|
| Mods                | `cube_24_regular`                 | `Mods`               |
| Projects            | `folder_24_regular`               | `Projects`           |
| Publish (Steam)     | `cloud_arrow_up_24_regular`       | `Publish on Steam`   |
| Glossary            | `book_24_regular` (newly added)   | `Glossary`           |
| Translation Memory  | `database_24_regular`             | `Translation Memory` |
| Game Files          | `globe_24_regular`                | `Game Translation`   |
| Compile             | `archive_multiple_24_regular`     | `Pack compilations`  |
| Settings            | `settings_24_regular`             | `Settings`           |

The Home screen itself is not modified (no need for a back button there). The
translation editor and other detail/sub-screens keep their existing toolbars.

## Non-goals

- The sidebar is not modified.
- The translation editor's existing 3-segment crumb (`Work › Projects › <name>`)
  is not changed.
- Sub-screens like `BatchPackExportScreen`, `WorkshopPublishScreen`,
  `BatchWorkshopPublishScreen`, `PackCompilationEditorScreen` are out of scope.

## Architecture

### `HomeBackToolbar`

File: `lib/widgets/detail/home_back_toolbar.dart`

A small `ConsumerWidget` rendering a 48 px bar with the back arrow on the
left and an optional `leading` widget (typically a `ListToolbarLeading`)
right next to it.

```dart
class HomeBackToolbar extends ConsumerWidget {
  final Widget? leading;

  const HomeBackToolbar({super.key, this.leading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l = leading;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          SmallIconButton(
            icon: FluentIcons.arrow_left_24_regular,
            tooltip: 'Back',
            onTap: () {
              if (canNavigateNow(context, ref)) {
                context.go(AppRoutes.home);
              }
            },
          ),
          if (l != null) ...[
            const SizedBox(width: 12),
            Expanded(child: l),
          ],
        ],
      ),
    );
  }
}
```

The widget intentionally builds its own 48 px container rather than wrapping
`DetailScreenToolbar` because the editor's toolbar is a crumb-trail layout
and forcing a foreign `leading` slot through the `crumbs` parameter would be
semantically wrong.

### Navigation behaviour

- The back arrow calls `context.go(AppRoutes.home)`, **not** `context.pop()`.
  These screens are typically reached via the sidebar (`context.go`), so
  `canPop()` returns `false` in the common case. Using `go` is deterministic.
- The call is wrapped in `canNavigateNow(context, ref)` so an in-progress
  translation or pack compilation blocks the back navigation with the existing
  warning toast.

### Per-screen integration

For the five screens already on the `FilterToolbar` archetype (Mods, Projects,
Steam Publish, Translation Memory, Pack Compilation):

- The screen builds a `ListToolbarLeading` (icon + title + count, optionally
  with status pills) and passes it to `HomeBackToolbar.leading`.
- The same screen's `FilterToolbar.leading` is replaced by
  `const SizedBox.shrink()` with `expandLeading: false` so the trailing slot
  (search field + actions) keeps stretching as before.
- For Mods and Steam Publish, the previously-private `_Leading` /
  `_PendingProjectsBanner` widgets in `mods_toolbar.dart` /
  `steam_publish_toolbar.dart` are renamed to public
  (`ModsToolbarLeading`, `PendingProjectsBanner`,
  `SteamPublishToolbarLeading`) so the screen can construct them.
- Constructor parameters of `ModsToolbar` / `SteamPublishToolbar` that are
  now only consumed by the leading (e.g. `totalMods`, `filteredMods`,
  `projectsWithPendingChanges`, `onNavigateToProjects`) are dropped from those
  widgets — the screen passes the matching values directly to the leading
  builder.

For the three "off-pattern" screens:

- **Glossary**: gains a `ListToolbarLeading(icon: book_24_regular, title:
  'Glossary')` in `HomeBackToolbar.leading` (the screen had no icon before).
  The custom 48 px Container in `_buildEditor` keeps the
  `GlossaryLanguageSwitcher` chip but loses the duplicated `Text('Glossary')`.
- **Game Files**: `_buildHeader(theme)` and its trailing `SizedBox(height: 24)`
  are removed; the icon + title move into `HomeBackToolbar.leading`. The
  `Padding(all: 24)` now wraps the `projectsAsync.when(...)` directly.
- **Settings**: the `Padding(all: 24)` containing the title `Row` is removed;
  the icon + title move into `HomeBackToolbar.leading`. The Column's
  `crossAxisAlignment` is changed to `stretch` so the new toolbar spans the
  available width.

## Visual / UX details

- Toolbar height: 48 px (matches the editor's `DetailScreenToolbar`).
- Icon: 20 px (`tokens.textMid`), via `ListToolbarLeading`.
- Title: `tokens.fontDisplay` 20 px (`tokens.text`).
- Count label: `tokens.fontMono` 12 px (`tokens.textDim`), shown when the
  screen carries one.
- Trailing widget slot of `ListToolbarLeading` is preserved — Mods uses it for
  its `PendingProjectsBanner` status pill.

## Risks & considerations

- **Vertical space**: top bar is now 48 px and the secondary toolbar (when
  present) is still 48 px. The total chrome height is unchanged from the
  previous iteration.
- **Glossary's secondary container**: it now holds only the
  `GlossaryLanguageSwitcher` chip, padded `16 × 12`. Visually slim; the
  alternative (moving the switcher into `HomeBackToolbar`) was rejected
  because the switcher only exists in the editor sub-state, not the
  preconditions states (no game / no projects / no language).
- **Color regressions**: Game Files used `theme.colorScheme.primary` for its
  globe icon; Settings used `tokens.accent` for its gear. Both now render in
  `tokens.textMid` (the `ListToolbarLeading` default). Trade-off accepted in
  exchange for visual consistency across all eight screens.

## Test plan

Manual verification in the running Flutter app (`flutter run -d windows`):
1. From Home, open each of the 8 screens via the sidebar. Confirm the top
   bar shows back arrow + icon + title + count where applicable.
2. Click the back arrow on each screen — confirm it returns to Home.
3. Confirm the secondary toolbars (search field, action buttons, filter
   pills) still work and stretch to full width.
4. Mods: when a project has pending translation changes, confirm the
   `PendingProjectsBanner` status pill appears next to the count in the top
   bar.
5. Glossary: enter the editor sub-state (game with at least one project and
   one target language), confirm the `GlossaryLanguageSwitcher` is still
   reachable in the slim Container below the top bar.
6. Start a translation in the editor, then click the back arrow on any of
   the eight screens — confirm `canNavigateNow` blocks the move with the
   existing warning toast.

`flutter analyze` must pass with no new warnings.
