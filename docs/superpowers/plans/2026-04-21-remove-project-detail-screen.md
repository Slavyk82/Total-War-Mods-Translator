# Remove Project Detail Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Supprimer l'écran intermédiaire `ProjectDetailScreen`, déplacer ses actions (delete project, open Steam) sur la carte projet, et intégrer un sélecteur de langue directement dans l'éditeur de traduction.

**Architecture:** Un nouveau helper `openProjectEditor(ctx, ref, projectId)` résout la langue cible (default-from-settings ou première) et navigue directement vers `AppRoutes.translationEditor`. L'éditeur gagne un `EditorLanguageSwitcher` dans sa `FilterToolbar` pour basculer, ajouter et supprimer une langue du projet. Le wizard de création passe de 3 à 2 étapes et crée un unique `ProjectLanguage` sur la langue par défaut des settings. La carte projet (`ProjectCard`) expose directement les actions delete/Steam et rend chaque barre de progression cliquable vers l'éditeur.

**Tech Stack:** Flutter Desktop (Windows), Riverpod 3, GoRouter, Material 3, tokens `TwmtThemeTokens`.

---

## File Structure

### Created
- `lib/features/projects/utils/open_project_editor.dart` — Helper de navigation.
- `lib/features/translation_editor/widgets/editor_language_switcher.dart` — Chip + popover + add/delete.
- `test/features/projects/utils/open_project_editor_test.dart`
- `test/features/translation_editor/widgets/editor_language_switcher_test.dart`

### Modified
- `lib/config/router/app_router.dart` — Retrait de la route `projectDetail`, `AppRoutes.projectDetail`, `goProjectDetail`.
- `lib/features/projects/screens/projects_screen.dart` — `onTap` passe par helper.
- `lib/features/home/widgets/recent_projects_list.dart` — idem.
- `lib/features/mods/utils/mods_screen_controller.dart` — 3 sites.
- `lib/features/mods/widgets/whats_new_dialog.dart` — 1 site.
- `lib/features/game_translation/screens/game_translation_screen.dart` — 1 site.
- `lib/features/translation_editor/screens/translation_editor_screen.dart` — Ajout switcher, retrait crumb langue, `CrumbSegment(projectName)` sans route.
- `lib/features/translation_editor/screens/actions/editor_actions_base.dart` — Retrait de l'invalidation `projectDetailsProvider`.
- `lib/features/translation_editor/screens/actions/editor_actions_translation.dart` — `projectDetailsProvider` → `currentProjectProvider`.
- `lib/features/projects/widgets/add_language_dialog.dart` — Invalidation `projectLanguagesProvider` au lieu de `projectDetailsProvider`.
- `lib/features/projects/widgets/create_project/create_project_dialog.dart` — 2 étapes, création langue par défaut.
- `lib/features/projects/widgets/create_project/project_creation_state.dart` — Suppression `selectedLanguageIds`.

### Deleted
- `lib/features/projects/screens/project_detail_screen.dart`
- `lib/features/projects/providers/project_detail_providers.dart` (une fois vidé : sinon conservé allégé)
- `lib/features/projects/widgets/language_progress_row.dart`
- `lib/features/projects/widgets/create_project/step_languages.dart`
- `test/features/projects/screens/project_detail_screen_test.dart`
- `test/features/projects/widgets/language_progress_row_test.dart`
- `test/features/projects/widgets/create_project/create_project_dialog_language_validation_test.dart`

---

## Commands

Avant toute modification de code générée par Riverpod, lancer :
```
C:/src/flutter/bin/dart run build_runner build --delete-conflicting-outputs
```

Pour lancer la suite de tests d'un fichier :
```
C:/src/flutter/bin/flutter test test/path/to/file_test.dart
```

Pour analyser statiquement :
```
C:/src/flutter/bin/flutter analyze
```

---

## Task 1 — Helper `openProjectEditor`

**Files:**
- Create: `lib/features/projects/utils/open_project_editor.dart`
- Create: `test/features/projects/utils/open_project_editor_test.dart`

**Rationale:** Centraliser la résolution de langue dans un seul point avant de toucher au routeur. Le helper doit être appelable depuis n'importe quel `ConsumerWidget` / `ConsumerState`. Aucune dépendance à l'ancien `ProjectDetailScreen` — on écrit d'abord ce helper isolé.

- [ ] **Step 1.1 — Write the failing test**

Create `test/features/projects/utils/open_project_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/test_helpers.dart';

class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(this._defaultCode);
  final String _defaultCode;

  @override
  Future<String> getString(String key, {String defaultValue = ''}) async {
    if (key == SettingsKeys.defaultTargetLanguage) return _defaultCode;
    return defaultValue;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProjectLanguageDetails _pld(String id, String code, String name) {
  return ProjectLanguageDetails(
    projectLanguage: ProjectLanguage(
      id: 'pl_$id',
      projectId: 'p',
      languageId: id,
      progressPercent: 0.0,
      createdAt: 1,
      updatedAt: 1,
    ),
    language: Language(
      id: id,
      code: code,
      name: name,
      nativeName: name,
    ),
  );
}

void main() {
  setUp(setupMockServices);
  tearDown(tearDownMockServices);

  testWidgets('resolves to settings default when present in project',
      (tester) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(_FakeSettingsService('de')),
      projectLanguagesProvider('p').overrideWith((ref) async => [
            _pld('fr-id', 'fr', 'French'),
            _pld('de-id', 'de', 'German'),
          ]),
    ]);
    addTearDown(container.dispose);

    final id = await resolveTargetLanguageId(container.read, 'p');
    expect(id, 'de-id');
  });

  testWidgets('falls back to first language when default missing',
      (tester) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(_FakeSettingsService('es')),
      projectLanguagesProvider('p').overrideWith((ref) async => [
            _pld('fr-id', 'fr', 'French'),
            _pld('de-id', 'de', 'German'),
          ]),
    ]);
    addTearDown(container.dispose);

    final id = await resolveTargetLanguageId(container.read, 'p');
    expect(id, 'fr-id');
  });

  testWidgets('returns null when project has no languages', (tester) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(_FakeSettingsService('fr')),
      projectLanguagesProvider('p').overrideWith((ref) async => []),
    ]);
    addTearDown(container.dispose);

    final id = await resolveTargetLanguageId(container.read, 'p');
    expect(id, isNull);
  });
}
```

- [ ] **Step 1.2 — Run the failing test**

```
C:/src/flutter/bin/flutter test test/features/projects/utils/open_project_editor_test.dart
```

Expected: compilation failure (`open_project_editor.dart` doesn't exist yet, `resolveTargetLanguageId` undefined).

- [ ] **Step 1.3 — Write the helper**

Create `lib/features/projects/utils/open_project_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Resolves which `languageId` to land on when opening a project.
///
/// Rule: if the project contains a language whose `code` matches
/// `SettingsKeys.defaultTargetLanguage`, return that language's id. Otherwise
/// return the first project language. Returns `null` when the project has no
/// language.
Future<String?> resolveTargetLanguageId(
  T Function<T>(ProviderListenable<T>) read,
  String projectId,
) async {
  final langs = await read(projectLanguagesProvider(projectId).future);
  if (langs.isEmpty) return null;

  final settings = read(settingsServiceProvider);
  final defaultCode = await settings.getString(
    SettingsKeys.defaultTargetLanguage,
    defaultValue: SettingsKeys.defaultTargetLanguageValue,
  );

  final match = langs.where((l) => l.language.code == defaultCode).firstOrNull;
  return (match ?? langs.first).projectLanguage.languageId;
}

/// Navigate to the translation editor for the given project, resolving the
/// target language automatically. Shows a toast and returns to the projects
/// list when the project has no language yet.
Future<void> openProjectEditor(
  BuildContext context,
  WidgetRef ref,
  String projectId,
) async {
  final languageId = await resolveTargetLanguageId(ref.read, projectId);
  if (!context.mounted) return;
  if (languageId == null) {
    FluentToast.warning(context, 'This project has no target language');
    context.go(AppRoutes.projects);
    return;
  }
  context.go(AppRoutes.translationEditor(projectId, languageId));
}
```

- [ ] **Step 1.4 — Run the test to verify it passes**

```
C:/src/flutter/bin/flutter test test/features/projects/utils/open_project_editor_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 1.5 — Commit**

```
git add lib/features/projects/utils/open_project_editor.dart \
        test/features/projects/utils/open_project_editor_test.dart
git commit -m "feat: add openProjectEditor helper resolving default language"
```

---

## Task 2 — Migrate `projectDetailsProvider` consumers

**Files:**
- Modify: `lib/features/translation_editor/screens/actions/editor_actions_base.dart`
- Modify: `lib/features/translation_editor/screens/actions/editor_actions_translation.dart`
- Modify: `lib/features/projects/widgets/add_language_dialog.dart`

**Rationale:** Avant de supprimer `projectDetailsProvider`, ses trois consommateurs restants doivent migrer. Chacun n'utilise qu'une information triviale (nom du projet) ou une invalidation croisée. `currentProjectProvider` (dans `editor_providers.dart`) fournit déjà le projet seul. `projectLanguagesProvider` fournit le reste.

- [ ] **Step 2.1 — Update `editor_actions_base.dart`**

Edit `lib/features/translation_editor/screens/actions/editor_actions_base.dart` lines 5-6 and 45.

Replace the `show` import lines:

```dart
import '../../../projects/providers/projects_screen_providers.dart'
    show projectsWithDetailsProvider, translationStatsVersionProvider;
```

Remove the `project_detail_providers` import entirely (lines 5-6). Then delete the `ref.invalidate(projectDetailsProvider(projectId));` line in `refreshProviders()`.

After: `refreshProviders` looks like:

```dart
void refreshProviders() {
  if (!mounted) return;
  ref.invalidate(translationRowsProvider(projectId, languageId));
  ref.invalidate(editorStatsProvider(projectId, languageId));
  ref.invalidate(projectsWithDetailsProvider);
  ref.read(translationStatsVersionProvider.notifier).increment();
}
```

- [ ] **Step 2.2 — Update `editor_actions_translation.dart`**

Edit `lib/features/translation_editor/screens/actions/editor_actions_translation.dart` around line 201.

Replace:

```dart
final projectDetails = await ref.read(projectDetailsProvider(projectId).future);
final projectName = projectDetails.project.name;
```

With:

```dart
final project = await ref.read(currentProjectProvider(projectId).future);
final projectName = project.name;
```

Then remove any now-unused `project_detail_providers` import at the top of the file.

- [ ] **Step 2.3 — Update `add_language_dialog.dart`**

Edit `lib/features/projects/widgets/add_language_dialog.dart` around line 276.

Replace:

```dart
ref.invalidate(projectDetailsProvider(widget.projectId));
```

With:

```dart
ref.invalidate(projectLanguagesProvider(widget.projectId));
```

Remove the `project_detail_providers` import if `projectDetailsProvider` was the only symbol used from it (but note that `projectLanguagesProvider` lives in the same file — keep the import, just change the symbol used).

- [ ] **Step 2.4 — Run existing tests to confirm nothing broke**

```
C:/src/flutter/bin/flutter test test/features/translation_editor/ test/features/projects/widgets/
```

Expected: all currently-passing tests still pass (failures in `project_detail_screen_test.dart` are tolerated — that file will be removed in Task 8; but no NEW failures in other files).

- [ ] **Step 2.5 — Commit**

```
git add lib/features/translation_editor/screens/actions/editor_actions_base.dart \
        lib/features/translation_editor/screens/actions/editor_actions_translation.dart \
        lib/features/projects/widgets/add_language_dialog.dart
git commit -m "refactor: drop projectDetailsProvider consumers in editor and dialogs"
```

---

## Task 3 — Route callers through `openProjectEditor`

**Files:**
- Modify: `lib/features/projects/screens/projects_screen.dart` (1 site)
- Modify: `lib/features/home/widgets/recent_projects_list.dart` (1 site)
- Modify: `lib/features/mods/widgets/whats_new_dialog.dart` (1 site)
- Modify: `lib/features/mods/utils/mods_screen_controller.dart` (3 sites)
- Modify: `lib/features/game_translation/screens/game_translation_screen.dart` (1 site)

**Rationale:** Tous les appelants qui pointent vers `AppRoutes.projectDetail(projectId)` doivent désormais résoudre la langue via le helper. La route `projectDetail` reste vivante pendant cette tâche (au cas où un deep-link arrive, l'écran existe encore) ; elle sera supprimée en Task 8.

- [ ] **Step 3.1 — `projects_screen.dart`**

Around line 206, replace:

```dart
context.go(AppRoutes.projectDetail(projectId));
```

With:

```dart
openProjectEditor(context, ref, projectId);
```

Add the import:

```dart
import 'package:twmt/features/projects/utils/open_project_editor.dart';
```

- [ ] **Step 3.2 — `recent_projects_list.dart`**

Around line 47, replace:

```dart
onTap: () => context.go(AppRoutes.projectDetail(p.project.id)),
```

With:

```dart
onTap: () => openProjectEditor(context, ref, p.project.id),
```

Add the import at the top. Note: `RecentProjectsList` is a `ConsumerWidget`, so `ref` is in scope.

- [ ] **Step 3.3 — `whats_new_dialog.dart`**

Around line 86, replace the `context.go(AppRoutes.projectDetail(project.id));` call with `openProjectEditor(context, ref, project.id);`. Add the import.

If `WhatsNewDialog` is a `ConsumerWidget` use `ref`; if it receives `ref` via constructor, use that parameter. Inspect the surrounding function signature to decide.

- [ ] **Step 3.4 — `mods_screen_controller.dart` (3 sites)**

Around lines 108, 209, 287, replace `router.go(AppRoutes.projectDetail(X))` with `router.go(AppRoutes.translationEditor(X, resolvedLangId))` — but this controller already has a `_ref` in scope. So use:

```dart
await openProjectEditor(context, WidgetRef? proxy, existingProject.id);
```

Since `_ref` is a `Ref` (not `WidgetRef`), add a secondary overload in `open_project_editor.dart` that accepts a `Ref`. Edit the helper file:

Add at the end of `lib/features/projects/utils/open_project_editor.dart`:

```dart
/// Same as [openProjectEditor] but callable from contexts that hold a
/// bare `Ref` (e.g. stateful controllers). Uses `GoRouter.of(context)` for
/// navigation.
Future<void> openProjectEditorFromRef(
  BuildContext context,
  Ref ref,
  String projectId,
) async {
  final languageId = await resolveTargetLanguageId(ref.read, projectId);
  if (!context.mounted) return;
  final router = GoRouter.of(context);
  if (languageId == null) {
    FluentToast.warning(context, 'This project has no target language');
    router.go(AppRoutes.projects);
    return;
  }
  router.go(AppRoutes.translationEditor(projectId, languageId));
}
```

Then replace the 3 sites with `await openProjectEditorFromRef(context, _ref, <projectId>);` (keep the `return` after the line at site 108 if present in the current code).

Update the test for `resolveTargetLanguageId` — it already accepts a `read` function, no change needed.

- [ ] **Step 3.5 — `game_translation_screen.dart`**

Around line 207, replace `context.go(AppRoutes.projectDetail(projectId));` with `openProjectEditor(context, ref, projectId);`. Add the import.

- [ ] **Step 3.6 — Run analyse + tests**

```
C:/src/flutter/bin/flutter analyze
C:/src/flutter/bin/flutter test test/features/
```

Expected: analyze is clean. Tests pass except `project_detail_screen_test.dart` and the dialog validation test (tolerated — deleted in Task 8).

- [ ] **Step 3.7 — Commit**

```
git add lib/features/projects/utils/open_project_editor.dart \
        lib/features/projects/screens/projects_screen.dart \
        lib/features/home/widgets/recent_projects_list.dart \
        lib/features/mods/widgets/whats_new_dialog.dart \
        lib/features/mods/utils/mods_screen_controller.dart \
        lib/features/game_translation/screens/game_translation_screen.dart
git commit -m "refactor: route project navigation through openProjectEditor"
```

---

## Task 4 — Build `EditorLanguageSwitcher` widget

**Files:**
- Create: `lib/features/translation_editor/widgets/editor_language_switcher.dart`
- Create: `test/features/translation_editor/widgets/editor_language_switcher_test.dart`

**Rationale:** Widget standalone (ConsumerWidget) qui liste les langues du projet dans un `MenuAnchor`, permet de switcher, d'en ajouter (via `AddLanguageDialog`) et d'en supprimer (sauf la dernière). Aucune intégration dans l'éditeur à cette étape — juste le widget isolé, testable en vase clos.

- [ ] **Step 4.1 — Write the failing test**

Create `test/features/translation_editor/widgets/editor_language_switcher_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_language_switcher.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

ProjectLanguageDetails _pld(String id, String code, String name,
    {int translated = 0, int total = 0}) {
  return ProjectLanguageDetails(
    projectLanguage: ProjectLanguage(
      id: 'pl_$id',
      projectId: 'p',
      languageId: id,
      progressPercent: total == 0 ? 0 : translated / total * 100,
      createdAt: 1,
      updatedAt: 1,
    ),
    language: Language(id: id, code: code, name: name, nativeName: name),
    totalUnits: total,
    translatedUnits: translated,
  );
}

void main() {
  setUp(setupMockServices);
  tearDown(tearDownMockServices);

  Widget wrap(Widget child, List<Override> overrides) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('renders current language label', (tester) async {
    await tester.pumpWidget(wrap(
      const EditorLanguageSwitcher(projectId: 'p', currentLanguageId: 'fr-id'),
      [
        projectLanguagesProvider('p').overrideWith((ref) async => [
              _pld('fr-id', 'fr', 'French', translated: 40, total: 100),
              _pld('de-id', 'de', 'German', translated: 10, total: 100),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('French'), findsOneWidget);
  });

  testWidgets('opens menu listing project languages with progress',
      (tester) async {
    await tester.pumpWidget(wrap(
      const EditorLanguageSwitcher(projectId: 'p', currentLanguageId: 'fr-id'),
      [
        projectLanguagesProvider('p').overrideWith((ref) async => [
              _pld('fr-id', 'fr', 'French', translated: 40, total: 100),
              _pld('de-id', 'de', 'German', translated: 10, total: 100),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-language-switcher-chip')));
    await tester.pumpAndSettle();

    expect(find.text('German'), findsWidgets);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('+ Add language'), findsOneWidget);
  });

  testWidgets('delete icon disabled when project has a single language',
      (tester) async {
    await tester.pumpWidget(wrap(
      const EditorLanguageSwitcher(projectId: 'p', currentLanguageId: 'fr-id'),
      [
        projectLanguagesProvider('p').overrideWith(
            (ref) async => [_pld('fr-id', 'fr', 'French', total: 10)]),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-language-switcher-chip')));
    await tester.pumpAndSettle();

    final trash = find.byKey(const Key('editor-language-delete-fr-id'));
    expect(trash, findsOneWidget);
    final button = tester.widget<IconButton>(trash);
    expect(button.onPressed, isNull);
  });
}
```

- [ ] **Step 4.2 — Run to confirm failure**

```
C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_language_switcher_test.dart
```

Expected: compilation failure (widget file doesn't exist).

- [ ] **Step 4.3 — Write the widget**

Create `lib/features/translation_editor/widgets/editor_language_switcher.dart`:

```dart
import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';
import 'package:twmt/features/projects/widgets/add_language_dialog.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Language switcher chip + popover used by the translation editor.
///
/// Renders the current language as a filled accent chip. Tapping opens a menu
/// listing every language declared in the project (with its progress %), a
/// trash affordance per language (disabled when the project has a single
/// language), and an "Add language" entry at the bottom that reuses
/// [AddLanguageDialog].
class EditorLanguageSwitcher extends ConsumerWidget {
  const EditorLanguageSwitcher({
    super.key,
    required this.projectId,
    required this.currentLanguageId,
  });

  final String projectId;
  final String currentLanguageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final langsAsync = ref.watch(projectLanguagesProvider(projectId));
    final langs = langsAsync.asData?.value ?? const <ProjectLanguageDetails>[];
    final current = langs
        .where((l) => l.projectLanguage.languageId == currentLanguageId)
        .firstOrNull;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      builder: (context, controller, _) {
        return _SwitcherChip(
          key: const Key('editor-language-switcher-chip'),
          label: current?.language.displayName ?? '—',
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        if (langs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No language in this project',
                style: tokens.fontBody.copyWith(
                    fontSize: 12, color: tokens.textDim)),
          )
        else
          for (final l in langs)
            _LanguageMenuItem(
              details: l,
              isCurrent: l.projectLanguage.languageId == currentLanguageId,
              canDelete: langs.length > 1,
              onSelect: () => _switchTo(context, l.projectLanguage.languageId),
              onDelete: () => _confirmDelete(context, ref, l),
            ),
        const Divider(height: 1),
        _AddLanguageMenuItem(
          onTap: () => _openAddDialog(context, ref, langs),
        ),
      ],
    );
  }

  void _switchTo(BuildContext context, String languageId) {
    if (languageId == currentLanguageId) return;
    context.go(AppRoutes.translationEditor(projectId, languageId));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ProjectLanguageDetails details,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Language'),
        content: Text(
            'Remove "${details.language.displayName}" from this project? '
            '${details.translatedUnits} translations will be deleted. '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final result = await ref
        .read(shared_repo.projectLanguageRepositoryProvider)
        .delete(details.projectLanguage.id);
    if (!context.mounted) return;

    if (result.isErr) {
      FluentToast.error(context, 'Failed to delete language: ${result.error}');
      return;
    }

    ref.invalidate(projectLanguagesProvider(projectId));
    unawaited(ref
        .read(projectsWithDetailsProvider.notifier)
        .refreshProject(projectId));

    if (details.projectLanguage.languageId == currentLanguageId) {
      await openProjectEditor(context, ref, projectId);
    }
  }

  Future<void> _openAddDialog(
    BuildContext context,
    WidgetRef ref,
    List<ProjectLanguageDetails> current,
  ) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AddLanguageDialog(
        projectId: projectId,
        existingLanguageIds:
            current.map((l) => l.projectLanguage.languageId).toList(),
      ),
    );
    if (added == true && context.mounted) {
      ref.invalidate(projectLanguagesProvider(projectId));
    }
  }
}

class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.accentBg,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.globe_24_regular,
                  size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(FluentIcons.chevron_down_24_regular,
                  size: 14, color: tokens.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageMenuItem extends StatelessWidget {
  const _LanguageMenuItem({
    required this.details,
    required this.isCurrent,
    required this.canDelete,
    required this.onSelect,
    required this.onDelete,
  });

  final ProjectLanguageDetails details;
  final bool isCurrent;
  final bool canDelete;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pct = details.progressPercent.toInt();
    return SizedBox(
      width: 280,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSelect,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      isCurrent
                          ? FluentIcons.checkmark_24_regular
                          : FluentIcons.translate_24_regular,
                      size: 16,
                      color: isCurrent ? tokens.accent : tokens.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(details.language.displayName,
                          style: tokens.fontBody.copyWith(
                              fontSize: 13, color: tokens.text)),
                    ),
                    Text('$pct%',
                        style: tokens.fontMono.copyWith(
                            fontSize: 12, color: tokens.textDim)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: Key('editor-language-delete-${details.projectLanguage.languageId}'),
            icon: Icon(FluentIcons.delete_24_regular,
                size: 16, color: canDelete ? tokens.err : tokens.textFaint),
            tooltip: canDelete
                ? 'Delete language'
                : 'Cannot delete the last language',
            onPressed: canDelete ? onDelete : null,
          ),
        ],
      ),
    );
  }
}

class _AddLanguageMenuItem extends StatelessWidget {
  const _AddLanguageMenuItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(FluentIcons.add_24_regular, size: 16, color: tokens.accent),
              const SizedBox(width: 8),
              Text('+ Add language',
                  style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4.4 — Run the test suite**

```
C:/src/flutter/bin/flutter test test/features/translation_editor/widgets/editor_language_switcher_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 4.5 — Commit**

```
git add lib/features/translation_editor/widgets/editor_language_switcher.dart \
        test/features/translation_editor/widgets/editor_language_switcher_test.dart
git commit -m "feat: add EditorLanguageSwitcher with switch, add, delete"
```

---

## Task 5 — Integrate switcher into `TranslationEditorScreen`

**Files:**
- Modify: `lib/features/translation_editor/screens/translation_editor_screen.dart`

**Rationale:** Placer `EditorLanguageSwitcher` dans `ListToolbarLeading.trailing` à droite du titre projet, et retirer le dernier `CrumbSegment(languageName)`. Également rendre le crumb projet inerte (`route: null`) puisqu'il n'y a plus d'écran intermédiaire à atteindre.

- [ ] **Step 5.1 — Update the toolbar construction**

Edit `lib/features/translation_editor/screens/translation_editor_screen.dart` around lines 211-261.

Replace the `FilterToolbar` leading block:

```dart
FilterToolbar(
  leading: ListToolbarLeading(
    icon: FluentIcons.folder_24_regular,
    title: projectName,
  ),
  trailing: [ /* search field ... */ ],
  ...
)
```

With:

```dart
FilterToolbar(
  leading: ListToolbarLeading(
    icon: FluentIcons.folder_24_regular,
    title: projectName,
    trailing: [
      EditorLanguageSwitcher(
        projectId: widget.projectId,
        currentLanguageId: widget.languageId,
      ),
    ],
  ),
  trailing: [ /* unchanged search field */ ],
  ...
)
```

Add the import:

```dart
import '../widgets/editor_language_switcher.dart';
```

- [ ] **Step 5.2 — Update breadcrumbs**

In the same file around line 213-220, replace the breadcrumb list:

```dart
crumbs: [
  const CrumbSegment('Work'),
  const CrumbSegment('Projects', route: AppRoutes.projects),
  CrumbSegment(
    projectName,
    route: AppRoutes.projectDetail(widget.projectId),
  ),
  CrumbSegment(languageName),
],
```

With:

```dart
crumbs: [
  const CrumbSegment('Work'),
  const CrumbSegment('Projects', route: AppRoutes.projects),
  CrumbSegment(projectName),
],
```

Remove the now-unused `languageName` local when it is no longer referenced. The `languageAsync` watch can stay since it drives other things (confirm by `flutter analyze` after — otherwise remove the watch too).

- [ ] **Step 5.3 — Run editor tests to confirm no regression**

```
C:/src/flutter/bin/flutter test test/features/translation_editor/
```

Some existing tests (e.g. `editor_filter_toolbar_test.dart`) may stub `projectLanguagesProvider` — if a new test failure arises there, add an override providing an empty list and a stubbed `currentLanguage`. Any required override is:

```dart
projectLanguagesProvider(projectId).overrideWith((ref) async => [
  // at least one entry matching languageId so the chip renders a name
]),
```

Keep the fix focused on the test that broke; don't globally restructure.

- [ ] **Step 5.4 — Commit**

```
git add lib/features/translation_editor/screens/translation_editor_screen.dart \
        test/features/translation_editor/widgets/editor_filter_toolbar_test.dart
git commit -m "feat: embed language switcher in translation editor toolbar"
```

(omit the test file if it didn't need updates)

---

## Task 6 — Wizard 2 steps

**Files:**
- Modify: `lib/features/projects/widgets/create_project/create_project_dialog.dart`
- Modify: `lib/features/projects/widgets/create_project/project_creation_state.dart`
- Delete: `lib/features/projects/widgets/create_project/step_languages.dart`
- Delete: `test/features/projects/widgets/create_project/create_project_dialog_language_validation_test.dart`

**Rationale:** Le wizard perd l'étape 2 ; la création crée un seul `ProjectLanguage` pour la langue par défaut des settings (avec fallback sur la première langue active).

- [ ] **Step 6.1 — Remove `selectedLanguageIds`**

Edit `project_creation_state.dart`:

```dart
class ProjectCreationState {
  // Step 1: Basic info
  final TextEditingController nameController = TextEditingController();
  final TextEditingController modSteamIdController = TextEditingController();
  final TextEditingController sourceFileController = TextEditingController();
  final TextEditingController outputFileController = TextEditingController();
  String? selectedGameId;
  WorkshopMod? workshopMod;

  // Step 2: Settings (was step 3)
  final TextEditingController batchSizeController = TextEditingController(text: '25');
  final TextEditingController parallelBatchesController = TextEditingController(text: '3');
  final TextEditingController customPromptController = TextEditingController();

  final DetectedMod? detectedMod;

  ProjectCreationState({this.detectedMod}) {
    if (detectedMod != null) {
      nameController.text = detectedMod!.name;
      sourceFileController.text = detectedMod!.packFilePath;
      modSteamIdController.text = detectedMod!.workshopId;
    }
  }

  void dispose() {
    nameController.dispose();
    modSteamIdController.dispose();
    sourceFileController.dispose();
    outputFileController.dispose();
    batchSizeController.dispose();
    parallelBatchesController.dispose();
    customPromptController.dispose();
  }
}
```

- [ ] **Step 6.2 — Rework the dialog to 2 steps**

Edit `create_project_dialog.dart`.

Remove the `step_languages.dart` import.

Change step count / headers:

```dart
WizardStepHeader(
  stepNumber: _currentStep + 1,
  totalSteps: 2,
  title: const [
    'Basic info',
    'Translation settings',
  ][_currentStep],
),
```

Update `_nextStep`:

```dart
void _nextStep() {
  if (_currentStep < 1) {
    if (_validateCurrentStep()) {
      setState(() => _currentStep++);
    }
  } else {
    _createProject();
  }
}
```

Update `_validateCurrentStep` — drop the `_currentStep == 1` (language) block:

```dart
bool _validateCurrentStep() {
  if (_currentStep == 0) {
    if (!_formKey.currentState!.validate()) return false;
    if (_state.selectedGameId == null) {
      setState(() => _errorMessage = 'Please select a game installation');
      return false;
    }
  }
  setState(() => _errorMessage = null);
  return true;
}
```

Update `_buildStepContent`:

```dart
Widget _buildStepContent() {
  return switch (_currentStep) {
    0 => StepBasicInfo(state: _state, formKey: _formKey),
    1 => StepSettings(state: _state),
    _ => const SizedBox.shrink(),
  };
}
```

Update the footer next-button logic from `_currentStep < 2` to `_currentStep < 1`:

```dart
SmallTextButton(
  label: _currentStep < 1 ? 'Next' : 'Create',
  icon: _currentStep < 1
      ? FluentIcons.arrow_right_24_regular
      : FluentIcons.play_24_regular,
  onTap: _isLoading ? null : _nextStep,
),
```

- [ ] **Step 6.3 — Create the single project language**

In `create_project_dialog.dart`, replace the existing language-creation block inside `_createProject`:

```dart
// Create project languages
for (final languageId in _state.selectedLanguageIds) {
  final projectLanguage = ProjectLanguage(
    id: uuid.v4(),
    projectId: projectId,
    languageId: languageId,
    progressPercent: 0.0,
    createdAt: now,
    updatedAt: now,
  );
  await projectLangRepo.insert(projectLanguage);
}
```

With:

```dart
// Resolve default target language and create a single project language.
final settings = ref.read(settingsServiceProvider);
final defaultCode = await settings.getString(
  SettingsKeys.defaultTargetLanguage,
  defaultValue: SettingsKeys.defaultTargetLanguageValue,
);
final langRepo = ref.read(languageRepositoryProvider);
Language? target;
final byCode = await langRepo.getByCode(defaultCode);
if (byCode.isOk) {
  target = byCode.unwrap();
}
if (target == null || !target.isActive) {
  // Fallback: first active language.
  final active = await langRepo.getActive();
  if (active.isErr || active.unwrap().isEmpty) {
    throw Exception('No active language available to create project');
  }
  target = active.unwrap().first;
}
final projectLanguage = ProjectLanguage(
  id: uuid.v4(),
  projectId: projectId,
  languageId: target.id,
  progressPercent: 0.0,
  createdAt: now,
  updatedAt: now,
);
await projectLangRepo.insert(projectLanguage);
```

Add the imports at the top of the file:

```dart
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart'
    show languageRepositoryProvider;
import '../../../../models/domain/language.dart';
```

- [ ] **Step 6.4 — Delete `step_languages.dart`**

```
git rm lib/features/projects/widgets/create_project/step_languages.dart
```

- [ ] **Step 6.5 — Delete the obsolete language-validation test**

```
git rm test/features/projects/widgets/create_project/create_project_dialog_language_validation_test.dart
```

- [ ] **Step 6.6 — Verify compile + analyze**

```
C:/src/flutter/bin/flutter analyze lib/features/projects/widgets/create_project/
```

Expected: no errors (warnings about unused helpers acceptable; fix before commit).

- [ ] **Step 6.7 — Commit**

```
git add lib/features/projects/widgets/create_project/create_project_dialog.dart \
        lib/features/projects/widgets/create_project/project_creation_state.dart
git commit -m "feat: shrink create-project wizard to two steps with default language"
```

---

## Task 7 — `_ProjectRow` enhancements in `projects_screen.dart`

**Files:**
- Modify: `lib/features/projects/screens/projects_screen.dart`
- Modify: `test/features/projects/screens/projects_screen_test.dart`

**Rationale:** La liste des projets (`projects_screen.dart`) utilise `_ProjectRow` (layout `ListRow` en colonnes), pas `ProjectCard`. Cible réelle du refactor : fusionner les colonnes "Language" (140px) + "Progress" (200px) en une seule colonne "Languages" plus large qui affiche **une mini-barre par langue du projet** avec `nom · barre · %`, chacune cliquable pour ouvrir l'éditeur sur cette langue. Ajouter une icône corbeille en `trailingAction` du `ListRow`. Rendre l'icône Steam (cloud + modSteamId) cliquable pour ouvrir Steam Workshop. Le tap du reste de la ligne appelle `openProjectEditor`.

- [ ] **Step 7.1 — Redefine `_projectColumns` layout**

Edit `lib/features/projects/screens/projects_screen.dart` around line 733.

Replace:

```dart
const List<ListRowColumn> _projectColumns = [
  ListRowColumn.fixed(56), // cover
  ListRowColumn.flex(3), // name + meta
  ListRowColumn.fixed(140), // target language
  ListRowColumn.fixed(200), // progress
  ListRowColumn.fixed(180), // last modified
  ListRowColumn.fixed(150), // status pill
];
```

With:

```dart
const List<ListRowColumn> _projectColumns = [
  ListRowColumn.fixed(56), // cover
  ListRowColumn.flex(3), // name + meta
  ListRowColumn.flex(2), // languages + per-language progress
  ListRowColumn.fixed(180), // last modified
  ListRowColumn.fixed(150), // status pill
];

// Matches the IconButton footprint (16px icon + 12px padding) reserved on
// the list header for the trailing delete action.
const double _projectRowTrailingActionWidth = 40;
```

Update the header labels in `_ProjectsListHeader.build` (around line 747):

```dart
return ListRowHeader(
  columns: _projectColumns,
  labels: const ['', 'Project', 'Languages & progress', 'Modified', 'Status'],
  trailingActionWidth: _projectRowTrailingActionWidth,
);
```

- [ ] **Step 7.2 — Extend `_ProjectRow` constructor with new callbacks**

Still in `projects_screen.dart`, around line 754, replace the `_ProjectRow` constructor:

```dart
class _ProjectRow extends StatelessWidget {
  final ProjectWithDetails details;
  final bool selected;
  final bool isResyncing;
  final VoidCallback onTap;
  final VoidCallback onResync;
  final VoidCallback onDelete;
  final ValueChanged<String> onOpenLanguage; // languageId
  final ValueChanged<String> onLaunchSteam; // modSteamId

  const _ProjectRow({
    required this.details,
    required this.selected,
    required this.isResyncing,
    required this.onTap,
    required this.onResync,
    required this.onDelete,
    required this.onOpenLanguage,
    required this.onLaunchSteam,
  });
```

- [ ] **Step 7.3 — Make the Steam cloud icon clickable in `_ProjectRow.build`**

Around lines 812-827 (the Steam cloud icon block inside the "name + meta" column), replace:

```dart
if (project.modSteamId != null) ...[
  Icon(
    FluentIcons.cloud_24_regular,
    size: 12,
    color: tokens.textDim,
  ),
  const SizedBox(width: 4),
  Text(
    project.modSteamId!,
    style: tokens.fontMono.copyWith(
      fontSize: 11,
      color: tokens.textDim,
    ),
  ),
] else if ...
```

With:

```dart
if (project.modSteamId != null) ...[
  _SteamLinkPill(
    modSteamId: project.modSteamId!,
    onTap: () => onLaunchSteam(project.modSteamId!),
  ),
] else if ...
```

Then at the bottom of the file (near the other helpers), add:

```dart
class _SteamLinkPill extends StatelessWidget {
  const _SteamLinkPill({required this.modSteamId, required this.onTap});
  final String modSteamId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: 'Open in Steam Workshop',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.cloud_24_regular,
                    size: 12, color: tokens.textDim),
                const SizedBox(width: 4),
                Text(
                  modSteamId,
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7.4 — Replace "target language" + "progress" cells with a languages column**

Around lines 871-906 in `_ProjectRow.build`, delete both the "Target language column" and the "Progress column" `Padding` children. Replace with a single cell:

```dart
// Languages column — one clickable mini-progress-row per language.
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  child: _RowLanguagesCell(
    languages: details.languages,
    onOpenLanguage: onOpenLanguage,
  ),
),
```

And add the helper widget near the other row helpers:

```dart
class _RowLanguagesCell extends StatelessWidget {
  const _RowLanguagesCell({
    required this.languages,
    required this.onOpenLanguage,
  });

  final List<ProjectLanguageWithInfo> languages;
  final ValueChanged<String> onOpenLanguage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (languages.isEmpty) {
      return Text('No target language',
          style: tokens.fontBody.copyWith(
              fontSize: 12, color: tokens.textFaint));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in languages)
          _RowLanguageLine(
            details: l,
            onTap: () => onOpenLanguage(l.projectLanguage.languageId),
          ),
      ],
    );
  }
}

class _RowLanguageLine extends StatelessWidget {
  const _RowLanguageLine({required this.details, required this.onTap});
  final ProjectLanguageWithInfo details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final percent = details.progressPercent.clamp(0.0, 100.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  details.language?.name ?? 'Unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textMid,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 4,
                    backgroundColor: tokens.border,
                    valueColor: AlwaysStoppedAnimation(tokens.accent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 38,
                child: Text(
                  '${percent.toInt()}%',
                  textAlign: TextAlign.right,
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: tokens.textDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add the missing import near the top of the file:

```dart
import '../providers/projects_screen_providers.dart'
    show ProjectLanguageWithInfo, ProjectWithDetails;
```

(If the file already imports the providers file for `ProjectWithDetails`, just ensure `ProjectLanguageWithInfo` is in the `show` list or that the import isn't filtered.)

- [ ] **Step 7.5 — Pass `trailingAction` (delete icon) to the `ListRow`**

In `_ProjectRow.build`, find the `return ListRow(` around line 785 and add `trailingAction:`:

```dart
return ListRow(
  columns: _projectColumns,
  selected: selected,
  onTap: onTap,
  trailingAction: IconButton(
    icon: const Icon(FluentIcons.delete_24_regular, size: 16),
    tooltip: 'Delete project',
    onPressed: onDelete,
    color: Theme.of(context).colorScheme.error,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
  ),
  children: [
    // ... existing children (minus the dropped language/progress cells) ...
  ],
);
```

- [ ] **Step 7.6 — Wire callbacks and handlers in the list builder**

Around lines 196-210, update `itemBuilder`:

```dart
return _ProjectRow(
  details: details,
  selected: isSelected,
  isResyncing: resyncState.resyncingProjects.contains(projectId),
  onTap: () {
    if (selectionState.isSelectionMode) {
      ref
          .read(batchProjectSelectionProvider.notifier)
          .toggleProject(projectId);
    } else {
      openProjectEditor(context, ref, projectId);
    }
  },
  onResync: () => _handleResync(context, projectId),
  onDelete: () => _handleDeleteProject(context, details),
  onOpenLanguage: (languageId) =>
      context.go(AppRoutes.translationEditor(projectId, languageId)),
  onLaunchSteam: (modId) => _launchSteamWorkshop(modId),
);
```

Add the handler methods inside `_ProjectsScreenState` (near `_handleResync`):

```dart
Future<void> _launchSteamWorkshop(String modId) async {
  final url = Uri.parse(
      'https://steamcommunity.com/sharedfiles/filedetails/?id=$modId');
  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  }
}

void _handleDeleteProject(BuildContext context, ProjectWithDetails details) {
  showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Delete Project'),
      content: Text(
          'Are you sure you want to delete "${details.project.name}"? This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(dialogCtx).pop();
            final result = await ref
                .read(shared_repo.projectRepositoryProvider)
                .delete(details.project.id);
            if (!context.mounted) return;
            if (result.isOk) {
              ref
                  .read(projectsWithDetailsProvider.notifier)
                  .removeProject(details.project.id);
              FluentToast.success(
                  context, 'Project "${details.project.name}" deleted');
            } else {
              FluentToast.error(
                  context, 'Failed to delete project: ${result.error}');
            }
          },
          child: Text('Delete',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ),
  );
}
```

Add the imports at the top of `projects_screen.dart` (keep the existing ones):

```dart
import 'package:url_launcher/url_launcher.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';
```

- [ ] **Step 7.7 — Run analyze + existing tests**

```
C:/src/flutter/bin/flutter analyze lib/features/projects/
C:/src/flutter/bin/flutter test test/features/projects/screens/projects_screen_test.dart
```

Expected: analyze is clean. The `projects_screen_test.dart` may reference `AppRoutes.projectDetail` in its assertions (see line 149: "row's onTap called `context.go(AppRoutes.projectDetail('p1'))`"). Update the relevant test case to expect a navigation toward `AppRoutes.translationEditor('p1', <langId>)` — the simplest fix is to override `projectLanguagesProvider('p1')` with a deterministic list and check for `startsWith('/work/projects/p1/editor/')` on the most recent route. Keep that fix in the same commit.

- [ ] **Step 7.8 — Commit**

```
git add lib/features/projects/screens/projects_screen.dart \
        test/features/projects/screens/projects_screen_test.dart
git commit -m "feat: per-language progress + delete + steam actions on project rows"
```

---

## Task 8 — Delete `ProjectDetailScreen`, route and dead providers

**Files:**
- Delete: `lib/features/projects/screens/project_detail_screen.dart`
- Delete: `lib/features/projects/widgets/language_progress_row.dart`
- Delete: `test/features/projects/screens/project_detail_screen_test.dart`
- Delete: `test/features/projects/widgets/language_progress_row_test.dart`
- Modify: `lib/config/router/app_router.dart`
- Modify: `lib/features/projects/providers/project_detail_providers.dart`
- Modify: `test/config/router/app_router_test.dart`

**Rationale:** Une fois tous les callers migrés (Tasks 2-3) et l'UI alternative livrée (Tasks 4-7), le detail-screen n'a plus de consommateurs. On peut le retirer ainsi que son provider dédié.

- [ ] **Step 8.1 — Confirm no remaining references**

```
C:/src/flutter/bin/flutter analyze
```

Also:

```bash
grep -rn "projectDetail\b\|projectDetailsProvider\|goProjectDetail" lib/ test/
```

Expected: only references are in the files about to be deleted (router, provider, tests). If anything else surfaces, loop back to Tasks 2/3/5.

- [ ] **Step 8.2 — Remove route and helper from `app_router.dart`**

Edit `lib/config/router/app_router.dart`:

Remove line 73:
```dart
static String projectDetail(String projectId) => '$projects/$projectId';
```

Remove the corresponding `GoRoute` block (around lines 180-210) :

```dart
GoRoute(
  path: ':${AppRoutes.projectIdParam}',
  name: 'projectDetail',
  pageBuilder: (context, state) { ... },
  routes: [
    GoRoute(
      path: 'editor/:${AppRoutes.languageIdParam}',
      ...
    ),
  ],
),
```

Replace with a flat editor route at the same depth as `batch-export` (editor keeps the same URL shape):

```dart
GoRoute(
  path: ':${AppRoutes.projectIdParam}/editor/:${AppRoutes.languageIdParam}',
  name: 'translationEditor',
  pageBuilder: (context, state) {
    final projectId = state.pathParameters[AppRoutes.projectIdParam]!;
    final languageId = state.pathParameters[AppRoutes.languageIdParam]!;
    return FluentPageTransitions.slideFromRightTransition(
      child: TranslationEditorScreen(
        projectId: projectId,
        languageId: languageId,
      ),
      state: state,
    );
  },
),
```

Remove the `goProjectDetail` extension method (line 395):

```dart
void goProjectDetail(String projectId) => go(AppRoutes.projectDetail(projectId));
```

Remove the now-unused `ProjectDetailScreen` import.

- [ ] **Step 8.3 — Update `app_router_test.dart`**

Edit `test/config/router/app_router_test.dart` around lines 63-65. Replace:

```dart
test('projectDetail composes /work/projects/<id>', () {
  expect(AppRoutes.projectDetail('abc'), '/work/projects/abc');
});
```

With:

```dart
test('translationEditor composes /work/projects/<id>/editor/<lang>', () {
  expect(
    AppRoutes.translationEditor('abc', 'fr'),
    '/work/projects/abc/editor/fr',
  );
});
```

(Keep other test cases intact.)

- [ ] **Step 8.4 — Shrink the provider file**

Edit `lib/features/projects/providers/project_detail_providers.dart`:

- Delete `ProjectDetails` class.
- Delete `TranslationStats` class (confirm no other import references it — `ripgrep` — if it's referenced from `EditorStatusBar` or elsewhere, hold off and convert those consumers first).
- Delete `projectDetailsProvider`.
- Keep `ProjectLanguageDetails`, `projectLanguagesProvider`, `translationStatsProvider` (widely used).

After the edit the file should only contain: imports, `ProjectLanguageDetails`, `projectLanguagesProvider`, and `translationStatsProvider` (if kept).

Also update the file's top-level `export` line (re-export of repositories) if it still serves consumers; otherwise drop it.

- [ ] **Step 8.5 — Delete the detail screen files**

```
git rm lib/features/projects/screens/project_detail_screen.dart
git rm lib/features/projects/widgets/language_progress_row.dart
git rm test/features/projects/screens/project_detail_screen_test.dart
git rm test/features/projects/widgets/language_progress_row_test.dart
```

- [ ] **Step 8.6 — Run the full suite**

```
C:/src/flutter/bin/flutter analyze
C:/src/flutter/bin/flutter test
```

Expected: analyze clean, full test suite green. If a test references the deleted types (e.g. `TranslationStats`), trace and either update the test to use live stats or delete the obsolete test assertion.

- [ ] **Step 8.7 — Commit**

```
git add lib/config/router/app_router.dart \
        lib/features/projects/providers/project_detail_providers.dart \
        test/config/router/app_router_test.dart
git commit -m "chore: delete project detail screen, route and dead providers"
```

---

## Self-Review Notes

- Spec § "Règles décisionnelles retenues" row 1 → Task 1 (`resolveTargetLanguageId`).
- Spec § "Règles décisionnelles retenues" row 2 → Task 6.
- Spec § "Règles décisionnelles retenues" row 3 → Tasks 4 + 5.
- Spec § "Règles décisionnelles retenues" row 4 → Task 7.
- Spec § "Règles décisionnelles retenues" row 5 → Task 7 (`onOpenLanguage` callback).
- Spec § "Architecture > Routage" → Tasks 2, 3, 8.
- Spec § "Architecture > Écran `ProjectDetailScreen` et providers" → Task 8.
- Spec § "Gestion des edge cases" row "langue courante supprimée" → Task 4 `_confirmDelete` calling `openProjectEditor`.
- Spec § "Gestion des edge cases" row "projet sans langue" → Task 1 `resolveTargetLanguageId` returning null + Task 1 `openProjectEditor` toast branch.
- Spec § "Gestion des edge cases" row "default langue absente/désactivée" → Task 1 resolve fallback + Task 6 Step 6.3 fallback.
- Spec § "Gestion des edge cases" row "clic barre pendant sélection" → Task 7 Step 7.4 `isSelectionMode ? null`.

All spec requirements map to a task.
