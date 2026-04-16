# TWMT — UI redesign — Plan 5b (Détail / overview) — design spec

**Date:** 2026-04-17
**Status:** design · pending implementation plan
**Parent spec:** [`2026-04-14-ui-redesign-design.md`](./2026-04-14-ui-redesign-design.md) §7.2
**Sibling spec:** [`2026-04-16-ui-lists-filterable-design.md`](./2026-04-16-ui-lists-filterable-design.md) (Plan 5a — primitives réutilisées)
**Predecessor plans:** Plan 1 (Foundation), Plan 2 (Navigation), Plan 3 (Home), Plan 4 (Editor), Plan 5a (Lists — filterable). All shipped on `main`.
**Successor plan:** Plan 5c (Wizard / form).
**Branch (proposed):** `feat/ui-details`

---

## 1. Intent

Adopter l'archétype « Détail / overview » de la spec parente §7.2 sur les deux écrans de détail réellement présents dans l'app : **Project Detail** et **Glossary Detail**. Les deux utilisent aujourd'hui un chrome hétérogène (Project en `FluentScaffold` + couleurs hard-codées + `LanguageCard` custom ; Glossary en branche inline de `GlossaryScreen` avec un stats panel 280px à gauche, incohérent avec §7.2).

Le livrable porte sur **le chrome et la composition** — meta-bandeau, layout 2fr/1fr avec rail à droite, crumb intégré, extraction de primitives composables `DetailMetaBanner`/`DetailCover`/`DetailOverviewLayout`/`StatsRail`, migration de la liste des langues sur la primitive `ListRow` du Plan 5a. **Aucune feature ajoutée ou retirée.**

**Non-objectifs :**
- **Mod Detail** — n'existe pas aujourd'hui. Création reportée (nouvelle feature méritant son propre brainstorming : scope Workshop meta, versions, projets liés, actions).
- **Glossary Entry editor dialog** — conservé en dialogue modal (`GlossaryEntryEditorDialog`), pas converti en panel inspector. Cohérent avec les autres dialogs CRUD.
- **Settings**, **Help** — adoption des tokens dans un plan mineur final.
- **Description Project** — le modèle `Project` n'a pas de champ description. Le slot `DetailMetaBanner.description` est prévu mais restera vide pour Project jusqu'à ajout data-modèle (hors scope).
- **Ajout de feature fonctionnelle** : aucune (refactor chrome pur).

---

## 2. Decisions

| # | Question | Décision | Rationale |
|---|---|---|---|
| 1 | Scope | 2 écrans : Project Detail + Glossary Detail. Mod Detail déféré en nouvelle feature. | Mod Detail = vraie feature, mérite brainstorming dédié. Glossary Entry editor reste un dialog. |
| 2 | Layout Glossary | Meta-bandeau full-width + 2 colonnes 2fr/1fr, **stats à droite** (comme Project Detail, conforme §7.2). | Cohérence inter-écrans prime sur la mémoire musculaire (stats aujourd'hui à gauche 280px). |
| 3 | Cover du meta-bandeau | Hybride : `project.imageUrl` (Steam thumb) si dispo, sinon monogram Instrument Serif italic (2 lettres sur dégradé panel). Glossary → toujours monogram (pas d'image). | Valorise la data existante sans dépendre d'une collection de logos de jeux qu'on n'a pas. Monogram élégant et typed. |
| 4 | Langues Project | `LanguageCard` custom supprimée. Chaque langue = un `ListRow` (primitive Plan 5a) via un builder `LanguageProgressRow`. | Cohérence Plan 5a ; densité suffisante (projets typiques 3-5 langues) ; trailing action "Open" identique au pattern listes. |
| 5 | Colonne rail | `StatsRail` avec header progress bar + sections ("Overview"/"Efficiency"/"Usage"/"Quality") + hint actionnable ("NEXT · 2 units à revoir"). | B retenu : garde toute la data utile (TM/tokens ≠ vanity sur un écran pilotage), ajoute l'angle actionnable du Home sans basculer en dashboard. |
| 6 | Niveau d'abstraction | Primitives composables dans `lib/widgets/detail/`, pas de `DetailScaffold<T>` générique. | Symétrie Plan 5a (ListRow/FilterToolbar) : composition > inheritance, chaque écran garde sa liberté de divergence. |
| 7 | Crumb | Intégré dans la toolbar d'écran de chaque détail (clôt partiellement le follow-up Plan 2). Le crumb global `MainLayoutRouter` reste le temps que Plan 5c migre les wizards. | Même logique que Plan 5a. |
| 8 | Entry editor Glossary | Reste un dialog. Pas de conversion en panel inspector pour 5b. | Workflow d'édition rapide, pattern cohérent avec les autres CRUD de l'app. |
| 9 | Responsive | Breakpoint 1000px (repris du `LayoutBuilder` actuel ProjectDetailScreen) → pile en colonne en dessous. Pas de cas mobile (app min-width 1280 §8 spec parente). | Continuité comportement actuel. |

---

## 3. Scope — les 2 écrans

| Écran | Fichier principal | LOC actuel | Pattern | Notes |
|---|---|---|---|---|
| Project Detail | `features/projects/screens/project_detail_screen.dart` (+ widgets `project_overview_section.dart`, `language_card.dart`, `project_stats_card.dart`) | ~550 | détail | FluentScaffold retiré. Tokens partout. Languages en `ListRow`. Stats en `StatsRail`. `ProjectOverviewSection` / `LanguageCard` / `ProjectStatsCard` supprimés. |
| Glossary Detail | `features/glossary/screens/glossary_screen.dart` (branche `selectedGlossary != null`) + widgets `glossary_statistics_panel.dart`, `glossary_screen_components.dart` (partiel) | ~450 | détail | Vue inline conservée (pas de route dédiée, même `selectedGlossaryProvider`). Meta-bandeau + 2col stats-right. Grid + search conservés. `GlossaryStatisticsPanel`, `GlossaryEditorHeader`, `GlossaryEditorFooter`, `GlossaryEditorToolbar` supprimés. |

**Total** : ~1000 LOC écrans refondues. +350 LOC de primitives partagées. Après refactor attendu : **~1150 LOC nets**, compensés par la suppression des widgets ad-hoc.

---

## 4. Primitives à extraire

Emplacement : `lib/widgets/detail/` (nouveau dossier, pattern Plans 3 `cards/` et 5a `lists/`).

### 4.1 `DetailMetaBanner`

Meta-bandeau full-width §7.2 ligne horizontale :

```dart
DetailMetaBanner({
  required Widget cover,               // 110×68 — typiquement DetailCover
  required String title,               // Instrument Serif italic (Atelier) / caps (Forge)
  required List<Widget> subtitle,      // font-mono segments, séparateur · auto
  String? description,                  // optionnel, line-height 1.5
  List<Widget> actions = const [],     // SmallTextButton / SmallIconButton / FilledButton
})
```

Hauteur ~96px. `bg: tokens.panel2`, `border-bottom: 1px tokens.border`. `padding: 14` horizontal + vertical. Gap cover↔info : 16px. `actions` à droite via `margin-left: auto`.

### 4.2 `DetailCover`

Slot 110×68 intelligent (décision #3) :

```dart
DetailCover({
  String? imageUrl,                    // Steam thumb si dispo
  required String monogramFallback,    // 2-3 lettres
})
```

- `imageUrl != null` → `Image.network(imageUrl, fit: cover)` avec `loadingBuilder` (skeleton) et `errorBuilder` (fallback monogram).
- Sinon → container dégradé `tokens.panel2 → tokens.panel`, border 1px `tokens.border`, monogram centré en `tokens.fontDisplay` (Instrument Serif italic en Atelier / caps-mono en Forge), taille 28px, couleur `tokens.accent`.

Radius 6px (entre `--r-sm` et `--r-md`).

### 4.3 `DetailOverviewLayout`

Split 2fr/1fr §7.2 :

```dart
DetailOverviewLayout({
  required Widget main,
  required Widget rail,
  double railWidth = 320,              // min-width 320
  double gap = 24,
  double stackBreakpoint = 1000,
})
```

`LayoutBuilder` : au-dessus du breakpoint → `Row([Expanded(flex:6, main), gap, SizedBox(width: railWidth, rail)])`. En dessous → `Column([main, gap, rail])`. Padding externe 24px (repris du ProjectDetailScreen actuel).

### 4.4 `StatsRail` + sous-composants

```dart
StatsRail({
  Widget? header,                      // ex: OverallProgressHeader(%)
  required List<StatsRailSection> sections,
  StatsRailHint? hint,
})

StatsRailSection({
  required String label,               // "Overview", "Efficiency", "Usage", "Quality"
  required List<StatsRailRow> rows,
})

StatsRailRow({
  required String label,
  required String value,
  StatsSemantics semantics = StatsSemantics.neutral,  // ok, warn, err, neutral
})

StatsRailHint({
  required String kicker,              // "NEXT"
  required String message,
  StatsSemantics semantics = StatsSemantics.warn,
  VoidCallback? onTap,
})
```

**Rendu** :
- Container `bg: tokens.panel`, border 1px `tokens.border`, radius 8px, padding 16.
- `header` optionnel en haut (margin-bottom 14), séparateur 1px `tokens.border`.
- Chaque `StatsRailSection.label` en caps-mono 10px `tokens.textDim` letter-spacing 1.2, margin-bottom 8.
- `StatsRailRow` → `Row` : label `tokens.textMid` gauche, value `tokens.fontMono` droite avec couleur sémantique (`tokens.ok`/`warn`/`err`/`text`). Padding vertical 6, border-bottom 1px `tokens.border.withOpacity(.5)` sauf dernière.
- Séparateur 1px `tokens.border` entre sections (margin 8/8).
- `StatsRailHint` en bas : border-left 2px semantic color, padding 8/10, bg `semantic.withOpacity(.08)`, radius 4. Kicker caps-mono 11px semantic color, message `tokens.text` 12px. `InkWell` wrapper si `onTap != null`.

### 4.5 `LanguageProgressRow` (helper spécifique Project)

Vit dans `features/projects/widgets/language_progress_row.dart` (pas dans `widgets/detail/`, car spécifique Project). Consomme `ListRow` + `StatusPill` du Plan 5a :

```dart
LanguageProgressRow({
  required ProjectLanguageDetails langDetails,
  VoidCallback? onOpenEditor,
  VoidCallback? onDelete,
})
```

- Colonnes : `ListRowColumn.flex(1)` (name+status) · `ListRowColumn.fixed(60)` (% aligné droite) · `ListRowColumn.fixed(120)` (progress bar dense 4px) · `ListRowColumn.fixed(100)` (units aligné droite).
- `trailingAction` (slot `ListRow`) : `SmallTextButton("Open")` (et icône delete optionnelle en hover — décision d'implémentation).
- Couleur de la progress bar dérivée du % (même dérivation qu'aujourd'hui : `err` < 25, `warn` < 50, `accent` < 100, `ok` à 100).
- `StatusPill` (primitive Plan 5a) pour `translating`/`completed`/`pending`/`error` en suffixe du nom (font-mono 10px).

---

## 5. Layouts par écran

### 5.1 Project Detail

Structure (pseudo-code) :

```
Column [
  ScreenToolbar(
    crumb: "Work › Projects › {project.name}",
    leading: BackButton(onPressed: pop + invalidate projectDetailsProvider),
  ),
  DetailMetaBanner(
    cover: DetailCover(
      imageUrl: project.imageUrl,             // parsedMetadata?.modImageUrl
      monogramFallback: initials(project.name),
    ),
    title: project.name,
    subtitle: [
      TypeBadge(project.isGameTranslation),   // "mod" | "game"
      if (project.isGameTranslation) Text("source: $sourceLanguage"),
      if (project.modSteamId != null) Text("steam: ${project.modSteamId}"),
      Text("${details.languages.length} languages"),
    ],
    actions: [
      SmallTextButton("+ Language", primary: true, onTap: _handleAddLanguage),
      if (project.modSteamId != null) SmallIconButton(openInSteam, onTap: _launchSteamWorkshop),
      SmallIconButton(delete, danger: true, onTap: _handleDeleteProject),
    ],
  ),
  Expanded(child: DetailOverviewLayout(
    main: LanguagesSection(
      header: "Target languages (${details.languages.length})",
      rows: details.languages.map((ld) => LanguageProgressRow(
        langDetails: ld,
        onOpenEditor: () => _handleOpenEditor(ld),
        onDelete: () => _handleDeleteLanguage(ld),
      )),
      emptyState: EmptyLanguagesState(onAdd: _handleAddLanguage),  // retokénisé
    ),
    rail: StatsRail(
      header: OverallProgressHeader(percent: stats.progressPercent),
      sections: [
        StatsRailSection("Overview", [
          Row("Translated", stats.translatedUnits, ok),
          Row("Pending",    stats.pendingUnits,    warn),
          Row("Needs review", stats.needsReviewUnits, err),
          Row("Total",      stats.totalUnits),
        ]),
        StatsRailSection("Efficiency", [
          Row("TM reuse",    "${(stats.tmReuseRate*100).toStringAsFixed(1)}%"),
          Row("Tokens used", formatNumber(stats.tokensUsed)),
        ]),
      ],
      hint: _computeProjectHint(stats),         // err > warn > ok priorité
    ),
  )),
]
```

Dialogs (`AddLanguageDialog`, delete confirmations, `FluentToast`) conservés tels quels — retokénisation si tokens pas encore utilisés, mais hors scope.

### 5.2 Glossary Detail

Sort de la branche `selectedGlossary != null` dans `GlossaryScreen.build`. La détail-view reste inline (pas de route dédiée, toujours piloté par `selectedGlossaryProvider`) :

```
Column [
  ScreenToolbar(
    crumb: "Resources › Glossary › {glossary.name}",
    leading: BackButton(onPressed: () => ref.read(selectedGlossaryProvider.notifier).clear()),
  ),
  DetailMetaBanner(
    cover: DetailCover(
      imageUrl: null,
      monogramFallback: initials(glossary.name),
    ),
    title: glossary.name,
    subtitle: [
      Text(gameName(glossary.gameInstallationId)),
      Text("target: ${glossary.targetLanguageCode}"),
      Text("${stats.totalEntries} entries"),
      Text(formatRelativeSince(glossary.updatedAt)),   // primitive Plan 5a
    ],
    description: glossary.description,
    actions: [
      SmallTextButton("+ Entry", primary: true, onTap: _showEntryEditor),
      SmallTextButton("Import", onTap: _showImportDialog),
      SmallTextButton("Export", onTap: _showExportDialog),
      SmallIconButton(delete, danger: true, onTap: _confirmDeleteGlossary),
    ],
  ),
  Expanded(child: DetailOverviewLayout(
    main: Column [
      ListSearchField(controller: _entrySearchController),  // primitive Plan 5a
      Expanded(child: GlossaryDataGrid(glossaryId: glossary.id)),
    ],
    rail: StatsRail(
      sections: [
        StatsRailSection("Overview", [
          Row("Total entries", stats.totalEntries),
        ]),
        StatsRailSection("Usage", [
          Row("Used in translations", stats.usedInTranslations, ok),
          Row("Unused",               stats.unusedEntries,      neutral),
          Row("Usage rate",           "${(stats.usageRate*100).toStringAsFixed(1)}%"),
        ]),
        StatsRailSection("Quality", [
          Row("Duplicates",           stats.duplicatesDetected,
              stats.duplicatesDetected > 0 ? warn : neutral),
          Row("Missing translations", stats.missingTranslations,
              stats.missingTranslations > 0 ? warn : neutral),
        ]),
      ],
      hint: _computeGlossaryHint(stats),
    ),
  )),
]
```

**Suppression** : `GlossaryEditorHeader`, `GlossaryEditorFooter`, `GlossaryEditorToolbar` (dans `glossary_screen_components.dart`), `GlossaryStatisticsPanel`. L'empty-state `GlossaryEmptyState` reste. `GlossaryDataGrid` et `GlossaryEntryEditorDialog` conservés intacts.

---

## 6. Tests

Pattern Plans 3/4/5a (goldens + widget tests).

**Widget tests primitives** (~15 tests, `test/widgets/detail/`) :
- `DetailMetaBanner_test.dart` : layout (cover + title + subtitle + actions), description masquée si null, actions slot vide toléré, title en Instrument Serif italic sous Atelier, caps sous Forge.
- `DetailCover_test.dart` : `imageUrl != null` → `Image.network`, `errorBuilder` → monogram fallback, `imageUrl == null` → monogram direct, typo correcte par thème.
- `DetailOverviewLayout_test.dart` : au-dessus du breakpoint → Row 2fr/1fr, en dessous → Column, gap respecté.
- `StatsRail_test.dart` : sections rendues, header optionnel, hint optionnel, sémantiques → couleurs token attendues, `onTap` sur hint déclenche callback.
- `LanguageProgressRow_test.dart` : colonnes, couleur bar dérivée du %, status pill, trailing action tap.

**Widget tests écrans** (~10 tests) :
- Project Detail : chargement + erreur, overall progress calculé, delete project → toast + navigation, add language → dialog, open editor → push route, hint affiché si `needsReviewUnits > 0`.
- Glossary Detail : sélection via `selectedGlossaryProvider`, search filtre la grid, import/export → dialog, delete → confirmation + retour à la liste, hint si `missingTranslations > 0`.

**Golden tests** : 2 thèmes × 2 écrans × 1 état = **4 goldens**. États supplémentaires ajoutés seulement sur demande de la review.

**Tests existants à mettre à jour** :
- `test/features/projects/widgets/project_overview_section_test.dart` → supprimé.
- `test/features/projects/widgets/language_card_test.dart` → remplacé par `language_progress_row_test.dart`.
- `test/features/projects/widgets/project_stats_card_test.dart` → supprimé.
- `test/features/glossary/widgets/glossary_statistics_panel_test.dart` → supprimé (couverture migre sur `stats_rail_test.dart`).
- Les tests du Glossary screen branche détail adaptés au nouveau layout (chemins de widgets changent).

**Cible** : 1316 → **~1345** tests (+29 nets, tenant compte des suppressions).

---

## 7. Migration

### 7.1 Worktree

- Branche : `feat/ui-details` depuis `main`.
- Worktree : `.worktrees/ui-details/`.
- Setup post-clone : copier `windows/`, `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs` (gotcha mémoire : tous les deux gitignorés).

### 7.2 Task order (séquentiel, 1 commit par task)

| Task | Contenu | Verification |
|---|---|---|
| 1 | Primitives `lib/widgets/detail/` : `DetailMetaBanner`, `DetailCover`, `DetailOverviewLayout`, `StatsRail` + `StatsRailSection` + `StatsRailRow` + `StatsRailHint` + `StatsSemantics` enum. | Tests primitives verts (~12-15). |
| 2 | `LanguageProgressRow` helper (consomme ListRow + StatusPill Plan 5a). | Test widget vert. |
| 3 | Project Detail refondu : nouveau `project_detail_screen.dart`, suppression `ProjectOverviewSection`, `LanguageCard`, `ProjectStatsCard` + tests associés. FluentScaffold retiré. | Tests Project verts + golden Atelier + golden Forge. |
| 4 | Glossary Detail refondu : refonte de la branche détail dans `glossary_screen.dart`, suppression `GlossaryEditorHeader`/`Footer`/`Toolbar`, `GlossaryStatisticsPanel` + tests associés. `GlossaryDataGrid`, `GlossaryEntryEditorDialog`, `GlossaryEmptyState` intacts. | Tests Glossary verts + golden Atelier + golden Forge. |
| 5 | Goldens regénérés en batch si drift, `flutter analyze`, full suite. | `flutter test` vert à ~1345/30. |

### 7.3 Conventions

- Commits en anglais, format `type: description`, pas de mention AI (CLAUDE.md).
- Tokens exclusivement via `context.tokens` — zéro `Colors.xxxxxx`, zéro `Theme.of(context).colorScheme.xxx` dans les écrans et widgets refondus.
- `FluentScaffold` retiré de Project Detail.

---

## 8. Risques

- **`GlossaryDataGrid` dans la colonne 2fr** — la grid a un `SfDataGridTheme` appliqué en Plan 5a ; placer cette grid dans une colonne dont la largeur change (2fr vs 1fr responsive, vs bordures du DetailOverviewLayout) peut perturber le layout interne. **Mitigation** : snapshot golden du Glossary detail, régression visuelle attrapée tôt.
- **`selectedGlossaryProvider` state** — le pop depuis la détail-view doit nettoyer le provider sinon l'écran reste en mode détail orphelin. **Mitigation** : back button custom explicite, test qui vérifie `selectedGlossaryProvider.value == null` après back.
- **Breakpoint responsive** — `DetailOverviewLayout` utilise 1000px. Si le rail est fixé à 320px et main doit garder min 600px utile, le seuil effectif est 920+24+320 ≈ 1264px. L'app tient min-width 1280 (§8 spec parente), donc on reste en mode Row. Prévoir le test du mode Column pour robustesse, mais pas de cas réel à livrer.
- **Migration tests** — suppression de widget tests existants signifie que la couverture ligne peut temporairement baisser. **Mitigation** : les tests sur primitives + écrans compensent amplement. Revalider la couverture en Task 5.
- **Icônes "delete" danger** — `SmallIconButton` de Plan 5a n'a pas de variante `danger` explicite. Décision d'implémentation : soit on ajoute le paramètre `danger: bool` à `SmallIconButton` (extension primitive), soit on override la couleur via `color: tokens.err` passé en argument. Choix : **override couleur explicite** pour éviter de toucher à `SmallIconButton` en 5b.
- **Description absent côté Project** — `project.description` n'existe pas. Le slot `DetailMetaBanner.description` est `null` pour Project Detail. Pas de fallback bidon.

---

## 9. Follow-ups déférés (explicites)

- **Mod Detail** — feature entière à brainstormer : Workshop meta (description, changelog, subscribers, last-update), versions, projets liés, actions (Open in Steam, Import, Create project). Branche 5d ou plan dédié.
- **Inspector entry editor** — conversion de `GlossaryEntryEditorDialog` en panneau à droite de la détail-view. À considérer si le feedback post-5b dit que le workflow dialog rompt la densité.
- **Description Project** — si un jour on ajoute un champ description au modèle Project, `DetailMetaBanner.description` s'active automatiquement.
- **Breadcrumb global cleanup** — retirer le crumb de `MainLayoutRouter` à la fin de Plan 5c quand tous les écrans embarquent le leur.
- **Raccourcis clavier** sur les meta-bandeaux — aucun exposé en 5b (cohérent avec 5a).
- **Game logo cover** — si on constitue une librairie de logos de jeux, `DetailCover` peut s'étendre pour Game-type projects et Glossaries. Pas pour 5b.
- **`SmallIconButton(danger:)`** — ajouter la variante primitive au lieu d'override couleur. Micro-refactor éventuel en Plan 5c ou follow-up 5b.
- **Description Glossary** — le modèle `Glossary` expose `description?`. Le slot est actif immédiatement côté Glossary.

---

## 10. Open questions pour le plan d'implémentation

1. **`EmptyLanguagesState`** — reste à concevoir en tokens (placeholder cover-like avec icône + message + bouton Add). Décision fine au plan (probable : réutiliser le pattern `GlossaryEmptyState` mais ajusté au contexte Project).
2. **`OverallProgressHeader`** widget — petit composant (~40px : label "Overall progress" + % en accent + bar 4px pleine largeur). Où vit-il ? Probable : inline dans `StatsRail.header` slot, pas un widget exporté.
3. **Initials fallback** — helper `initials(String name)` : premiers caractères par mot, max 2-3 lettres, uppercase. Où vit-il ? Probable : `lib/utils/string_initials.dart` (ou helper privé de `DetailCover`).
4. **Thème test setup** — les tests goldens Project/Glossary doivent injecter `TwmtThemeTokens` via le helper existant (décision Plan 3 mémorisée). Penser à preload `googleFonts` en mode test (pattern Plans 3/4/5a).
5. **Mode Column sous breakpoint** — faut-il tester explicitement le layout en dessous de 1000px ? L'app ne l'atteindra jamais en runtime (min-width 1280), mais le test documente le comportement.
