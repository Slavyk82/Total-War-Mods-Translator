# TWMT — UI redesign — Plan 4 (Translation Editor) — design spec

**Date:** 2026-04-16
**Status:** design · pending implementation plan
**Parent spec:** [`2026-04-14-ui-redesign-design.md`](./2026-04-14-ui-redesign-design.md) §7.3
**Reference mockup:** `.superpowers/brainstorm/2035-1776190006/content/editor-mix.html`
**Predecessor plans:** Plan 1 (Foundation, shipped), Plan 2 (Navigation, shipped), Plan 3 (Home, shipped)
**Branch (proposed):** `feat/ui-editor`

---

## 1. Intent

Refonte de l'écran d'édition de traduction (`TranslationEditorScreen`) pour matérialiser l'archétype "Éditeur dense" de la spec parente §7.3 : toolbar compacte, 3 colonnes (filtres / grille / inspector), statusbar de métriques live. Densité power-user : voir 10–15 unités sans scroll, éditer la cible directement dans l'inspector sans modal, raccourcis clavier visibles, suggestions TM à un clic.

Aujourd'hui l'écran est un layout 2-colonnes (sidebar 200px + grille) avec un `FluentScaffold` header, sans inspector, sans statusbar, et un `EditorBottomPanel` orphelin (jamais wiré) qui contient pourtant déjà des panels TM/History/Validation prêts à servir.

**Non-objectifs :**
- Refonte des 6 dialogs de traduction (Settings, History, PromptPreview, ValidationEdit, ModRule, Export) — reste pour Plan 5.
- Refonte de `ValidationReviewScreen` (écran séparé) — reste pour Plan 5.
- Réécriture du widget `SfDataGrid` — on garde le moteur, on retokenise et on restructure le squelette autour.
- Nouvelles features fonctionnelles — aucune action n'est ajoutée ou retirée, uniquement réorganisée.

---

## 2. Decisions

| # | Question | Décision |
|---|---|---|
| 1 | Scope | Editor screen seul. Dialogs et ValidationReviewScreen restent inchangés (Plan 5). |
| 2 | Contenu inspector | 3 sections empilées : Source/Target (édition inline) → TM Suggestions → Validation. History reléguée au dialog existant. |
| 3 | Stats sidebar vs statusbar | Statusbar = stats live ; sidebar dégraissée à filtres only. Tokens/cost skippés (pas de tracking session). |
| 4 | Search vs CmdK | Search filter rows avec look cmdk + raccourci `Ctrl+F` (find). `Ctrl+K` réservé pour palette future. |
| 5 | Densité toolbar | 5 actions visibles : Rules · Selection · Translate all · Validate ▾ · Pack ▾. Settings en icône. Rescan déplacé dans le dropdown de Validate. Import déplacé dans le dropdown de Pack. |
| 6 | Inspector empty / multi-select | 0 sélection : icône + texte. N>1 : header `N unités sélectionnées` + hints raccourcis batch (pas de Source/Target/TM/Validation). |
| 7 | Approche grille | Garder `SfDataGrid` + retokeniser via `SfDataGridThemeData`. La refonte porte sur le squelette, pas le widget grid. |
| 8 | Filtres sidebar | `État` (3) + `Source mémoire` (5) — déjà existants. Pas d'ajout `Fichier loc` (pas de provider, follow-up Plan 5+). |
| 9 | Raccourcis | `Ctrl+F` search · `Ctrl+Enter` save · `↓` next · `Ctrl+R` retranslate · `Ctrl+Shift+V` validate · `Ctrl+T` translate selected · `Ctrl+Shift+T` translate all. Affichés en `.kbd` sur les boutons et hints inspector. |

---

## 3. Layout architecture

```
TranslationEditorScreen (ConsumerStatefulWidget)
└── Column
    ├── EditorTopBar             (56px)  — crumb · model · skip-tm · sep · actions · sep · search
    ├── Expanded
    │   └── Row
    │       ├── EditorFilterPanel    (200px) — État + Source mémoire + Clear
    │       ├── Expanded
    │       │   └── EditorDataGrid   (1fr)   — SfDataGrid retokenisée
    │       └── EditorInspectorPanel (320px) — Source/Target + TM + Validation
    └── EditorStatusBar          (28px)  — units · translated% · review · TM% · spacer · encoding
```

- `FluentScaffold` retiré ; le header global est remplacé par le crumb intégré dans `EditorTopBar`.
- Le breadcrumb du shell (`MainLayoutRouter`) est masqué sur la route `/work/projects/:id/edit/:lang` (même pattern que Plan 3 sur `/work/home`).
- Toutes couleurs/typographies via `context.tokens` (Plan 1). Aucun `Theme.of(context).colorScheme.*` ni `Colors.*` hardcodé dans les widgets touchés.
- Min-width strict 1280px (spec parente §8.7) : layout reste 3-col, scroll horizontal sur la grille en deçà.

---

## 4. Composants

### 4.1 `EditorTopBar` — 56px (remplace `EditorToolbar`)

**Gauche** : crumb cliquable.
- `Projects › <project name italic Instrument Serif> › <language accent>`
- Clic sur "Projects" navigue back (remplace le bouton retour `FluentScaffold`).

**Centre-gauche** : sélecteurs LLM.
- `EditorToolbarModelSelector(compact: false)` (existant, retokenisé).
- `EditorToolbarSkipTm(compact: false)` (existant, retokenisé).
- `tb-sep` (1×24px `--border`).

**Centre** : 1 chip `Rules` + 4 boutons d'action, chacun avec `.kbd` chip si raccourci. (Note d'implémentation : `Rules` est rendu par le widget chip existant `EditorToolbarModRule` — pas un `_ActionButton` — d'où la formulation « Rules chip + 4 action buttons » dans le code.)
- `Rules` — ouvre `ModRuleEditorDialog`. Pas de raccourci.
- `Selection · Ctrl+T` — `handleTranslateSelected`. Disabled si `editorSelectionProvider.hasSelection == false`.
- `Translate all · Ctrl+Shift+T` — `handleTranslateAll`. Variant primary (bg=accent).
- `Validate ▾ · Ctrl+Shift+V` — split-button. Action principale = `handleValidate` (valider la sélection ou tout si pas de sélection). Dropdown : `Rescan all` → `handleRescanValidation` (rerun validation service sur toutes les translated, opération longue — toujours explicite, jamais auto).
- `Pack ▾` — split-button. Action principale = `handleExport` (Generate). Dropdown menu : `Generate pack` · `Import pack`.

**Droite** (`margin-left: auto`) :
- `Settings` — icône-only `⚙`, ouvre `TranslationSettingsDialog`.
- `tb-sep`.
- Search field cmdk look : font-mono, `--panel-2` bg, hint `Ctrl+F` à droite. Filtre rows via `editorFilterProvider.setSearchQuery` (debounced 200ms).

**Suppressions toolbar actuelle** :
- `Settings` (devient icône à droite).
- `Translate Selected` (renommé `Selection`).
- `Rescan` (déplacé dans le dropdown du split-button `Validate ▾`).
- `Generate pack` + `Import pack` (fusionnés en `Pack ▾`).

### 4.2 `EditorFilterPanel` — 200px (renommé depuis `EditorSidebar`)

**Structure** :
- 2 groupes verticalement empilés.
- Section title en `--font-display` italique (Atelier) ou caps-mono (Forge), avec ligne dégradée en suffixe (CSS `linear-gradient(to right, --border, transparent)`).

**Groupe 1 — État** (3 chips) :
- `Pending` (dot warn)
- `Translated` (dot ok)
- `Needs review` (dot err)

**Groupe 2 — Source mémoire** (5 chips) :
- `Exact match` · `Fuzzy match` · `LLM` · `Manual` · `None`

**Chip** : ligne 28px = `cb` checkbox 12×12px + dot couleur + label + count `font-mono` 10.5px à droite. Counts lus depuis `editorStatsProvider` (déjà calcule par status) + nouveau provider pour TM source counts (extension `editorStatsProvider`).

**Bas du panel** : bouton `Clear filters` si `editorFilterProvider.hasActiveFilters == true`.

**Suppressions** : section "Statistics" (Total/Pending/Translated/NeedsReview + LinearProgressIndicator) — déplacée dans `EditorStatusBar`.

### 4.3 `EditorDataGrid` — inchangé en widget, retokenisé

- `SfDataGridThemeData` extrait des tokens : `headerColor=panel`, `gridLineColor=border`, `selectionColor=accent-bg`, `rowHoverColor=panel-2`.
- Colonnes (largeurs fixes alignées sur le mockup) : `[ ] · status-dot · loc file (mono) · key (mono) · source · target · TM pill · ›`.
  - Largeurs : 24/18/140/170/`1.2fr`/`1.2fr`/90/20.
- Cell renderers (`cell_renderers/`) mis à jour : palette via tokens, status-dot 7×7px, TM pill `r=8px` font-mono caps.
- Sélection notifie `editorSelectionProvider.toggleSelection` via `grid_selection_handler.dart` (inchangé).
- Invalidation sur `BatchProgressEvent`/`BatchCompletedEvent` (invariant Phase 4 #3 préservé).
- Empty state grille : message centré "Aucune unité ne correspond aux filtres" + bouton "Effacer les filtres" si `hasActiveFilters`.

### 4.4 `EditorInspectorPanel` — 320px (NEW)

`ConsumerStatefulWidget` (state pour `TextEditingController` du target éditable).

**Cas 0 sélection** :
- Centre vertical : icône `FluentIcons.info_24_regular` 48px dim + texte "Sélectionnez une unité pour voir les détails".

**Cas 1 sélection** :

| Section | Contenu |
|---|---|
| Header | `Unité <index>/<total>` (font-display italique) + `<index>/<total>` mono à droite |
| Key | Chip `--panel-2` border, `font-mono` 11px, `word-break: break-all`, padding 8×12 |
| Source | Label "Source · `<lang>`" en `font-mono` 9.5px caps + block `--panel-2` border, `r=4px`, line-height 1.6, padding 10×13. Read-only. |
| Cible | Label "Cible · `<lang>` — édition" + bullet accent + block bg=`--accent-bg` border `--accent`, line-height 1.6. `TextField` multi-line, save sur `Ctrl+Enter` → `handleCellEdit(unitId, text)`. |
| Suggestions | Lecture `tmSuggestionsForUnitProvider`. Liste empilée d'items cliquables : libellé tronqué + `pct` mono à droite (TM 100% / TM 82% / LLM / SRC). Clic = `handleApplySuggestion`. |
| Validation | Lecture `validationIssuesProvider`. Liste d'issues + bouton `Apply fix` per-issue. Réutilise `EditorValidationPanel` (déjà autonome dans `editor_validation_panel.dart`, seulement référencé par le `editor_bottom_panel.dart` orphelin — survit à sa suppression). |
| Footer hints | `Ctrl+Enter save · ↓ next · Ctrl+R retranslate · Ctrl+Shift+V validate` en `font-mono` 10px |

**Cas N>1 sélection** :
- Header : `<N> unités sélectionnées` (font-display italique).
- Hints raccourcis batch : `Ctrl+T translate · Ctrl+R retranslate · Ctrl+Shift+V validate`.
- Pas de Source/Target/TM/Validation.

### 4.5 `EditorStatusBar` — 28px (NEW)

- Lit `editorStatsProvider(projectId, languageId)` + nouveau `tmReuseStatsProvider(projectId, languageId)`.
- Layout flex horizontal, gap 22px, padding `0 20px`, bg=`--panel`, border-top `--border`, font-mono 10.5px, color=`--text-dim`.
- **Gauche** : `<total> units · <translated> translated (<%>) · <needsReview> need review · TM <reuse%>` — la métrique progression colorée en `--accent`.
- **Droite** (`margin-left: auto`) : `UTF-8 · CRLF` (encoding statique affiché — assumé pour TWMT puisque l'éditeur n'expose pas d'autre encoding ; à confirmer dans le plan d'implémentation contre le pack writer réel).
- État loading : skeleton placeholders `· · ·` (mono dim).
- État error : statusbar vide (silencieuse), erreur loggée via `loggingServiceProvider`.

### 4.6 Suppressions

| Fichier / élément | Raison |
|---|---|
| `editor_bottom_panel.dart` | Orphelin (jamais wiré). `EditorValidationPanel` utilisé déplacé dans inspector via import. |
| `EditorSidebar` | Renommé `EditorFilterPanel`. |
| Section "Statistics" du sidebar | Déplacée dans `EditorStatusBar`. |
| `FluentScaffold` du screen | Header remplacé par crumb in-toolbar. |
| Bouton `Translation Settings` toolbar | Devient icône-only à droite. |
| Bouton `Rescan` toolbar | Déplacé dans le dropdown du split-button `Validate ▾`. |
| Boutons `Generate pack` + `Import pack` séparés | Fusionnés en `Pack ▾` split-button. |

---

## 5. Data flow

### 5.1 Providers consommés (lecture)

| Composant | Providers |
|---|---|
| `EditorTopBar` | `currentProjectProvider`, `currentLanguageProvider`, `editorSelectionProvider`, `selectedLlmModelProvider`, `translationSettingsProvider` |
| `EditorFilterPanel` | `editorFilterProvider`, `editorStatsProvider` |
| `EditorDataGrid` | `filteredTranslationRowsProvider`, `editorSelectionProvider`, `selectedLlmModelProvider` |
| `EditorInspectorPanel` | `editorSelectionProvider`, `filteredTranslationRowsProvider`, `tmSuggestionsForUnitProvider`, `validationIssuesProvider` |
| `EditorStatusBar` | `editorStatsProvider`, `tmReuseStatsProvider` (NEW) |

### 5.2 Nouveau provider : `tmReuseStatsProvider`

Vit dans `lib/features/translation_editor/providers/tm_reuse_stats_provider.dart`.

```dart
class TmReuseStats {
  final double reusePercentage; // 0..100
  final int reusedCount;
  final int translatedCount;
  const TmReuseStats({...});
  factory TmReuseStats.empty() => const TmReuseStats(
    reusePercentage: 0, reusedCount: 0, translatedCount: 0);
}

@riverpod
Future<TmReuseStats> tmReuseStats(Ref ref, String projectId, String languageId) async {
  final rows = await ref.watch(translationRowsProvider(projectId, languageId).future);
  final translated = rows.where((r) =>
    r.versionStatus == TranslationVersionStatus.translated).toList();
  if (translated.isEmpty) return TmReuseStats.empty();
  final fromTm = translated.where((r) {
    final src = getTmSourceType(r);
    return src == TmSourceType.exactMatch
        || src == TmSourceType.fuzzyMatch
        || src == TmSourceType.llm;
  }).length;
  return TmReuseStats(
    reusedCount: fromTm,
    translatedCount: translated.length,
    reusePercentage: fromTm / translated.length * 100,
  );
}
```

Watch sur `translationRowsProvider` → recalcule à chaque save / batch.

### 5.3 Mutations

| Action UI | Mutator |
|---|---|
| Toggle filter chip | `editorFilterProvider.notifier.setStatusFilters / setTmSourceFilters` |
| Search input | `editorFilterProvider.notifier.setSearchQuery` (debounced 200ms widget-side) |
| Skip TM toggle | `translationSettingsProvider.notifier.setSkipTranslationMemory` |
| Select model | `selectedLlmModelProvider.notifier.setModel` |
| Toggle row selection | `editorSelectionProvider.notifier.toggleSelection` (via `grid_selection_handler`) |
| Apply TM suggestion | `handleApplySuggestion` → écrit via `translationVersionRepo` puis `ref.invalidate(translationRowsProvider)` |
| Save inspector edit | `handleCellEdit(unitId, text)` puis `ref.invalidate(translationRowsProvider)` |
| Validate / Translate / Retranslate | `TranslationEditorActions.handle*` (existants, batch events refresh la grille) |

### 5.4 Réactivité critique

- `EditorDataGrid` reste seul à écouter `BatchProgressEvent` / `BatchCompletedEvent` via `editor_data_source.dart`. Invalide `translationRowsProvider` → cascade vers `filteredTranslationRowsProvider`, `editorStatsProvider`, `tmReuseStatsProvider`, et tout l'inspector.
- `EditorInspectorPanel` watch `editorSelectionProvider` directement → quand l'utilisateur clique une row, le panel se rebuild sans callback parent.
- `EditorStatusBar` re-render à chaque save / batch (via invalidate). Pas de polling.

### 5.5 Pas de nouveau service backend

Tout consomme les services existants (`translationMemoryService`, `validationService`, `translationOrchestrator`). Aucun nouveau repo, aucune nouvelle migration DB. Seul ajout : `tmReuseStatsProvider`.

---

## 6. États limites & erreurs

### 6.1 Loading
- `EditorDataGrid` : `_cachedRows` (Phase 4) — la grille reste visible pendant les refresh.
- `EditorFilterPanel` : counts en placeholder `· · ·` si `editorStatsProvider` loading.
- `EditorInspectorPanel` : section Suggestions = shimmer 3 lignes ; section Validation cachée (pas de placeholder bruyant).
- `EditorStatusBar` : skeleton `· · ·` à la place des chiffres.

### 6.2 Empty
- 0 row : message centré "Aucune unité ne correspond aux filtres" + bouton "Effacer les filtres" si `hasActiveFilters`.
- 0 sélection : inspector empty state (cf. §4.4).
- 0 issues validation : section Validation = "Aucun problème détecté" (texte dim).
- 0 suggestions TM : section Suggestions = "Aucune correspondance" (texte dim).

### 6.3 Erreurs
- `editorStatsProvider` error : statusbar silencieuse, filterpanel sans counts. Erreur loggée. Pas de toast.
- `tmSuggestionsForUnitProvider` error : section Suggestions = "Erreur de chargement TM" + retry icon. Logge.
- `validationIssuesProvider` error : section Validation = "Validation indisponible". Logge.
- Save inspector edit échoue : toast `FluentToast.error` + le block target garde le texte non-sauvé en bg `--err-bg` border `--err`, focus restauré.
- Apply TM suggestion échoue : toast error, suggestion non appliquée.

### 6.4 Cas multi-fenêtres / re-entry
- `WidgetsBinding.addPostFrameCallback` dans `initState` réinitialise `skipTranslationMemory=false` et `clearModUpdateImpact()` — comportement existant **conservé**.
- `TranslationInProgress` (keepAlive) reste : si batch en cours, navigation bloquée.
- Resize fenêtre < 1280px : layout reste 3-col, scroll horizontal sur la grille.
- Disparition de la sélection (delete row) : inspector retombe en empty state.

### 6.5 Invariants Phase 4 préservés
- Right-click sur row non sélectionnée → select-only puis menu.
- Select-all checkbox tristate.
- `_cachedRows` pendant refresh.
- Invalidation toutes les 10 `BatchProgressEvent`.
- `keepAlive` sur `SelectedLlmModel` et `TranslationInProgress`.

---

## 7. Testing strategy

### 7.1 Tests existants à conserver verts
- `editor_characterisation_test.dart` (Phase 4 Batch A) — 6 cas. **Filet de sécurité principal**.
- Tests providers (`editor_filter_notifier_test`, `editor_selection_notifier_test`, `grid_data_providers_test`, etc.) — non touchés.
- `translation_editor_screen_test.dart` — à adapter : finders sur `EditorSidebar` deviennent `EditorFilterPanel` ; suppression du finder `FluentScaffold`.

### 7.2 Nouveaux tests widget

| Fichier | Couverture |
|---|---|
| `editor_top_bar_test.dart` | crumb cliquable navigue back · model selector · skip-tm · 5 actions présentes · Selection disabled si pas de sélection · Translate all primary · Pack split-button menu · Settings icône · search cmdk look |
| `editor_filter_panel_test.dart` | 2 groupes affichés · 8 chips totaux · counts lus · clear filters apparait si actif · clear vide les filtres · stats absent |
| `editor_inspector_panel_test.dart` | empty state si 0 sélection · header N/total si 1 sélection · key chip · Source block · Target block éditable · Suggestions clickable · Validation issues · multi-select header · footer hints |
| `editor_status_bar_test.dart` | 4 metrics affichés · TM% calculé · encoding statique · skeleton si loading · vide si error |
| `tm_reuse_stats_provider_test.dart` | empty si 0 translated · 100% si tous TM · 50% si moitié manual |

Tous via `createThemedTestableWidget` (cf. `feedback_flutter_test_patterns.md` : `valueOrNull` n'existe pas, override first-wins, FakeLogger registered en `setUp`).

### 7.3 Golden tests
- 4 goldens : `editor_screen.atelier.populated.png` · `editor_screen.atelier.empty_selection.png` · `editor_screen.forge.populated.png` · `editor_screen.forge.empty_selection.png`.
- PhysicalSize 1920×1080 dans `setUp`. Date pinnée `DateTime.utc(2024, 1, 1, 12)` si timeago utilisé.

### 7.4 Smoke test manuel post-implémentation
Identique à Phase 4 Batch E (15 steps) + 5 nouveaux :
16. Inspector affiche source/target éditables sur sélection 1 row.
17. `Ctrl+Enter` dans le block target sauve.
18. Cliquer une suggestion TM applique le texte à la sélection.
19. Toggle filtre chip dans `EditorFilterPanel` filtre la grille.
20. Statusbar reflète les counts en live après une traduction (translated++ / TM%++).

### 7.5 Cibles quantitatives
- `flutter analyze lib/` : 0 erreur.
- Suite complète : 1287 → cible **~1340 / 30** (≈55 nouveaux tests, 0 régression).
- Caractérisation Phase 4 : 6/6 verts.

---

## 8. Approche d'implémentation

**Approche 1 — Réécriture du squelette en place** (validée).

- Worktree : `feat/ui-editor` from `main`.
- Sub-agent driven, batches indépendants, `model: opus` partout (cf. `feedback_subagent_model.md`).
- Pattern Plan 3 : un sub-agent par batch, code-review opus après chaque commit.
- Reuse Plan 3 primitives : `TokenCard` / `ActionCard` / `WorkflowCard` n'ont pas d'application directe ici (l'éditeur est une grille, pas un dashboard de cards), mais le pattern theming `context.tokens` est repris partout.

### 8.1 Batches anticipés (ordre figé au plan)

| # | Sujet |
|---|---|
| A | `tmReuseStatsProvider` + tests provider (zero-risk preflight). |
| B | `EditorStatusBar` widget + test + intégration screen (avec sidebar stats encore en place — duplication temporaire 1 commit). |
| C | `EditorFilterPanel` (rename + suppression Statistics) + test. |
| D | `EditorTopBar` (refonte toolbar 5 actions + crumb + cmdk search) + test + suppression `FluentScaffold` du screen. |
| E | `EditorInspectorPanel` widget + test + intégration screen. Suppression `editor_bottom_panel.dart`. |
| F | Retokenisation `EditorDataGrid` cell renderers + `SfDataGridThemeData` + golden tests. |
| G | Smoke test manuel + memory update + merge readiness. |

Les détails (instructions sub-agent par batch, dépendances, gates de commit) seront dressés dans le plan d'implémentation.

---

## 9. Risques identifiés

| Risque | Mitigation |
|---|---|
| `SfDataGrid` ne consomme pas correctement les tokens (limitations Syncfusion) | Wrap dans `Theme()` avec `SfDataGridThemeData` extrait des tokens — fallback : surcharge cell-by-cell via cell renderers. |
| Inspector édition target conflit avec édition inline grid | Spec : édition inspector désactive temporairement l'édition inline (mode mutually exclusive). À documenter dans le plan. |
| Statusbar `tmReuseStatsProvider` lourd à calculer sur gros projet | Mémoization Riverpod déjà en place via family `(projectId, languageId)`. Watch `translationRowsProvider` qui est déjà cached. |
| Tests goldens flaky sur Windows | `test/flutter_test_config.dart` désactive google_fonts runtime fetch (Plan 3). Date pinnée. |
| Min-width 1280px casse en CI / petits écrans dev | Tests utilisent `physicalSize = 1920×1080` (cf. `feedback_flutter_test_patterns.md`). |

---

## 10. Out of scope (Plan 4)

- Refonte des dialogs translation (Settings, History, PromptPreview, ValidationEdit, ModRule, Export) → Plan 5.
- Refonte `ValidationReviewScreen` (écran séparé) → Plan 5.
- Filtre `Fichier loc` dans `EditorFilterPanel` (pas de provider existant) → follow-up Plan 5+.
- Vraie palette de commandes `Ctrl+K` → potentiel Plan 6.
- Tracking session-level tokens / cost pour la statusbar → demande nouveau service, hors scope.
- Suivi encoding dynamique (pour l'instant statique `UTF-8 · CRLF`).
- Plan 3 follow-ups (I2 activity feed staleness, I3 projectName) — déjà listés dans la mémoire `project_ui_redesign_progress.md`, indépendants.

---

## 11. Open questions for the implementation plan

1. `SfDataGridThemeData` peut-il vraiment couvrir 100% du theming de la grille, ou faut-il garder du theming cell-by-cell ?
2. La debounce 200ms du search field doit-elle être implémentée widget-side (`Timer`) ou côté provider (Riverpod `debounce` middleware) ?
3. L'invalidation `translationRowsProvider` après save inspector doit-elle être explicit ou couverte par les batch events existants ?
4. Faut-il introduire une transition d'animation lorsqu'on change de sélection (cross-fade inspector content) ou rebuild brutal acceptable ?
5. Les goldens pour le state "1 sélection avec inspector populé" sont-ils dans le scope du Plan 4 ou ajoutés en suivi ?

Ces questions seront résolues lors de la rédaction du plan d'implémentation.
