# Mods pending banner → Projects filter deep link

## Context

The Mods screen toolbar shows a red status pill when at least one project has pending translation changes ("X project(s) pending", rendered by `_PendingProjectsBanner` in `lib/features/mods/widgets/mods_toolbar.dart`). Tapping the pill is expected to take the user to the Projects screen pre-filtered to the exact set of projects counted by the banner, so the count on the banner matches the number of rows the user sees.

## Problem

Today, tapping the pill calls `ModsScreenController.navigateToProjectsWithFilter` (`lib/features/mods/utils/mods_screen_controller.dart:32`), which does:

```dart
_ref.read(projectsFilterProvider.notifier).setQuickFilter(ProjectQuickFilter.needsUpdate);
GoRouter.of(context).go(AppRoutes.projects);
```

The first line sets the quick filter programmatically before navigation. The second line navigates without a query parameter. When `ProjectsScreen` mounts (`lib/features/projects/screens/projects_screen.dart:48`), its `initState` runs:

```dart
notifier.resetAll();
final initial = widget.initialFilter;
if (initial != null && initial != ProjectQuickFilter.none) {
  notifier.setQuickFilter(initial);
}
```

`resetAll()` wipes the quick filter the controller just set, and `widget.initialFilter` comes from the router reading `state.uri.queryParameters['filter']` (`lib/config/router/app_router.dart:161`). Because no `?filter=…` was passed, `initialFilter` is null and the screen loads with no quick filter applied. Result: the banner says "8 projects pending" but the Projects screen shows every project.

## Semantic alignment

The correct target filter is `ProjectQuickFilter.needsUpdate`, not `ProjectQuickFilter.incomplete`:

- Banner count (`projectsWithPendingChangesCount`, `lib/features/mods/providers/mods_screen_providers.dart:323`) considers a project pending when `project.hasModUpdateImpact` is set or when the source file is newer than the cached Steam workshop timestamp.
- `needsUpdate` filter (`hasUpdates`, `lib/features/projects/providers/projects_screen_providers.dart:174`) considers a project to have updates when `project.hasModUpdateImpact` is set or `updateAnalysis?.hasPendingChanges` is true.

Both are gated on the same primary flag (`hasModUpdateImpact`); the fallback paths differ in mechanics but evaluate the same concept ("source has changed since last analysis"). `incomplete`, by contrast, means "not 100 % translated in all languages" — orthogonal to mod updates.

## Design

Replace the body of `navigateToProjectsWithFilter` so it uses the URL deep-link pattern that the Home dashboard action cards already use (introduced in `7b4828d feat: add projects needs-review filter with URL deep-link`):

```dart
void navigateToProjectsWithFilter(BuildContext context) {
  GoRouter.of(context).go('${AppRoutes.projects}?filter=needs-update');
}
```

The programmatic `setQuickFilter` call goes away — it was dead code, overwritten by `ProjectsScreen.initState`'s `resetAll()`.

### Why this is right

- The token `needs-update` is already registered in `projectQuickFilterFromUrlToken` (`lib/features/projects/providers/projects_screen_providers.dart:84`).
- The router already parses `?filter` and passes it as `initialFilter` to `ProjectsScreen`.
- `initState` applies `initialFilter` after `resetAll()`, so the filter survives.
- No new provider, no new enum, no UI change.

### Out of scope

- Guaranteeing byte-exact equality between the banner count and the filtered list length. The two evaluation paths (timestamp check vs. cached `updateAnalysis`) can momentarily disagree when analysis is stale. Harmonising them into one provider is a separate concern and not required to satisfy the user-visible behavior ("show the same projects"). If a drift is later observed, the fix is to make `hasUpdates` and `projectsWithPendingChangesCount` share a single computation — not to pick a different filter.
- Renaming the banner label ("X projects pending" stays as-is).

## Test plan

Unit test on `ModsScreenController.navigateToProjectsWithFilter`:

- Arrange a `ProviderContainer` and a `BuildContext` wired to a `GoRouter` with the real `AppRoutes.projects` path.
- Act: call `navigateToProjectsWithFilter(context)`.
- Assert: the current `GoRouter` location equals `/work/projects?filter=needs-update`.

If the Flutter test harness makes pumping a real `GoRouter` heavy for this one case, fall back to asserting on a thin shim: wrap the navigation call behind an injectable navigator seam or verify via a widget test that taps the `_PendingProjectsBanner` and reads the router's current URI.

## Acceptance criteria

1. Tapping the pending banner in the Mods toolbar navigates to `/work/projects?filter=needs-update`.
2. The Projects screen opens with the "needs update" quick filter active (the same filter currently exposed on the Projects screen filter bar / dashboard `needs-update` card).
3. No regression for other Projects screen entry points (dashboard cards continue to work with their existing `?filter=…` tokens).
