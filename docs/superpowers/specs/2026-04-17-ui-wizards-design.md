# TWMT — UI redesign — Plan 5c (Wizard / form) — design spec

**Date:** 2026-04-17
**Status:** design · pending implementation plan
**Parent spec:** [`2026-04-14-ui-redesign-design.md`](./2026-04-14-ui-redesign-design.md) §7.5
**Sibling specs:**
- [`2026-04-16-ui-lists-filterable-design.md`](./2026-04-16-ui-lists-filterable-design.md) (Plan 5a — §7.1 primitives reused)
- [`2026-04-17-ui-details-design.md`](./2026-04-17-ui-details-design.md) (Plan 5b — Detail primitives reused)

**Predecessor plans (all shipped on main):** Plan 1 (Foundation), Plan 2 (Navigation), Plan 3 (Home), Plan 4 (Editor), Plan 5a (Lists), Plan 5b (Details).
**Successor plans:** none — closes the UI redesign initiative.
**Branch (proposed):** `feat/ui-wizards`

---

## 1. Intent

Adopter l'archétype « Wizard / form » §7.5 sur les 3 écrans wizard existants (Pack Compilation editor, Workshop Publish single, Workshop Publish batch) et séparer Pack Compilation en deux routes distinctes (liste §7.1 + editor §7.5). Livrable : **chrome + composition** (tokens, sticky form 380px, dynamic zone, summary box live preview, toolbar crumb), extraction de primitives composables `lib/widgets/wizard/`, et factorisation d'un `DetailScreenToolbar` partagé (clôt un follow-up Plan 5b reviewer). **Aucune refonte fonctionnelle.**

**Non-objectifs :**
- **Game Translation setup dialog** et **New Project dialog** — conservés comme dialogs multi-step, retokenisation déferée à un plan mineur final.
- **Settings**, **Help** — adoption des tokens dans un plan mineur final.
- **Pack Compilation filter pills** — aucun provider d'agrégation aujourd'hui, déferé.
- **Workshop Publish result panel riche** — structure actuelle conservée, feature distincte.
- Refonte fonctionnelle — aucun ajout/retrait de feature.

---

## 2. Decisions

| # | Question | Décision | Rationale |
|---|---|---|---|
| 1 | Scope | 3 écrans (Pack Compilation editor + Workshop Publish single + batch). Pack Compilation list migre aussi vers §7.1 (retombée du split de route). Dialogs Game Translation / New Project out. | Plan 5a a posé la convention « refresh chrome, préserve behavior ». Les dialogs restent dialogs : workflow focalisé, fermeture post-succès. |
| 2 | Workshop Publish mode switching | Sticky form reste visible · dynamic zone transitionne preview → progress+logs → result via `AnimatedSwitcher`. | Cohérent §7.5 « dynamic zone montre sorties post-génération » (§11 parent). Le form agit comme vérité de ce qui est soumis. |
| 3 | Pack Compilation list + editor split | Split en 2 routes : `/publishing/pack` = liste §7.1, `/publishing/pack/new` et `/publishing/pack/:id/edit` = editor §7.5. | Cohérent avec le reste de l'app (Projects/Mods/Glossary : liste séparée du détail/éditeur). Chaque écran archétype unique. |
| 4 | Niveau d'abstraction primitives | Composables (pattern Plans 5a/5b) dans `lib/widgets/wizard/` : `StickyFormPanel`, `FormSection`, `SummaryBox`, `DynamicZonePanel`, `WizardScreenLayout`. Pas de scaffold générique. | Symétrie totale avec 5a (`lists/`) et 5b (`detail/`). Chaque écran garde sa liberté sur le contenu dynamique. |
| 5 | Batch Publish dans §7.5 | §7.5 dégénéré : gauche = staging summary read-only (pas de form input) · droite = per-pack status list + logs. | Préserve l'archétype unique pour les 3 écrans Workshop/Pack. La primitive `StickyFormPanel` accepte n'importe quel contenu — le « read-only summary » est valide comme form. |
| 6 | Toolbar crumb | Extraction `DetailScreenToolbar` primitive partagée dans `lib/widgets/detail/` (ou renommage du dossier en `chrome/`). Migration Project Detail + Glossary Detail vers la primitive en Task 1. Les 4 écrans 5c la consomment. | Clôt le Plan 5b code-reviewer follow-up (duplication `_ToolbarCrumb` / `_GlossaryToolbarCrumb` noté sur 2174e25). |
| 7 | Crumb global cleanup | Supprimer le crumb global `MainLayoutRouter` en clôture de 5c, puisque les écrans embarquent tous leur crumb. | Clôture du Plan 2 follow-up « breadcrumb au niveau screen ». |

---

## 3. Scope — les 4 écrans

| Écran | Fichier actuel | Route cible | Archétype | LOC actuel | Notes |
|---|---|---|---|---|---|
| Pack Compilation **list** | `features/pack_compilation/screens/pack_compilation_screen.dart` (branche `_showEditor=false`) + `features/pack_compilation/widgets/compilation_list.dart` | `/publishing/pack` (inchangée) | §7.1 | ~187 + 150 | Migration vers `FilterToolbar` + `ListRow`. Écran nouveau `pack_compilation_list_screen.dart`. |
| Pack Compilation **editor** | `features/pack_compilation/screens/pack_compilation_screen.dart` (branche `_showEditor=true`) + `features/pack_compilation/widgets/compilation_editor.dart` | `/publishing/pack/new` + `/publishing/pack/:id/edit` (nouvelles) | §7.5 | ~187 + 200 | Écran nouveau `pack_compilation_editor_screen.dart`. `CompilationEditor` widget retiré (rôle porté par l'écran). Widgets atomiques (`CompilationProjectSelectionSection`, `ConflictingProjectsPanel`, `CompilationProgressSection`, `CompilationBBCodeSection`, `LogTerminal`) conservés + retokenisés. |
| Workshop Publish **single** | `features/steam_publish/screens/workshop_publish_screen.dart` | `/publishing/steam/single` (inchangée) | §7.5 | 821 | Mode swap (form vs progress) remplacé par sticky form + dynamic zone `AnimatedSwitcher`. `WorkshopPublishNotifier` intact. |
| Workshop Publish **batch** | `features/steam_publish/screens/batch_workshop_publish_screen.dart` | `/publishing/steam/batch` (inchangée) | §7.5 dégénéré | 543 | Gauche = staging summary read-only · droite = per-pack status list + logs. `BatchWorkshopPublishNotifier` intact (démarre batch `initState + postFrame`). |

**Total** : ~2100 LOC écrans refondues. +450 LOC primitives partagées. Après refactor attendu : ~2400 LOC écrans (list + editor split pèse plus) + 450 primitives = **~700 LOC nets**, compensés par la suppression de la logique de mode-swap et de l'état `_showEditor`.

---

## 4. Primitives à extraire

Emplacement : `lib/widgets/wizard/` (nouveau dossier, pattern Plans 3/5a/5b).

### 4.1 `StickyFormPanel`

Colonne gauche 380px, contenu sticky au scroll :

```dart
StickyFormPanel({
  required List<Widget> sections,           // typiquement FormSection
  SummaryBox? summary,                      // rendu au-dessus des actions
  List<Widget> actions = const [],          // full-width stacked boutons primaires
  double width = 380,
  EdgeInsetsGeometry padding = const EdgeInsets.all(24),
})
```

Rendu :
- `Container(width: 380, bg: tokens.panel, border-right: 1px tokens.border, padding: 24)`.
- Body = `CustomScrollView` + `SliverList` des sections + `SliverToBoxAdapter` pour summary + `SliverFillRemaining` / footer Column pour actions. Le sticky s'obtient en maintenant la colonne dans le flux principal (le parent scroll est la dynamic zone). Pour la phase 1 : simple `SingleChildScrollView`, sticky assuré par la largeur fixe et le parent qui ne scroll pas côté form.

### 4.2 `FormSection`

Groupe titré de champs :

```dart
FormSection({
  required String label,                    // "Basics", "Compiled pack", "Publication"
  required List<Widget> children,           // TextField, Dropdown, ReadonlyField, etc.
  String? helpText,                         // optionnel, sous le label
})
```

Rendu : `Column([LabelCapsMono, 1pxDivider, ...children (gap 10), helpText])`. Margin-bottom 16. Labels en `tokens.fontMono` 10px caps letterSpacing 1.2 `tokens.textDim`.

### 4.3 `SummaryBox`

Live preview §7.5 dashed border :

```dart
SummaryBox({
  required String label,                    // caps-mono kicker ("WILL GENERATE")
  required List<SummaryLine> lines,
  SummarySemantics semantics = neutral,     // couleur kicker + border
})

SummaryLine({
  required String key,
  required String value,
  SummarySemantics? semantics,              // override per-line
})

enum SummarySemantics { neutral, accent, ok, warn, err }
```

Rendu :
- Container, `border: DashedBorder(1px, semantic color)`, `radius: tokens.radiusSm`, padding 12/14, bg transparent.
- Header : kicker caps-mono 10px semantic color + kicker padding-bottom 6.
- Chaque ligne : `Row([Expanded(Text(key, textMid)), Text(value, fontMono semanticColor w600)])`, padding-vertical 4.

`DashedBorder` : helper à créer ou via `CustomPainter` (plusieurs libs existent — préférer un `CustomPaint` minimal pour éviter un package).

### 4.4 `DynamicZonePanel`

Slot colonne droite 1fr :

```dart
DynamicZonePanel({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(24),
})
```

Rendu minimal : `Padding(child: child)`. Existe comme primitive sémantique (les écrans composent `Column` / `AnimatedSwitcher` / `Stack` à l'intérieur). Si la primitive est trop légère à l'implémentation, basculer vers `Expanded(Padding(child: ...))` direct dans les écrans.

### 4.5 `WizardScreenLayout`

Composition §7.5 complète :

```dart
WizardScreenLayout({
  required Widget toolbar,                  // DetailScreenToolbar typiquement
  required StickyFormPanel formPanel,
  required DynamicZonePanel dynamicZone,
})
```

Rendu : `Column([toolbar, Expanded(Row([formPanel, VerticalDivider(width: 1, color: tokens.border), Expanded(dynamicZone)]))])`.

### 4.6 `DetailScreenToolbar` (Task 1 — primitive partagée)

Extraction du pattern `_ToolbarCrumb` / `_GlossaryToolbarCrumb` dupliqué en Plan 5b. Emplacement : `lib/widgets/detail/detail_screen_toolbar.dart`.

```dart
DetailScreenToolbar({
  required String crumb,                    // "Publishing › Pack › New"
  required VoidCallback onBack,
  List<Widget> trailing = const [],         // optionnel, actions à droite
})
```

Rendu : `Container(height: 48, bg: tokens.panel, border-bottom: 1px tokens.border)` + `Row([SmallIconButton(arrow_left, onBack), 12px gap, Flexible(Text(crumb, fontMono 12 textDim ls 0.5, ellipsis)), Spacer, ...trailing])`.

### 4.7 Primitives réutilisées

- **Plans 5a :** `FilterToolbar`, `FilterPill`, `ListToolbarLeading`, `ListSearchField`, `ListRow`, `ListRowHeader`, `SmallTextButton`, `SmallIconButton`, `StatusPill`, `formatRelativeSince`, `buildTokenDataGridTheme`, `clockProvider`.
- **Plan 5b :** `DetailMetaBanner` (pas utilisée), `StatsRail` (optionnelle pour batch staging summary — décision d'implémentation).

---

## 5. Layouts par écran

### 5.1 Pack Compilation list (§7.1)

Archétype strict §7.1, pattern 5a :

```
Column [
  FilterToolbar(
    leading: ListToolbarLeading(
      icon: FluentIcons.package_multiple_24_regular,
      title: "Pack compilations",
      countLabel: "${filtered.length} / ${total.length}"
    ),
    trailing: [
      ListSearchField(value: q, onChanged: ..., onClear: ...),
      SmallTextButton("+ New compilation", primary: true, icon: add, onTap: () => context.push('/publishing/pack/new')),
    ],
    pillGroups: [],                                                   // pas de pills (deferred)
  ),
  Expanded(
    child: ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) => ListRow(
        columns: const [
          ListRowColumn.flex(1),                                      // name + description
          ListRowColumn.fixed(140),                                   // game
          ListRowColumn.fixed(100),                                   // project count
          ListRowColumn.fixed(100),                                   // updated (relative)
        ],
        children: [
          _NameCell(name, description),
          Text(gameName, fontMono textDim),
          Text("${c.projectCount} packs", fontMono),
          Text(formatRelativeSince(c.updatedAt), fontMono textFaint),
        ],
        trailingAction: Row([
          SmallTextButton("Edit", onTap: () => context.push('/publishing/pack/${c.id}/edit')),
          SmallIconButton(compile_icon, onTap: _quickCompile, foreground: tokens.accent),
          SmallIconButton(delete_icon, onTap: _confirmDelete, foreground: tokens.err, background: tokens.errBg),
        ]),
        onTap: () => context.push('/publishing/pack/${c.id}/edit'),
      ),
    ),
  ),
]
```

Dialogs (`_confirmDelete`, compile toast) préservés.

### 5.2 Pack Compilation editor (§7.5)

```
WizardScreenLayout(
  toolbar: DetailScreenToolbar(
    crumb: "Publishing › Pack compilation › ${state.isEditing ? state.name : 'New'}",
    onBack: _handleBack,
  ),
  formPanel: StickyFormPanel(
    sections: [
      FormSection("Basics", [
        TextField(controller: _nameController, label: "Name"),
        TextField(controller: _descriptionController, label: "Description (optional)", maxLines: 2),
        Dropdown<LanguageId>(value: selectedLanguageId, items: languages, onChanged: ...),
      ]),
      FormSection("Output", [
        ReadonlyField(label: "Filename", value: computedPackName),
        TextField(controller: _outputPathController, label: "Output folder", suffix: folder_picker),
      ]),
    ],
    summary: SummaryBox(
      label: "WILL GENERATE",
      lines: [
        ("Filename", computedPackName),
        ("Projects", "${selectedProjectIds.length} selected"),
        ("Target language", selectedLanguageName ?? "—"),
        ("Conflicts", conflictCount > 0 ? "${conflictCount} ⚠" : "None",
          semantics: conflictCount > 0 ? warn : ok),
        ("Size estimate", humanSize(estimatedBytes)),
      ],
      semantics: conflictCount > 0 ? warn : accent,
    ),
    actions: [
      SmallTextButton("Cancel", onTap: () => context.pop(), disabled: state.isCompiling),
      FilledButton("Compile", icon: play, onTap: _compile, enabled: _canSubmit),
    ],
  ),
  dynamicZone: DynamicZonePanel(
    child: AnimatedSwitcher(
      duration: 200ms,
      child: state.isCompiling
        ? _CompilingView(
            progress: CompilationProgressSection(onStop: ...),
            logs: LogTerminal(expand: true),
          )
        : _EditingView(
            selection: CompilationProjectSelectionSection(state, onToggle, onSelectAll, onDeselectAll),
            conflicts: showConflicts ? ConflictingProjectsPanel() : null,
            bbcode: state.lastCompiledAt != null ? CompilationBBCodeSection(state) : null,
          ),
    ),
  ),
)
```

Widgets conservés intacts (retokenisés si besoin) : `CompilationProjectSelectionSection`, `ConflictingProjectsPanel`, `CompilationProgressSection`, `CompilationBBCodeSection`, `LogTerminal`. Dialogs (`ProjectConflictsDetailDialog`) préservés.

**Suppressions** : `compilation_editor.dart` (rôle porté par l'écran), `compilation_editor_sections.dart` et `compilation_editor_form_widgets.dart` refactorés en appels directs à `FormSection` primitive (restes regroupés dans l'écran si spécifiques).

### 5.3 Workshop Publish single (§7.5)

```
WizardScreenLayout(
  toolbar: DetailScreenToolbar(
    crumb: "Publishing › Steam Workshop › ${item?.projectName ?? ''}",
    onBack: _handleBack,
  ),
  formPanel: StickyFormPanel(
    sections: [
      FormSection("Publication", [
        TextField(controller: _titleController, label: "Title", maxLength: 128),
        TextField(controller: _descriptionController, label: "Description", maxLines: 6),
        Dropdown<WorkshopVisibility>(value: _visibility, items: [...], label: "Visibility"),
        TextField(controller: _changeNoteController, label: "Change notes", maxLines: 3),
      ]),
      FormSection("Pack", [
        ReadonlyField(label: "Pack path", value: _packFilePath),
        if (_isUpdate) ReadonlyField(label: "Steam ID", value: _item!.publishedSteamId!),
      ]),
    ],
    summary: SummaryBox(
      label: _isUpdate ? "WILL UPDATE" : "WILL PUBLISH",
      lines: [
        ("Mode", _isUpdate ? "Update existing" : "New publish"),
        ("Pack size", humanSize(packSizeBytes)),
        ("Visibility", _visibility.displayLabel),
        if (_isUpdate) ("Steam ID", _item!.publishedSteamId!),
      ],
      semantics: accent,
    ),
    actions: [
      SmallTextButton("Cancel", onTap: () => context.pop(), disabled: state.isPublishing),
      FilledButton(_isUpdate ? "Update" : "Publish", icon: cloud_upload,
        onTap: _submit, enabled: _canSubmit),
    ],
  ),
  dynamicZone: DynamicZonePanel(
    child: AnimatedSwitcher(
      duration: 200ms,
      child: switch (state.phase) {
        idle                => _PublishPreview(title: _titleController.text, description: _descriptionController.text, _visibility, _isUpdate, _packFilePath),
        publishing|uploading|processing => _PublishProgressView(phase: state.phase, elapsed: _elapsed, logs: state.logs),
        done                => _PublishResultPanel(result: state.result, onOpenInSteam: ..., onClose: ...),
        failed              => _PublishErrorPanel(error: state.error, onRetry: ..., onClose: ...),
      },
    ),
  ),
)
```

`WorkshopPublishNotifier` inchangé. `LogTerminal` réutilisée. `SteamGuardDialog`, `SteamLoginDialog`, `SteamCmdInstallDialog`, `WorkshopPublishSettingsDialog` préservés.

### 5.4 Workshop Publish batch (§7.5 dégénéré)

```
WizardScreenLayout(
  toolbar: DetailScreenToolbar(
    crumb: "Publishing › Steam Workshop › Batch (${items.length} packs)",
    onBack: _confirmLeaveIfActive,
  ),
  formPanel: StickyFormPanel(
    sections: [
      FormSection("Staging", [
        _StagingRow("Packs",     "${items.length}"),
        _StagingRow("Total size", humanSize(totalBytes)),
        _StagingRow("Publish",   "$publishCount"),
        _StagingRow("Update",    "$updateCount"),
        _StagingRow("Account",   username),
        _StagingRow("Elapsed",   _elapsedTime),
      ]),
    ],
    summary: null,                                                    // la staging section EST le summary
    actions: [
      if (state.isPublishing) FilledButton("Stop", icon: stop, danger: true, onTap: _confirmCancel)
      else SmallTextButton("Close", onTap: () => context.pop()),
    ],
  ),
  dynamicZone: DynamicZonePanel(
    child: Column[
      _OverallProgressHeader(completed: state.completedCount, total: items.length, percent: state.progress),
      const SizedBox(height: 12),
      Expanded(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => _BatchPackRow(
            packName: items[i].projectName,
            mode: items[i].isUpdate ? "update" : "publish",
            status: state.statusFor(items[i]),               // pending | uploading | done | failed
            percent: state.progressFor(items[i]),
            error: state.errorFor(items[i]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(height: 240, child: LogTerminal(expand: false)),
    ]
  ),
)
```

`BatchWorkshopPublishNotifier` intact — démarrage batch dans `initState` via `addPostFrameCallback` préservé. Dialogs (`SteamGuardDialog`) préservés.

**`_StagingRow`** : helper simple (label fontBody textMid + value fontMono w600), inline dans l'écran.
**`_BatchPackRow`** : `ListRow` avec 3 colonnes (pack name + mode pill, progress bar, status pill). Pas de trailing action.

### 5.5 Migration Project Detail + Glossary Detail vers `DetailScreenToolbar`

Task 1 :
- Extraire `_ToolbarCrumb` de `project_detail_screen.dart` et `_GlossaryToolbarCrumb` de `glossary_screen.dart` dans `lib/widgets/detail/detail_screen_toolbar.dart` avec l'API §4.6.
- Remplacer les usages dans les 2 écrans.
- Vérifier que les 4 goldens (Project Detail × 2 thèmes + Glossary Detail × 2 thèmes) restent byte-identiques — puisque le rendu ne change pas. Si drift, investiguer avant de regenerate.

---

## 6. Tests

Pattern Plans 3/4/5a/5b (goldens + widget tests).

**Widget tests primitives** (~15 tests, `test/widgets/wizard/` + `test/widgets/detail/`) :
- `DetailScreenToolbar_test.dart` : crumb rendu, back tap, trailing actions, sticky 48px.
- `StickyFormPanel_test.dart` : layout 380px, sections, summary optionnel, actions bottom.
- `FormSection_test.dart` : label caps-mono, children empilés, helpText visible/absent.
- `SummaryBox_test.dart` : dashed border, kicker, lignes, sémantiques → couleurs tokens.
- `DynamicZonePanel_test.dart` : contenu libre + padding (minimal).
- `WizardScreenLayout_test.dart` : composition Column + Row, divider vertical.

**Widget tests écrans** (~15 tests) :
- Pack Compilation list : chargement, search filtre, "+ New" navigue, row tap edit, delete confirme.
- Pack Compilation editor : new → state vide, edit → state chargé, form inputs binding, selection toggle, summary recalcule, compile démarre, dynamic zone switche, BBCode apparaît post-compile.
- Workshop Publish single : form inputs, preview avant submit, publish bascule progress, result success/error, Open in Steam tap.
- Workshop Publish batch : staging summary rendu, per-pack progress, stop confirmation, elapsed tick.

**Golden tests** : 2 thèmes × 4 écrans × 1 état principal = **8 goldens**.
- Pack Compilation list : populated.
- Pack Compilation editor : pre-compile (form filled, selection partielle, BBCode vide).
- Workshop Publish single : pre-submit (form filled, preview rendu à droite).
- Workshop Publish batch : in-progress (50% overall, quelques packs done + en cours).

**Tests existants à mettre à jour / migrer** :
- `test/features/pack_compilation/screens/*` → split en `pack_compilation_list_screen_test.dart` + `pack_compilation_editor_screen_test.dart`. Anciens tests adaptés.
- `test/features/steam_publish/screens/workshop_publish_screen_test.dart` → struct changes.
- `test/features/steam_publish/screens/batch_workshop_publish_screen_test.dart` → struct changes.
- `test/features/projects/screens/project_detail_screen_test.dart` → remplace `_ToolbarCrumb` par `DetailScreenToolbar` dans les assertions si applicable.
- `test/features/glossary/screens/glossary_screen_test.dart` → idem.

**Cible** : 1330 → **~1385** tests (+55 bruts, après adaptations).

---

## 7. Migration

### 7.1 Worktree

- Branche : `feat/ui-wizards` depuis `main`.
- Worktree : `.worktrees/ui-wizards/`.
- Setup : `cp -r ../../windows ./`, `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs` (gotcha mémoire).

### 7.2 Task order (séquentiel, 1 commit par task)

| Task | Contenu | Verification |
|---|---|---|
| 1 | `DetailScreenToolbar` primitive partagée (`lib/widgets/detail/`) + migration Project Detail + Glossary Detail | Tests + 4 goldens (Project/Glossary × 2 thèmes) restent identiques |
| 2 | Primitives `lib/widgets/wizard/` : `FormSection`, `SummaryBox` (+ `SummaryLine`, `SummarySemantics` enum), `StickyFormPanel`, `DynamicZonePanel`, `WizardScreenLayout` + tests | Tests primitives verts |
| 3 | Routes Pack Compilation : ajout `/publishing/pack/new` et `/publishing/pack/:id/edit` dans `app_router.dart` · redirection `/publishing/pack` reste la liste | `flutter analyze` clean, route params OK |
| 4 | Pack Compilation **list** refondu §7.1 : nouveau `pack_compilation_list_screen.dart` · `pack_compilation_screen.dart` + `compilation_list.dart` supprimés | Tests list + golden atelier/forge |
| 5 | Pack Compilation **editor** refondu §7.5 : nouveau `pack_compilation_editor_screen.dart` · `compilation_editor.dart` supprimé · widgets atomiques retokenisés · `compilation_editor_sections.dart` et `compilation_editor_form_widgets.dart` refactorés en `FormSection` | Tests editor + golden |
| 6 | Workshop Publish single refondu §7.5 | Tests + golden |
| 7 | Workshop Publish batch refondu §7.5 dégénéré | Tests + golden |
| 8 | Retrait du crumb global `MainLayoutRouter` (clôt Plan 2 follow-up) + goldens regen si drift · `flutter analyze` · full suite | `flutter test` vert à ~1385 |

### 7.3 Conventions

- Commits en anglais, format `type: description`, sans mention AI (CLAUDE.md).
- Tokens exclusivement via `context.tokens` — zéro `Colors.xxxxxx`, zéro `Theme.of().colorScheme.xxx`.
- `FluentScaffold` retiré des 4 écrans refondus.

---

## 8. Risques

- **Route split Pack Compilation** — l'état actuel est porté par `compilationEditorProvider` dans le même écran. Avec 2 routes, la nouvelle route (`/new` ou `/:id/edit`) doit initialiser le notifier avec reset ou load selon le mode. Tests de navigation (deep-link + back) nécessaires. Prévoir un `initState` qui appelle `notifier.initFor(id)` avec une surcharge `new` / `edit(id)`.
- **Workshop Publish sticky form pendant progress** — avec `AnimatedSwitcher` côté dynamic zone seulement, le form reste monté pendant l'upload. Bien vérifier que `TextEditingController` ne se régénère pas (focus loss). Si c'est un problème, accepter que le form passe en read-only via `Form.enabled = !isPublishing`.
- **Batch Publish notifier timing** — démarre batch dans `initState + postFrame`. Refonte de l'écran doit préserver ce timing. Prévoir un `StaffulWidget` avec `initState` qui re-lance le `publishBatch` si `staging` est présent.
- **`DetailScreenToolbar` golden drift** — Task 1 factorise du code visuellement identique. Les goldens doivent rester byte-identiques. Si drift même d'1 pixel, investiguer avant de regenerate (indique un refactor qui change le rendu).
- **`DashedBorder` pour `SummaryBox`** — Flutter ne fournit pas de dashed border natif. Implémenter via `CustomPainter` léger (une 50-80 LOC). Alternative : package `dotted_border` (discipline anti-deps). Décision : `CustomPainter` home-made.
- **`LogTerminal` cohabitation** — utilisée par Editor + Pack Compilation (existant) + Workshop Publish (nouveau). Si retokenisation, valider les 3 écrans.
- **Batch Publish `_StagingRow` vs `FormSection`** — l'écran batch a une section "Staging" qui n'est pas vraiment un form (pas d'inputs). Possible de la coder directement en `Column` au lieu d'utiliser `FormSection` avec des `_StagingRow` widgets. Décision d'implémentation : garder `FormSection` pour la symétrie chrome, mais contenu en Rows simples.
- **Crumb global cleanup Task 8** — retirer le crumb de `MainLayoutRouter` alors que **certains écrans** n'embarquent peut-être pas encore le leur (Game Translation, Settings, Help). Vérifier au moment de Task 8 si tous les écrans visitables ont leur crumb local. Si non, adapter ou reporter.

---

## 9. Follow-ups déférés (explicites)

- **Game Translation setup dialog** et **New Project dialog** — retokenisation minimale (pas de conversion en écran §7.5). Plan 5d mineur ou absorbé dans un "cleanup final".
- **Pack Compilation filter pills** — nécessite un provider d'agrégation (état par compilation : compiled / outdated / never-compiled). Pas en 5c.
- **Workshop Publish rich result panel** — copy link, changelog template, re-publish button. Feature à part.
- **Batch Publish re-launch from UI** — aujourd'hui staged depuis Steam Publish list. Si on veut un bouton "Re-run" in-situ, nouveau plan.
- **Settings / Help token adoption** — plan mineur final (Plan 5d ?).

---

## 10. Open questions pour le plan d'implémentation

1. **`SummaryBox` dashed border** — implémentation `CustomPainter` vs extension du `BoxDecoration` via `DecoratedBox`. Décision au plan (probable : `CustomPainter` 60 LOC).
2. **`_StagingRow` dans batch** — inline dans l'écran ou primitive partagée ? Ne sert qu'une fois ; inline probablement.
3. **`_OverallProgressHeader` / `_BatchPackRow` / `_StagingRow`** — tous helpers privés à l'écran batch. OK de les laisser internes.
4. **Route parameter parsing** — `/publishing/pack/:id/edit` vs `/publishing/pack/new` : distinction via path pattern ou via query param `?mode=new` ? Décision au plan (probable : path patterns distincts comme fait).
5. **Animation transition `AnimatedSwitcher`** — durée 200ms, curve easeInOut. Décision au plan.
6. **`FormSection.helpText` rendu** — sous le label ou en bottom de section ? Décision au plan (probable : sous le label, petit 11px).
7. **Reusing `StatsRail` for batch summary** — alternative à `FormSection` pour la section "Staging". À benchmarker visuellement au plan.
