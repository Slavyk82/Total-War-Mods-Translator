# Home back-toolbar on top-level screens

**Status:** approved
**Date:** 2026-04-25

## Goal

Add a thin top toolbar on every top-level screen reachable from the sidebar, in
the same visual style as the existing `DetailScreenToolbar` used by the
translation editor: a back arrow on the left and a breadcrumb trail next to it.
Crumb format: `Home › <Screen Name>`. The back arrow returns to the Home screen.

This gives users an explicit "go back to Home" affordance on every screen,
even though the sidebar already exposes Home — the back arrow + crumb pattern
is more discoverable, and consistent with the editor's chrome.

## Scope

Eight screens get the toolbar:

| Screen              | Crumb                       | File |
|---------------------|-----------------------------|------|
| Mods                | `Home › Mods`               | `lib/features/mods/screens/mods_screen.dart` |
| Projects            | `Home › Projects`           | `lib/features/projects/screens/projects_screen.dart` |
| Publish             | `Home › Publish`            | `lib/features/steam_publish/screens/steam_publish_screen.dart` |
| Glossary            | `Home › Glossary`           | `lib/features/glossary/screens/glossary_screen.dart` |
| Translation Memory  | `Home › Translation Memory` | `lib/features/translation_memory/screens/translation_memory_screen.dart` |
| Game Files          | `Home › Game Files`         | `lib/features/game_translation/screens/game_translation_screen.dart` |
| Compile             | `Home › Compile`            | `lib/features/pack_compilation/screens/pack_compilation_list_screen.dart` |
| Settings            | `Home › Settings`           | `lib/features/settings/screens/settings_screen.dart` |

Screens labels match the sidebar `navigationTree` labels. The Home screen
itself is not modified (no need for a back button there). The translation
editor and other detail/sub-screens keep their existing toolbars.

## Non-goals

- The sidebar is not modified.
- The translation editor's existing 3-segment crumb (`Work › Projects › <name>`)
  is not changed.
- Sub-screens like `BatchPackExportScreen`, `WorkshopPublishScreen`,
  `BatchWorkshopPublishScreen`, `PackCompilationEditorScreen` are out of scope —
  they have a different navigation pattern (descendants of lists) and are not
  in the user's list.

## Architecture

### New widget: `HomeBackToolbar`

File: `lib/widgets/detail/home_back_toolbar.dart`

A thin `ConsumerWidget` wrapper around `DetailScreenToolbar`. It centralises
the "back to Home" navigation logic so the eight screens don't each duplicate
the route + guard boilerplate.

```dart
class HomeBackToolbar extends ConsumerWidget {
  final String currentLabel;
  const HomeBackToolbar({super.key, required this.currentLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DetailScreenToolbar(
      crumbs: [
        const CrumbSegment('Home'),
        CrumbSegment(currentLabel),
      ],
      onBack: () {
        if (canNavigateNow(context, ref)) {
          context.go(AppRoutes.home);
        }
      },
    );
  }
}
```

Why a wrapper rather than inlining `DetailScreenToolbar` in each screen:
- Avoids duplicating the navigation + guard logic eight times.
- Single source of truth: a future tweak (tooltip text, icon, behaviour) is
  one edit instead of eight.
- Keeps `DetailScreenToolbar` generic — it remains usable for other crumb
  patterns (the editor still uses it directly with three segments).

### Navigation behaviour

- The back arrow calls `context.go(AppRoutes.home)`, **not** `context.pop()`.
  These screens are typically reached via the sidebar (`context.go`), so
  `canPop()` returns `false` in the common case. Using `go` is deterministic.
- The call is wrapped in `canNavigateNow(context, ref)` so an in-progress
  translation or pack compilation blocks the back navigation with the existing
  warning toast — consistent with the sidebar and with crumb taps in the
  editor.

### Per-screen integration

Each target screen already builds a `Column` (or a `FluentScaffold` with a
`Column` body). The integration is uniform: insert
`HomeBackToolbar(currentLabel: '<X>')` as the **first child** of that column,
above the existing screen toolbar.

For screens using `FluentScaffold` (Game Files, Steam Publish), the wrapper is
prepended inside the scaffold body so the sidebar layout is unchanged.

## Visual / UX details

- Toolbar height: 48 px (inherited from `DetailScreenToolbar`).
- First crumb (`Home`) is rendered in dim text, non-clickable — this matches
  the existing `_CrumbTrail` convention (`isFirst` branch returns `null` for
  `onTap`). Users navigate Home via the **back arrow**, not the crumb text.
- Last crumb (`<Screen Name>`) is rendered bold/current.
- No trailing widgets in the toolbar.

## Risks & considerations

- **Vertical space**: each screen adds 48 px of chrome. The 8 screens already
  have a content toolbar below, so the result is two stacked bars (same as the
  editor today). Acceptable.
- **`Settings` screen** uses `Scaffold` + `Padding(all: 24)` rather than the
  shared toolbar primitives. The `HomeBackToolbar` will sit above the existing
  padded content; the visual rhythm should remain coherent (verify in app).
- **`GameTranslationScreen` and `SteamPublishScreen`** use `FluentScaffold`.
  Adding the toolbar inside their body is a structural change but additive —
  no existing widget is removed.

## Test plan

Manual verification in the running Flutter app:
1. From Home, navigate to each of the 8 screens via the sidebar — confirm the
   `Home › <Name>` crumb and back arrow appear.
2. Click the back arrow on each screen — confirm it returns to Home.
3. Start a translation in the editor, then click a sidebar item to leave —
   confirm the existing in-progress guard still fires (regression check, not
   directly affected but the same `canNavigateNow` is used).
4. Visual sanity: confirm the toolbar height/style matches the editor's.

`flutter analyze` must pass with no new warnings.
