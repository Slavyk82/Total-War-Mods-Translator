# Remove Project Detail Screen — Design

**Date:** 2026-04-21
**Status:** Proposed

## Summary

Supprimer complètement l'écran intermédiaire `ProjectDetailScreen` qui liste les langues d'un projet. L'ouverture d'un projet mène directement à l'éditeur de traduction, sur une langue résolue automatiquement. L'éditeur gagne un sélecteur de langue permettant de basculer entre les langues déjà déclarées dans le projet et d'en ajouter de nouvelles (parmi celles des settings). La création de projet n'inclut plus l'étape "Target languages" — seule la langue par défaut des settings est créée. Les actions projet-level (supprimer, ouvrir dans Steam Workshop) migrent sur la carte projet dans l'écran "Projects".

## Motivation

L'écran intermédiaire est un saut de navigation qui n'apporte rien pour les projets à une seule langue (le cas nominal après refactor), et qui peut être remplacé par un sélecteur in-place pour les projets multi-langues.

## Règles décisionnelles retenues

| # | Décision |
|---|---|
| 1 | Ouverture d'un projet : langue par défaut des settings si présente dans le projet, sinon première langue du projet (ordre de création). |
| 2 | Création de projet : étape 2 du wizard supprimée ; une seule langue cible créée, correspondant à `SettingsKeys.defaultTargetLanguage`. |
| 3 | Sélecteur de langue : bouton dédié dans la `FilterToolbar` de l'éditeur, à côté du titre projet. |
| 4 | Actions projet-level (Delete, Steam Workshop) : relocalisées sur la carte projet (`ProjectCard`), en icônes directes en haut à droite de la carte. |
| 5 | Clic sur une barre de progression de langue dans la carte projet : ouvre l'éditeur directement sur cette langue. Clic ailleurs sur la carte : applique la règle #1. |

## Architecture

### 1. Routage

- Suppression de `AppRoutes.projectDetail` et de son `GoRoute` (`/work/projects/:projectId`) dans `app_router.dart`.
- Suppression de l'extension `goProjectDetail`.
- Conservation de `AppRoutes.translationEditor` et de son `GoRoute` imbriqué — reste la seule URL accessible sous un projet.
- Ajout d'un helper async unique qui centralise la résolution de langue + navigation :

  ```dart
  // lib/features/projects/utils/open_project_editor.dart
  Future<void> openProjectEditor(
    BuildContext context,
    WidgetRef ref,
    String projectId,
  );
  ```

  Implémentation :
  1. `final langs = await ref.read(projectLanguagesProvider(projectId).future);`
  2. `final defaultCode = await ref.read(settingsServiceProvider).getString(SettingsKeys.defaultTargetLanguage, defaultValue: SettingsKeys.defaultTargetLanguageValue);`
  3. Résolution : `langs.firstWhere((l) => l.language.code == defaultCode, orElse: () => langs.first)`.
  4. Si `langs.isEmpty` → `FluentToast.warning(context, 'Projet sans langue cible'); context.go(AppRoutes.projects);`.
  5. Sinon `context.go(AppRoutes.translationEditor(projectId, resolved.projectLanguage.languageId));`.

- Tous les appelants actuels de `AppRoutes.projectDetail(projectId)` migrent vers `openProjectEditor(...)`. Fichiers concernés :
  - `lib/features/mods/utils/mods_screen_controller.dart` (3 sites).
  - `lib/features/mods/widgets/whats_new_dialog.dart`.
  - `lib/features/game_translation/screens/game_translation_screen.dart`.
  - `lib/features/home/widgets/recent_projects_list.dart`.
  - `lib/features/projects/screens/projects_screen.dart` (+ `ProjectCard` onTap via parent).

### 2. Écran `ProjectDetailScreen` et providers

- **Suppression** de `lib/features/projects/screens/project_detail_screen.dart`.
- `lib/features/projects/providers/project_detail_providers.dart` :
  - `projectDetailsProvider` → supprimé (plus de consommateur).
  - `ProjectDetails` et `TranslationStats` (stats projet-level) → supprimés s'ils ne sont consommés que par ce provider. Vérifier avec grep.
  - `ProjectLanguageDetails` et `projectLanguagesProvider` → **conservés** (utilisés par le helper, éventuellement par la carte projet).
  - `translationStatsProvider` → conservé uniquement s'il est utilisé ailleurs (vérifier ; sinon supprimer).
- **Suppression** de `lib/features/projects/widgets/language_progress_row.dart` (consommé uniquement par l'écran détail).
- Composants de layout détail (`detail_meta_banner`, `detail_overview_layout`, `stats_rail`, `crumb_segment`) : conservés tant qu'ils sont utilisés par d'autres écrans détail (pack compilation, etc.) — ne pas toucher.

### 3. Sélecteur de langue dans l'éditeur

Nouveau widget `EditorLanguageSwitcher` sous `lib/features/translation_editor/widgets/editor_language_switcher.dart`.

**Contrat :**
```dart
class EditorLanguageSwitcher extends ConsumerWidget {
  final String projectId;
  final String currentLanguageId;
}
```

**UI :**
- Chip aux styles `SmallTextButton` filled (fond `tokens.accentBg`, texte `tokens.accent`) : `[🌐 Français ▾]`.
- Au clic, ouvre un `MenuAnchor` (Material 3) positionné sous le chip.
- Contenu du menu :
  - En-tête : libellé "LANGUAGES".
  - Liste des langues du projet triées par `createdAt` :
    - Nom + pastille de progression `xx%` (data issue de `projectLanguagesProvider(projectId)` — utilise `ProjectLanguageDetails` avec ses stats).
    - Indicateur check si c'est la langue courante.
    - Icône corbeille à droite (désactivée si c'est la seule langue du projet ; tooltip "Impossible de supprimer la dernière langue").
  - Séparateur.
  - Item accentué `+ Add language` → ouvre `AddLanguageDialog` existant.
- Interactions :
  - Tap ligne de langue : `context.go(AppRoutes.translationEditor(projectId, langId))`.
  - Tap corbeille : dialog de confirmation puis `projectLanguageRepository.delete(projectLanguageId)` + invalidation de `projectLanguagesProvider(projectId)` ; si la langue supprimée est la langue courante, `openProjectEditor(ctx, ref, projectId)` pour rebasculer.
  - Tap `+ Add language` : après `Navigator.pop(true)` du dialog, si une seule langue a été ajoutée et qu'on reste sur la langue courante, rester ; sinon, `openProjectEditor` (laisser la règle #1 gérer).

**Intégration :** `TranslationEditorScreen.build` place le switcher dans `FilterToolbar.leading` à droite de `ListToolbarLeading(title: projectName)`. La `FilterToolbar` accepte déjà une liste `leading` / `trailing` — vérifier et adapter si nécessaire (peut impliquer un petit changement dans `FilterToolbar` pour accepter un second widget leading).

**Breadcrumbs :** le dernier crumb `CrumbSegment(languageName)` est retiré — on s'arrête à `Work > Projects > [Project name]` où le crumb `Project name` est l'éditeur lui-même (inerte : `route: null`).

### 4. Wizard de création de projet

Fichiers affectés : `lib/features/projects/widgets/create_project/`.

- `create_project_dialog.dart` :
  - `WizardStepHeader`: `totalSteps: 2`, titres `['Basic info', 'Translation settings']`.
  - `_currentStep` max = 1 au lieu de 2, `_nextStep` déclenche `_createProject` quand `_currentStep == 1`.
  - `_validateCurrentStep` : suppression du bloc `_currentStep == 1` (langues).
  - `_buildStepContent` : switch passe de 3 à 2 cases.
  - `_createProject` : remplace la boucle `for (final languageId in _state.selectedLanguageIds)` par :
    1. `final defaultCode = await ref.read(settingsServiceProvider).getString(SettingsKeys.defaultTargetLanguage, defaultValue: SettingsKeys.defaultTargetLanguageValue);`
    2. `final langResult = await ref.read(languageRepositoryProvider).getByCode(defaultCode);`
    3. Si erreur / langue désactivée → fallback sur première langue active + log warning.
    4. Créer un `ProjectLanguage` unique avec ce `languageId`.
- `project_creation_state.dart` : `selectedLanguageIds` supprimé.
- `step_languages.dart` : **fichier supprimé**.
- Navigation post-création : plutôt que `Navigator.pop(projectId)`, le dialogue peut toujours renvoyer l'ID. Les callers de `CreateProjectDialog` doivent naviguer vers l'éditeur via `openProjectEditor` au lieu de `goProjectDetail`.

### 5. Carte projet (`ProjectCard`)

Fichier : `lib/features/projects/widgets/project_card.dart`.

**Header (`_buildHeader`) :**
- L'icône cloud + `modSteamId` devient un bloc cliquable : `InkWell` tooltip "Open in Steam Workshop" → `launchUrl(Uri.parse('https://steamcommunity.com/sharedfiles/filedetails/?id=$modSteamId'))`. Stoppe la propagation.
- **Nouveau** : icône `FluentIcons.delete_24_regular` tout à droite (après le badge changes et l'icône Steam), rouge discret (`tokens.err` + opacity), tooltip "Delete project". Tap : dialog de confirmation (reprend `_performDeleteProject` du `ProjectDetailScreen` — à déplacer ici). Stoppe la propagation.

**Barres de progression (`_buildLanguageProgress` / `_buildProgressBar`) :**
- Chaque ligne langue devient un `MouseRegion` + `GestureDetector` (ou `InkWell`) :
  - Tap → `context.go(AppRoutes.translationEditor(project.id, langId))`. Stoppe la propagation vers le `onTap` de la carte.
  - Mode sélection (`isSelectionMode == true`) : les barres ne sont PAS cliquables — le tap capture vers sélection comme le reste.
- `ProjectLanguageProgress` dans `ProjectWithDetails` doit exposer `projectLanguage.id` et `languageId` (vérifier — sinon étendre).

**`onTap` par défaut de la carte :** appelle `openProjectEditor(ctx, ref, project.id)` (passé via `onTap` depuis `ProjectsScreen`).

### 6. Suppression et nettoyage

Fichiers supprimés :
- `lib/features/projects/screens/project_detail_screen.dart`
- `lib/features/projects/widgets/create_project/step_languages.dart`
- `lib/features/projects/widgets/language_progress_row.dart`

Providers nettoyés :
- `projectDetailsProvider` (dans `project_detail_providers.dart`).
- `ProjectDetails`, `TranslationStats` (si sans autre consommateur).

Tests supprimés / mis à jour :
- Tests `ProjectDetailScreen` → suppression.
- Tests `StepLanguages` → suppression.
- Tests `CreateProjectDialog` → adaptés au wizard 2-étapes.
- Tests `ProjectCard` → ajout des icônes Delete/Steam + clic sur barres langue.
- Tests nouveaux : `EditorLanguageSwitcher`, `openProjectEditor` helper.

### 7. Gestion des edge cases

| Cas | Comportement |
|---|---|
| Projet ouvert, langue courante supprimée via le switcher. | `openProjectEditor` relance la résolution → navigation vers une autre langue. Si c'était la dernière, la corbeille est désactivée donc on n'y arrive pas. |
| Projet créé avant refactor sans aucune langue (données legacy). | `openProjectEditor` détecte `langs.isEmpty` → toast + redirection `AppRoutes.projects`. |
| `SettingsKeys.defaultTargetLanguage` pointe sur une langue désactivée ou absente. | Fallback silencieux sur première langue active (création) ou première langue du projet (ouverture). |
| Clic sur une barre de langue pendant mode sélection. | Tap propagé à la sélection (comportement actuel). |

## Ordre d'implémentation

1. **Helper `openProjectEditor`** + mise à jour des 6 callers existants. Le router conserve temporairement la route `projectDetail` pour ne rien casser.
2. **`EditorLanguageSwitcher`** dans l'éditeur (ajout non destructif).
3. **Wizard 2 étapes** — suppression de `step_languages.dart` et adaptation du flow.
4. **`ProjectCard`** — icônes Delete/Steam + barres langue cliquables.
5. **Suppression finale** : route `projectDetail`, `ProjectDetailScreen`, providers morts, tests obsolètes.

Chaque étape est indépendante et peut être commitée séparément, la suppression de la route arrivant en dernier.

## Tests à ajouter

- `test/features/projects/utils/open_project_editor_test.dart` : règle B, langue inexistante, liste vide.
- `test/features/translation_editor/widgets/editor_language_switcher_test.dart` : ouverture popover, switch, corbeille désactivée sur dernière langue, add language.
- `test/features/projects/widgets/create_project/create_project_dialog_test.dart` : wizard 2 étapes, création avec langue par défaut.
- `test/features/projects/widgets/project_card_test.dart` : tap sur barre langue → route éditeur, tap icône delete → dialog, tap icône Steam → `launchUrl`.

## Non-objectifs

- Pas de mémorisation de "dernière langue consultée par projet" — règle B uniquement.
- Pas de rail de stats projet-level ailleurs dans l'app ; les stats par langue existantes (`EditorStatusBar`) suffisent.
- Aucun refactor de `FilterToolbar` au-delà de ce qui est strictement nécessaire pour loger le switcher.
