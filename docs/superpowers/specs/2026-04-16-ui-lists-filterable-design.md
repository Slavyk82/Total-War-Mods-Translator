# TWMT — UI redesign — Plan 5a (Liste filtrable) — design spec

**Date:** 2026-04-16
**Status:** design · pending implementation plan
**Parent spec:** [`2026-04-14-ui-redesign-design.md`](./2026-04-14-ui-redesign-design.md) §7.1
**Reference mockup:** `.superpowers/brainstorm/2035-1776190006/content/archetypes-extra.html` (Projects list)
**Predecessor plans:** Plan 1 (Foundation, shipped), Plan 2 (Navigation, shipped), Plan 3 (Home, shipped), Plan 4 (Editor, shipped)
**Successor plans:** Plan 5b (Détail), Plan 5c (Wizard)
**Branch (proposed):** `feat/ui-lists-filterable`

---

## 1. Intent

Adopter l'archétype « Liste filtrable » de la spec parente §7.1 sur les 5 écrans listes restants : Projects, Mods, Steam Publish, Glossary, Translation Memory. Ces écrans utilisent aujourd'hui des `FluentScaffold` avec couleurs hard-codées, des toolbars hétérogènes, et mélangent card-views custom et `SfDataGrid` non tokenisée.

Le livrable porte sur **le chrome** (tokens, double-toolbar, filter pills, grid à colonnes fixes, crumb intégré) et une légère factorisation de primitives (`FilterToolbar`, `ListRow`, `TokenDataGridTheme`). **Aucune feature ajoutée ou retirée**.

**Non-objectifs :**
- Project Detail, Mod Detail, Glossary entry detail (→ Plan 5b)
- Wizards Pack Compilation, Workshop Publish, Game Translation, New Project (→ Plan 5c)
- Settings, Help (token adoption dans un plan mineur final)
- Nouveaux filtres qui n'existent pas aujourd'hui (ex. `Langue cible` sur Projects) — deferred
- Resize colonnes utilisateur, view switcher grid/list — deferred

---

## 2. Decisions

| # | Question | Décision |
|---|---|---|
| 1 | Scope | 5 écrans : Projects, Mods, Steam Publish (cards) + Glossary, Translation Memory (dense). Project/Mod/Glossary *detail* restent en Plan 5b. |
| 2 | Sous-archétypes | 2 patterns : `list-cards` (volume < 200) via `ListView.builder` + `ListRow` · `dense-list` (volume > 10³) via `SfDataGrid` retokenisée. |
| 3 | Niveau d'abstraction | Primitives composables, pas de scaffold générique `<T>`. Chaque écran compose `Column([FilterToolbar, Expanded(list)])`. |
| 4 | Filtres | Refresh strict : on adopte le chrome (pills, double-toolbar) sur les contrôles existants. Pas d'invention de pills si l'écran n'a qu'une search aujourd'hui. |
| 5 | Refactor Editor | `editor_data_grid_theme.dart` (Plan 4) est déplacé dans `lib/widgets/lists/token_data_grid_theme.dart` et réutilisé. Imports Editor mis à jour en Task 1. |
| 6 | Ordre d'implémentation | Simple-first : primitives → Projects → Mods → Steam Publish → Glossary → TM. Valide `FilterToolbar` sur cas simples avant intégration SfDataGrid. |
| 7 | Crumb | Intégré dans la toolbar écran de chaque liste (clôt le follow-up Plan 2 « breadcrumb au niveau écran »). Le crumb global du `MainLayoutRouter` reste affiché tant que tous les écrans n'ont pas migré ; Plan 5a couvre 5 écrans, pas de suppression globale dans 5a. |
| 8 | Volume Mods | Mods reste en cards (`list-cards`) malgré son `SfDataGrid` actuel — le volume typique (≤ 100) est safe pour `ListView.builder`. |
| 9 | Selection batch | Steam Publish conserve sa batch-selection (select all / outdated). À réimplémenter au-dessus de `ListRow` via `selected` + trailing action. |

---

## 3. Scope — les 5 écrans

| Écran | Fichier principal | LOC actuel | Pattern | Notes |
|---|---|---|---|---|
| Projects | `features/projects/screens/projects_screen.dart` | 280 | `list-cards` | Pagination conservée, New Project button dans toolbar. |
| Mods | `features/mods/screens/mods_screen.dart` | 222 | `list-cards` | Conversion SfDataGrid → `ListView.builder(ListRow)`. Embedded project creation flow préservé. |
| Steam Publish | `features/steam_publish/screens/steam_publish_screen.dart` | 583 | `list-cards` | Sort/filter/search/batch-selection tous préservés, trailing action = publish state. |
| Glossary | `features/glossary/screens/glossary_screen.dart` | 248 | `dense-list` | SfDataGrid retokenisée, inline entry editor panel conservé à droite. |
| Translation Memory | `features/translation_memory/screens/translation_memory_screen.dart` | 232 | `dense-list` | SfDataGrid retokenisée, pagination conservée, statistics panel préservé. |

**Total** : ~1565 LOC refondues. +400 LOC de primitives partagées. Après refactor attendu : ~1490 LOC écrans + 400 primitives = **+325 LOC nets**, compensés par la suppression des couleurs hard-codées et duplications inter-écrans.

---

## 4. Primitives à extraire

Emplacement : `lib/widgets/lists/` (nouveau dossier, pattern Plan 3 `lib/widgets/cards/`).

### 4.1 `FilterToolbar`

Double-ligne §7.1 :
- Ligne 1 : slot `leading` (crumb + titre + compteur) + slot `trailing` (search, sort, view, actions globales). Séparateurs `sep` 1px × 22px.
- Ligne 2 : liste de `FilterPillGroup`. Scrollable horizontal si débordement.

```
FilterToolbar({
  required Widget leading,
  List<Widget> trailing = const [],
  List<FilterPillGroup> pillGroups = const [],
})
```

Hauteur totale : 48px (ligne 1) + 40px (ligne 2) + séparateur 1px = 89px. Si `pillGroups.isEmpty`, ligne 2 masquée (48px total).

### 4.2 `FilterPillGroup` + `FilterPill`

`FilterPillGroup` : label caps-mono `--text-dim` + row de `FilterPill`. Espacement 8px inter-pills, 12px inter-groupes.

`FilterPill` : §6.2 — bg `--panel-2` + fg `--text-mid` off, bg `--accent-bg` + border/fg `--accent` on. Optional `count` en font-mono + `--text-faint` à droite.

```
FilterPill({
  required String label,
  required bool selected,
  int? count,
  required VoidCallback onToggle,
})
```

### 4.3 `ListRow`

Grid-template-columns fixe + dernière colonne optionnelle pour `trailingAction` §7.1. Largeurs passées en `List<double | _Flex>` via sealed class locale `ListRowColumn`.

```
ListRow({
  required List<ListRowColumn> columns,
  required List<Widget> children,
  bool selected = false,
  VoidCallback? onTap,
  Widget? trailingAction,
})
```

Hauteur 56px default, configurable. Border-left 2px `--accent` si `selected`. Hover : border `--text-dim` (§8).

### 4.4 `ListRowHeader`

Même grid-template, hauteur 32px, font-mono 11px caps, `--text-dim`, separator bottom 1px `--border`. API miroir de `ListRow` avec `children: List<String>` (labels simples) ou `children: List<Widget>` (labels cliquables pour sort).

### 4.5 `TokenDataGridTheme`

**Refactor** : `lib/features/translation_editor/theme/editor_data_grid_theme.dart` est déplacé dans `lib/widgets/lists/token_data_grid_theme.dart`. Factorisation de l'helper `buildTokenDataGridTheme(TwmtThemeTokens tokens) → SfDataGridThemeData`. L'Editor consomme le nouveau chemin, Glossary et TM l'appliquent via `SfDataGridTheme(data: buildTokenDataGridTheme(context.tokens), child: SfDataGrid(...))`.

---

## 5. Tests

Pattern Plan 3/4 (goldens + widget tests).

**Widget tests primitives** (~15 tests) :
- `FilterToolbar` : layout double-ligne, pills row masquée si vide, leading/trailing slots.
- `FilterPill` : états on/off, count visible/absent, onToggle.
- `FilterPillGroup` : label caps, row horizontal, spacing.
- `ListRow` : grid-template-columns, selected border, trailingAction visible, hover/selected couleurs.
- `ListRowHeader` : miroir minimal.

**Widget tests écrans** (~20 tests, 4 × 5) :
- Chargement + empty state
- Filter pill toggle → list filtered
- Selection (si applicable : Steam Publish batch, Projects single)
- Trailing action tap (si applicable)

**Golden tests** : 2 thèmes × 1 état principal par écran = **10 goldens**. États ajoutés seulement si review le demande. Pas de goldens pour états vides (coûteux, peu informatifs).

**Tests d'Editor existants** : mise à jour des imports `editor_data_grid_theme.dart` → `token_data_grid_theme.dart`. Aucune régression attendue, snapshot identique.

**Cible** : 1314 → ~1360 tests (+45).

---

## 6. Migration

**Worktree** :
- Branche `feat/ui-lists-filterable` depuis `main`
- Worktree `.worktrees/ui-lists/`
- Copier `windows/` + `flutter pub get` + `dart run build_runner build --delete-conflicting-outputs` après `git worktree add` (pattern mémoire)

**Task order** (séquentiel, 1 commit par task) :

| Task | Contenu | Verification |
|---|---|---|
| 1 | Extract primitives + relocalise `token_data_grid_theme.dart` + met à jour imports Editor | tests primitives + editor tests verts |
| 2 | Projects list refondu | tests Projects + golden |
| 3 | Mods list refondu (SfDataGrid → cards) | tests Mods + golden |
| 4 | Steam Publish list refondu (batch préservé) | tests Steam + golden |
| 5 | Glossary list refondu (dense, inline editor conservé) | tests Glossary + golden |
| 6 | Translation Memory list refondu (dense) | tests TM + golden |
| 7 | Goldens consolidés + regen si nécessaire + lint | full suite + `flutter analyze` |

**Conventions** :
- Commits conformes CLAUDE.md (anglais, `type: description`, pas de mention AI)
- Tokens exclusivement via `context.tokens` — zéro `Colors.xxxxxx` ou `Theme.of(context).colorScheme.xxx` dans les écrans refondus
- `FluentScaffold` retiré de chaque écran refondu

---

## 7. Follow-ups déférés (explicites)

- **Pills manquantes** : Projects `Langue cible`, Mods `Mise à jour`, Steam Publish `État de publication` — aucun provider d'agrégation aujourd'hui. 5b/5c ou plan dédié.
- **Resize colonnes utilisateur** : hors scope. Les colonnes sont fixées par design (§7.1).
- **View switcher grid/list Projects** : conservé si présent aujourd'hui (pattern custom), pas amélioré.
- **Breadcrumb global** : les 5 écrans embarquent leur crumb mais le `MainLayoutRouter` continue d'afficher le crumb global tant que Project/Mod Detail et les wizards n'ont pas migré. Suppression globale reportée à la fin de Plan 5c.
- **Virtualisation Mods** : `ListView.builder` suffit au volume typique (≤ 100). Si un jeu expose > 500 mods installés, évaluer le passage en `dense-list`.
- **Settings / Help adoption tokens** : plan mineur en fin de refonte, pas 5a.

---

## 8. Risques

- **Golden drift pendant la série** : les primitives évoluent aux Tasks 2-4, ce qui peut invalider les goldens des écrans déjà faits. Mitigation : générer les goldens après Task 7 uniquement, ou régénérer en batch à chaque changement.
- **SfDataGrid retokenisation Glossary/TM** : le Plan 4 a validé le pattern sur l'Editor, mais Glossary utilise un inline editor panel qui peut se comporter différemment. Prévoir un buffer en Task 5.
- **Steam Publish batch selection** : le code actuel est tissé dans le layout. Isoler l'état `selected: Set<ID>` et le passer à `ListRow.selected` via un provider local. Si ça force un refactor Riverpod non prévu, stop et discuter.
- **Import breakage Editor** : le déplacement de `editor_data_grid_theme.dart` touche ~5-10 fichiers. Grep exhaustif avant Edit batch en Task 1.

---

## 9. Open questions pour le plan d'implémentation

1. **`ListRowColumn` sealed class** — API exacte : `ListRowColumn.fixed(double)` vs `ListRowColumn.flex(int)` vs passer directement `List<int|double>` où int = flex et double = pixels ? Décision au plan.
2. **Hauteur de ligne Projects** — 56px (default §7.1) ou dérive de la cover 110×68 du mockup detail ? Décision au plan (probable 72px avec cover).
3. **Order des colonnes par écran** — à figer au plan en lisant chaque `_*Screen.build` actuel et en mappant 1:1 + ajout trailing action.
4. **Glossary inline editor** — doit-il rester en panel à droite (comme aujourd'hui) ou migrer vers le pattern Editor inspector 320px ? Le spec parent §7.1 n'impose pas. Décision au plan (probable : conserver panel à droite, c'est cohérent avec l'Editor).
5. **Statistics panel TM** — aujourd'hui à droite. Le garder là, le migrer en statusbar, ou le retirer (vanity) ? Décision au plan.
