# Game Translation — multi-create + delete + Projects-style toolbar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user create additional Game Translation projects (not just from the empty state) and delete existing ones, by adopting the Projects-screen toolbar pattern (count + persistent Create action) and adding a delete icon on each `ProjectCard`.

**Architecture:** Keep the existing card layout (`ProjectGrid` + `ProjectCard`). Insert a `FilterToolbar` row below the existing `HomeBackToolbar`, hosting a "Create Game Translation" `SmallTextButton`. Add an optional `onDelete` callback to `ProjectCard` (rendered as a delete icon at the end of the card header) and forward it through `ProjectGrid`. Wire the Game Translation screen to use the same `TokenConfirmDialog` + `projectRepositoryProvider.delete()` + `gameTranslationProjectsProvider` invalidation flow that the Projects screen already uses.

**Tech Stack:** Flutter (Material 3) · Riverpod (`flutter_riverpod`) · `fluentui_system_icons` · existing tokenised primitives (`FilterToolbar`, `ListToolbarLeading`, `SmallTextButton`, `TokenConfirmDialog`, `FluentToast`). Spec: `docs/superpowers/specs/2026-04-25-game-translation-multi-add-delete-design.md`. No automated tests — manual verification on `flutter run -d windows`.

---

## File map

**Modify:**
- `lib/features/projects/widgets/project_card.dart` — add nullable `onDelete` + delete icon at the end of `_buildHeader`
- `lib/features/projects/widgets/project_grid.dart` — add nullable `onDelete` prop and forward it to each card
- `lib/features/game_translation/screens/game_translation_screen.dart` — add count to leading, insert `FilterToolbar` with Create button, add `_handleDeleteProject`, pass `onDelete` to `ProjectGrid`

**No new files. No test files (none exist for this screen and the spec excludes adding any).**

---

## Task 1: Add optional `onDelete` to `ProjectCard`

**Files:**
- Modify: `lib/features/projects/widgets/project_card.dart`

The Projects screen renders its own row layout and never instantiates `ProjectCard` (it lives inside `ProjectGrid`, which today is only used by the Game Translation screen and the `home/recent_projects` widget). Adding `onDelete` as a nullable prop is therefore backwards-compatible — existing call sites pass nothing and get the previous visual.

Mirror the existing `_buildResyncButton` (lines 287–332) for the delete icon: a `GestureDetector` with `behavior: HitTestBehavior.opaque` wrapping a tinted square — this both absorbs the tap (so the card's outer `GestureDetector` does not receive it) and matches the surrounding visual style. Use the theme's error color so the destructive intent reads clearly.

- [ ] **Step 1: Add the `onDelete` prop**

Open `lib/features/projects/widgets/project_card.dart`. After the existing `onSelectionToggle` field around line 20 add:

```dart
  final VoidCallback? onDelete;
```

Update the constructor (around lines 22–31) to include `this.onDelete,`:

```dart
  const ProjectCard({
    super.key,
    required this.projectWithDetails,
    this.onTap,
    this.onResync,
    this.isResyncing = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
    this.onDelete,
  });
```

- [ ] **Step 2: Render the delete icon at the end of the header row**

In `_buildHeader` (around lines 150–201), append a delete-icon block at the very end of the `Row` children, after the resync button block. Insert immediately before the closing `],` of the `Row(children: [...])`:

```dart
        // Delete button (only shown when caller provides an onDelete callback)
        if (widget.onDelete != null) ...[
          const SizedBox(width: 8),
          _buildDeleteButton(context),
        ],
```

- [ ] **Step 3: Add the `_buildDeleteButton` method**

Add this method to `_ProjectCardState` immediately after `_buildResyncButton` (i.e. after line 332, before `_buildLanguageProgress`):

```dart
  Widget _buildDeleteButton(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Delete',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Absorb the tap so the card's outer GestureDetector does not also
          // fire and navigate into the project.
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onDelete?.call(),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              FluentIcons.delete_24_regular,
              size: 14,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze lib/features/projects/widgets/project_card.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/projects/widgets/project_card.dart
git commit -m "feat(projects): add optional onDelete to ProjectCard"
```

---

## Task 2: Forward `onDelete` through `ProjectGrid`

**Files:**
- Modify: `lib/features/projects/widgets/project_grid.dart`

Plumbing-only change. Existing callers pass nothing and keep the previous behavior.

- [ ] **Step 1: Add the `onDelete` prop and forward it**

Replace the entire contents of `lib/features/projects/widgets/project_grid.dart` with:

```dart
import 'package:flutter/material.dart';
import '../providers/projects_screen_providers.dart';
import 'project_card.dart';

/// List layout for displaying project cards.
///
/// Displays project cards in full width.
class ProjectGrid extends StatelessWidget {
  final List<ProjectWithDetails> projects;
  final Function(String projectId)? onProjectTap;
  final Function(String projectId)? onResync;
  final Function(String projectId)? onDelete;
  final Set<String> resyncingProjects;
  final bool isSelectionMode;
  final Set<String> selectedProjectIds;
  final Function(String projectId)? onSelectionToggle;

  const ProjectGrid({
    super.key,
    required this.projects,
    this.onProjectTap,
    this.onResync,
    this.onDelete,
    this.resyncingProjects = const {},
    this.isSelectionMode = false,
    this.selectedProjectIds = const {},
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: projects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final projectWithDetails = projects[index];
        final projectId = projectWithDetails.project.id;
        return ProjectCard(
          projectWithDetails: projectWithDetails,
          onTap: () => onProjectTap?.call(projectId),
          onResync: () => onResync?.call(projectId),
          onDelete: onDelete == null ? null : () => onDelete!(projectId),
          isResyncing: resyncingProjects.contains(projectId),
          isSelectionMode: isSelectionMode,
          isSelected: selectedProjectIds.contains(projectId),
          onSelectionToggle: () => onSelectionToggle?.call(projectId),
        );
      },
    );
  }
}
```

The `onDelete == null ? null : () => onDelete!(projectId)` ternary is important: passing a non-null wrapper closure unconditionally would cause `ProjectCard` to render the delete icon for every existing call site (including `home/recent_projects`).

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/features/projects/widgets/project_grid.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/projects/widgets/project_grid.dart
git commit -m "feat(projects): forward onDelete through ProjectGrid"
```

---

## Task 3: Game Translation screen — count, toolbar Create button, delete handler

**Files:**
- Modify: `lib/features/game_translation/screens/game_translation_screen.dart`

This task replaces the screen body with a version that:
1. Adds a translations count in `ListToolbarLeading.countLabel`.
2. Inserts a `FilterToolbar` with a single trailing **Create Game Translation** `SmallTextButton` (filled variant, accent CTA).
3. Disables that button with a tooltip when `hasLocalPacksProvider.value == false`.
4. Adds `_handleDeleteProject` that mirrors `projects_screen.dart:376-405`, using `TokenConfirmDialog` + `projectRepositoryProvider.delete()` + `ref.invalidate(gameTranslationProjectsProvider)` + `FluentToast`.
5. Passes the delete handler to `ProjectGrid` via the new `onDelete` prop.

The screen must become `ConsumerStatefulWidget` only if needed. The current implementation is `ConsumerWidget` with `_handleDeleteProject` taking `WidgetRef`. We can keep it as `ConsumerWidget` and just thread `ref` into the helper — no state is needed.

- [ ] **Step 1: Replace the screen with the new implementation**

Replace the entire contents of `lib/features/game_translation/screens/game_translation_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../widgets/detail/home_back_toolbar.dart';
import '../../../widgets/layouts/fluent_scaffold.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/lists/list_toolbar_leading.dart';
import '../../projects/providers/projects_screen_providers.dart';
import '../../projects/utils/open_project_editor.dart';
import '../../projects/widgets/project_grid.dart';
import '../providers/game_translation_providers.dart';
import '../widgets/create_game_translation/create_game_translation_dialog.dart';

/// Screen for managing game translation projects.
///
/// Displays a list of game translation projects (projects with type='game')
/// that allow translating the base game's localization files.
class GameTranslationScreen extends ConsumerWidget {
  const GameTranslationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projectsAsync = ref.watch(gameTranslationProjectsProvider);
    final hasPacksAsync = ref.watch(hasLocalPacksProvider);
    // During loading/error treat packs as available (permissive). Empty data
    // means no packs detected — disable the toolbar Create button.
    final hasPacks = hasPacksAsync.value ?? true;
    final count = projectsAsync.asData?.value.length ?? 0;

    return FluentScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBackToolbar(
            leading: ListToolbarLeading(
              icon: FluentIcons.globe_24_regular,
              title: 'Game Translation',
              countLabel: '$count ${count == 1 ? 'translation' : 'translations'}',
            ),
          ),
          FilterToolbar(
            leading: const SizedBox.shrink(),
            expandLeading: false,
            trailing: [
              SmallTextButton(
                label: 'Create Game Translation',
                icon: FluentIcons.add_24_regular,
                filled: true,
                tooltip: hasPacks
                    ? null
                    : 'No localization packs found for this game',
                onTap:
                    hasPacks ? () => _showCreateDialog(context, ref) : null,
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: projectsAsync.when(
                data: (projects) =>
                    _buildContent(context, ref, theme, projects),
                loading: () => _buildLoading(theme),
                error: (error, stack) => _buildError(theme, error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    List<ProjectWithDetails> projects,
  ) {
    if (projects.isEmpty) {
      return _buildEmptyState(context, theme);
    }

    return ProjectGrid(
      projects: projects,
      onProjectTap: (projectId) => _navigateToProject(context, ref, projectId),
      onDelete: (projectId) {
        final details = projects.firstWhere(
          (p) => p.project.id == projectId,
        );
        _handleDeleteProject(context, ref, details);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.globe_24_regular,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No game translations yet',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new translation to translate the base game',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Consumer(
            builder: (context, ref, child) {
              final hasPacksAsync = ref.watch(hasLocalPacksProvider);
              return hasPacksAsync.when(
                data: (hasPacks) {
                  if (!hasPacks) {
                    return Column(
                      children: [
                        Icon(
                          FluentIcons.warning_24_regular,
                          size: 24,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No localization packs found for this game',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    );
                  }
                  return FluentButton(
                    onPressed: () => _showCreateDialog(context, ref),
                    icon: const Icon(FluentIcons.add_24_regular),
                    child: const Text('Create Game Translation'),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (_, _) => const Text('Error loading packs'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading game translations...',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading game translations',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CreateGameTranslationDialog(),
    );
  }

  void _navigateToProject(BuildContext context, WidgetRef ref, String projectId) {
    openProjectEditor(context, ref, projectId);
  }

  /// Confirm + delete a game translation project.
  ///
  /// Mirrors `projects_screen.dart:_handleDeleteProject` but invalidates the
  /// game-translations provider instead of using the optimistic
  /// `removeProject` notifier helper, since `gameTranslationProjectsProvider`
  /// is a plain FutureProvider.
  Future<void> _handleDeleteProject(
    BuildContext context,
    WidgetRef ref,
    ProjectWithDetails details,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TokenConfirmDialog(
        title: 'Delete Game Translation',
        message:
            'Are you sure you want to delete "${details.project.name}"?',
        warningMessage: 'This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmIcon: FluentIcons.delete_24_regular,
        destructive: true,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(shared_repo.projectRepositoryProvider)
        .delete(details.project.id);
    if (!context.mounted) return;
    if (result.isOk) {
      ref.invalidate(gameTranslationProjectsProvider);
      FluentToast.success(
        context,
        'Game translation "${details.project.name}" deleted',
      );
    } else {
      FluentToast.error(
        context,
        'Failed to delete game translation: ${result.error}',
      );
    }
  }
}
```

- [ ] **Step 2: Run static analysis on the screen**

Run: `flutter analyze lib/features/game_translation/screens/game_translation_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Run static analysis on the whole package**

Run: `flutter analyze`
Expected: `No issues found!` (or only pre-existing warnings unrelated to these files).

- [ ] **Step 4: Manual verification — create flow**

Run: `flutter run -d windows`. Sign-in / open the app, pick a game with at least one detected local pack, and navigate to **Game Translation**.

Verify, in order:
1. Empty state still shows the existing big "Create Game Translation" button (regression check).
2. The toolbar leading shows `Game Translation  0 translations`.
3. The new toolbar row (below the back arrow row) shows a filled accent **Create Game Translation** button on the right.
4. Click the toolbar Create button → wizard opens. Complete it. After it closes, the count becomes `1 translation`, the card list renders one card, and that card has a red-tinted delete icon at the right end of its header.
5. Click the toolbar Create button again → wizard reopens, create another → count becomes `2 translations`.

- [ ] **Step 5: Manual verification — delete flow**

Continuing the same session:
1. Click the delete icon on one card → `TokenConfirmDialog` opens with the project name and "This action cannot be undone." warning.
2. Cancel → dialog closes, no toast, the list is unchanged.
3. Click delete again, confirm → success toast `Game translation "<name>" deleted`. Count drops from `2 translations` to `1 translation`.
4. Delete the last one → count becomes `0 translations`, the body returns to the empty state with its big CTA still working.
5. Click the delete icon directly (not the card body) and verify that no editor navigation happens — only the dialog appears.

- [ ] **Step 6: Manual verification — disabled Create state**

Pick (or simulate, by clearing the game's installation path in Settings) a game that has **no** detected local packs. Navigate to Game Translation:
1. Toolbar Create button is rendered but disabled (lower-alpha) and shows the tooltip `No localization packs found for this game` on hover.
2. Empty state still shows its existing warning + no FluentButton (regression).

- [ ] **Step 7: Commit**

```bash
git add lib/features/game_translation/screens/game_translation_screen.dart
git commit -m "feat(game-translation): add toolbar create + per-card delete"
```

---

## Self-review notes

- **Spec coverage:**
  - Persistent Create access → Task 3 (toolbar Create button).
  - Delete with confirmation → Task 1 (icon) + Task 3 (`_handleDeleteProject`).
  - Toolbar count → Task 3 (`countLabel`).
  - Disabled-Create-when-no-packs → Task 3 (`onTap: hasPacks ? ... : null` + tooltip).
  - Empty-state regression → Task 3 manual verification step 4 + step 6 part 2.
  - Last-delete returns to empty state → Task 3 step 5.4.
  - Card-tap not triggered by delete icon → Task 1 (`HitTestBehavior.opaque` in `_buildDeleteButton`) + Task 3 step 5.5.
- **Other ProjectGrid call sites:** `home/recent_projects` does not pass `onDelete` and therefore gets `null`, so the delete icon does not render there. Verified by leaving `onDelete` nullable and gating the icon on `widget.onDelete != null`.
- **Type consistency:** `ProjectCard.onDelete` and `ProjectGrid.onDelete` are both `Function(String projectId)?` / `VoidCallback?` with the wrapping in `ProjectGrid.build` adapting between them. `_handleDeleteProject` signature matches the call site in Task 3 (`(context, ref, details)`).
- **No placeholders** in any step; every change shows the exact code to write or replace.
