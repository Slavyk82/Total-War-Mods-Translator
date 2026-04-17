# TWMT — UI redesign — Plan 5d (Cleanup & retokenization) — design spec

**Date:** 2026-04-17
**Status:** design · pending implementation plan
**Parent spec:** [`2026-04-14-ui-redesign-design.md`](./2026-04-14-ui-redesign-design.md)
**Sibling specs:**
- [`2026-04-16-ui-lists-filterable-design.md`](./2026-04-16-ui-lists-filterable-design.md) (Plan 5a)
- [`2026-04-17-ui-details-design.md`](./2026-04-17-ui-details-design.md) (Plan 5b)
- [`2026-04-17-ui-wizards-design.md`](./2026-04-17-ui-wizards-design.md) (Plan 5c — primitives reused & follow-ups absorbed)

**Predecessor plans (all shipped):** Plans 1, 2, 3, 4, 5a, 5b, 5c.
**Successor plan:** Plan 5e — Settings retokenization (~20 widget files, dedicated scope).
**Branch (proposed):** `feat/ui-cleanup`

---

## 1. Intent

Clôture du redesign UI (hors Settings) : extraire 3 form primitives partagées vers `lib/widgets/wizard/`, retokéniser structurellement les 2 dialogs multi-step (Game Translation setup + New Project) et le Help screen, absorber 4 follow-ups chirurgicaux de Plan 5c (P1 : remove `Future.delayed(100ms)` race ; P2 : controller sync via `ref.listen` ; P3 : narrow `try/catch` workshop publish ; P4 : `@visibleForTesting` sur staging notifiers). Zero nouvelle feature.

**Non-objectifs :**
- **Settings retokenization** — Plan 5e (~20 widget files, trop large pour ce plan).
- **`StatusPillPalette` extraction** — YAGNI, deferred jusqu'à 3e consommateur.
- **`LogTerminal` retokenization** — dark bg `0xFF1E1E1E` / fg `0xFFCCCCCC` assumé comme convention terminal.
- **Refonte fonctionnelle des dialogs** — preservation complète des 2-step / 3-step flows.
- **Conversion dialogs → écrans** — dialogs restent `AlertDialog`.

---

## 2. Decisions

| # | Question | Décision | Rationale |
|---|---|---|---|
| 1 | Scope | 3 form primitives extraction + 2 dialogs retokenisés + Help screen retokenisé + 4 follow-ups 5c. Settings deferred en Plan 5e. | Settings = 20+ widget files, scope dédié. Le reste est homogène (retokenisation + 5c cleanup). |
| 2 | Retokenisation level | β structurelle : tokens partout, `SmallTextButton`/`SmallIconButton` pour actions, `TokenTextField` pour inputs, drop `FluentScaffold` sur Help. | α color swap seul serait insuffisant : les boutons divergents créeraient une dette visuelle. |
| 3 | Primitives extraction | `TokenTextField` + `LabeledField` + `ReadonlyField` extraits (3 form widgets, 3-4 consommateurs chacun). `StatusPillPalette` reste privé. | YAGNI. Les 3 form widgets ont déjà 3+ consommateurs (Workshop Publish single + batch + dialogs). `StatusPillPalette` seulement 2 consommateurs potentiels. |
| 4 | 5c P1 refactor | `ref.listen` sur `compilationEditorProvider.select((s) => (s.selectedProjectIds, s.selectedLanguageId))` pour déclencher `analyze` automatiquement. | Supprime la race `Future.delayed(100ms)` x3. Riverpod gère la cleanup du listener. |
| 5 | 5c P2 refactor | Controller sync via `ref.listen` dans `initState` (ou top-level dans `build` via Consumer), trigger uniquement sur changements externes (`loadCompilation`, `updateLanguage` auto-fills prefix). | Évite la mutation dans `build()` à chaque frame. |
| 6 | 5c P3 refactor | Narrow `try/catch` : catch uniquement `ProviderException` / `StateError` avec `debugPrint` au lieu de swallow tout. | Expose les erreurs inattendues sans casser les tests ServiceLocator-less. |
| 7 | 5c P4 refactor | `@visibleForTesting` annotation sur `SinglePublishStagingNotifier` + `BatchPublishStagingNotifier`. | Confirme le test-affordance intentionnel. Pas de conversion en provider override pattern (trop d'effort pour peu de valeur). |

---

## 3. Scope — les cibles

| Cible | Fichiers modifiés | LOC touchés | Traitement |
|---|---|---|---|
| Form primitives | Extract depuis `lib/features/steam_publish/screens/workshop_publish_screen.dart` et `.../batch_workshop_publish_screen.dart` | ~100 LOC extract + ~30 LOC imports | Nouveaux `lib/widgets/wizard/token_text_field.dart`, `labeled_field.dart`, `readonly_field.dart`. Screens updated to import. |
| 5c follow-up P3 + P4 | `workshop_publish_screen.dart` + `publish_staging_provider.dart` | ~20 LOC | Narrow catches + `@visibleForTesting` annotations |
| 5c follow-up P1 + P2 | `pack_compilation_editor_screen.dart` | ~50 LOC | `ref.listen` refactors |
| Help screen | `help_screen.dart` + `help_section_content.dart` + `help_toc_sidebar.dart` | ~400 LOC | β retoken complet |
| Game Translation dialog | `create_game_translation_dialog.dart` + `step_select_source.dart` + `step_select_targets.dart` + `add_language_wizard_dialog.dart` | ~1500 LOC | β retoken |
| New Project dialog | `create_project_dialog.dart` + `step_basic_info.dart` + `step_languages.dart` + `step_settings.dart` | ~1200 LOC | β retoken |

**Total** : ~3200 LOC touchés, aucun fichier supprimé, 3 nouveaux fichiers primitives + 3 nouveaux tests primitives.

---

## 4. Primitives à extraire

Emplacement : `lib/widgets/wizard/` (compléter l'existant 5c).

### 4.1 `TokenTextField`

Signature :

```dart
TokenTextField({
  required TextEditingController controller,
  String? hintText,
  int maxLines = 1,
  int? maxLength,
  bool enabled = true,
  ValueChanged<String>? onChanged,
  FocusNode? focusNode,
})
```

Rendu : `TextField` avec `tokens.panel2` fill + `tokens.border` enabled/disabled, `tokens.accent` focused, `tokens.fontBody` 13px `tokens.text`, placeholder `tokens.fontBody` 13px `tokens.textFaint`, radius `tokens.radiusSm`, `isDense: true`, `contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)`.

### 4.2 `LabeledField`

Signature :

```dart
LabeledField({
  required String label,
  required Widget child,
  String? helpText,
})
```

Rendu : `Column([Text(label.toUpperCase(), fontMono 10px textDim ls 1.2 w600), SizedBox(6), child, if (helpText != null) SizedBox(4) + Text(helpText, fontBody 11px textFaint)])`. Margin-bottom 12. CrossAxisAlignment stretch.

### 4.3 `ReadonlyField`

Signature :

```dart
ReadonlyField({
  required String label,
  required String value,
  IconData? trailingIcon,
  VoidCallback? onTrailingIconTap,
  String? trailingTooltip,
})
```

Rendu : `LabeledField(label, child: Container(bg panel, border, radius radiusSm, padding 10/10, Row([Expanded(Text(value, fontMono 12px text)), if (trailingIcon != null) SmallIconButton(size: 24)])))`.

---

## 5. Layouts par cible

### 5.1 Help screen (β retoken)

```
Material(color: tokens.bg, child: Column[
  _HelpHeader(
    height: 72,
    padding: EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: tokens.panel,
      border: Border(bottom: BorderSide(color: tokens.border)),
    ),
    child: Row[
      Icon(FluentIcons.question_circle_24_regular, size: 28, color: tokens.accent),
      SizedBox(12),
      Text('Help', style: tokens.fontDisplay.copyWith(fontSize: 24, color: tokens.text, fontStyle: italic_if_atelier)),
      SizedBox(12),
      Text('documentation', style: tokens.fontMono.copyWith(fontSize: 11, color: tokens.textDim)),
    ],
  ),
  Expanded(child: sectionsAsync.when(
    data: (sections) => Row[
      HelpTocSidebar(retokenised — tokens.panel bg, item selected = accentBg + accent fg),
      VerticalDivider(width: 1, color: tokens.border),
      Expanded(child: HelpSectionContent(retokenised — tokens.fontBody body, tokens.fontDisplay headings, tokens.fontMono code)),
    ],
    loading: CircularProgressIndicator,
    error: (e, _) => Center(Column[Icon(error_circle, color: tokens.err), Text(e, fontBody color: tokens.err)]),
  )),
])
```

Pas de `DetailScreenToolbar` (Help est top-level, pas une page de détail). `FluentScaffold` retiré. Helper methods `_buildHeader`/`_buildError`/`_buildContent` refactorés.

### 5.2 Game Translation setup dialog (β retoken)

`AlertDialog` Material préservé (conserve mécanique modal, barrier, dismiss). Body retokenisé :

```
SizedBox(width: 680, height: 520, child: Column[
  _StepHeader(step: _currentStep + 1, totalSteps: 2, title, subtitle),
  SizedBox(16),
  Expanded(child: _currentStep == 0
    ? StepSelectSource(state, ...)            // retoken: TokenTextField, tokens partout
    : StepSelectTargets(state, ...)),          // idem
])

actions: [
  if (_currentStep > 0) SmallTextButton('Back', icon: arrow_left, onTap: _prevStep),
  Spacer(),
  SmallTextButton('Cancel', onTap: () => Navigator.pop(context)),
  SmallTextButton(
    _currentStep == 0 ? 'Next' : 'Create',
    icon: _currentStep == 0 ? arrow_right : play,
    onTap: _nextStep,
  ),
]
```

`_StepHeader` : `Column([Text('STEP ${n}/2', fontMono 10px textDim ls 1.2), Text(title, fontDisplay 18px text italic_if_atelier), if subtitle Text(subtitle, fontBody 12px textDim)])`.

`StepSelectSource` retokenisation :
- Progress indicator pendant scan : `CircularProgressIndicator(valueColor: tokens.accent)`.
- Pack list items : `Container(bg panel2 on hover, border highlighted if selected)`.
- Error state : Icon + Text en `tokens.err` + `tokens.errBg` container.
- Help text : `fontBody 12px textDim`.

`StepSelectTargets` retokenisation :
- Language tiles : grid de `Container(bg panel2, border, selected state: accentBg + accent border)`.
- Checkbox : `Checkbox(activeColor: tokens.accent)`.

`AddLanguageWizardDialog` (helper dialog appelé depuis StepSelectTargets) : retoken identique, `TokenTextField` pour search, listing en `ListRow`-style rows.

### 5.3 New Project dialog (β retoken)

Même pattern que Game Translation mais 3 steps :
- Step 1 : Basic info (name, game, source file, detected from mod if applicable).
- Step 2 : Languages (target language selection).
- Step 3 : Settings (batch size, parallel batches, custom prompt).

Footer actions incluent Back/Next/Create selon step. `_StepHeader` affiche "STEP N/3".

Step widgets retokenisés :
- `step_basic_info.dart` : `TokenTextField` pour name, `ReadonlyField` ou `LabeledField(Dropdown)` pour game/source.
- `step_languages.dart` : identique à `step_select_targets` du Game Translation.
- `step_settings.dart` : `TokenTextField(maxLength)` pour batch size, `Checkbox`, `LabeledField(Slider)` pour parallel batches.

### 5.4 5c follow-ups implementations

**P1 — remove 100ms race (`pack_compilation_editor_screen.dart`)** :

```dart
@override
Widget build(BuildContext context) {
  ref.listen<({Set<String> ids, String? langId})>(
    compilationEditorProvider.select((s) => (ids: s.selectedProjectIds, langId: s.selectedLanguageId)),
    (previous, next) {
      if (next.ids.length >= 2 && next.langId != null) {
        // schedule analyze — no delay needed, state is already settled
        ref.read(compilationConflictAnalysisProvider.notifier).analyze(
          projectIds: next.ids.toList(),
          languageId: next.langId!,
        );
      } else {
        ref.read(compilationConflictAnalysisProvider.notifier).clear();
      }
    },
  );
  // ... rest of build
}
```

Remove the 3 `Future.delayed(100ms)` calls in `onToggle`/`onSelectAll`/`onDeselectAll`.

**P2 — controller sync via ref.listen** :

```dart
@override
void initState() {
  super.initState();
  _nameCtl = TextEditingController();
  _packNameCtl = TextEditingController();
  _prefixCtl = TextEditingController();
  // setup listener after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // initial load (same as before)
    // ...
    // then: setup listener for external state mutations
    ref.listenManual(
      compilationEditorProvider,
      (previous, next) {
        if (previous?.name != next.name && _nameCtl.text != next.name) {
          _nameCtl.text = next.name;
        }
        if (previous?.prefix != next.prefix && _prefixCtl.text != next.prefix) {
          _prefixCtl.text = next.prefix;
        }
        if (previous?.packName != next.packName && _packNameCtl.text != next.packName) {
          _packNameCtl.text = next.packName;
        }
      },
    );
  });
}
```

Remove the in-build mutation block.

**P3 — narrow try/catch (`workshop_publish_screen.dart`)** :

```dart
Future<void> _loadTemplates() async {
  try {
    final settings = ref.read(settingsServiceProvider);
    final titleTemplate = await settings.getString('workshop_default_title');
    // ...
  } on ProviderException catch (e) {
    debugPrint('[WorkshopPublish] Settings unavailable: $e');
  } on StateError catch (e) {
    debugPrint('[WorkshopPublish] Settings state error: $e');
  }
}

@override
void dispose() {
  _elapsedTimer?.cancel();
  _titleController.dispose();
  _descriptionController.dispose();
  _changeNoteController.dispose();
  _outputScrollController.dispose();
  try {
    _publishNotifier.silentCleanup();
  } on StateError catch (e) {
    debugPrint('[WorkshopPublish] Cleanup state error: $e');
  }
  super.dispose();
}
```

**P4 — @visibleForTesting on notifiers** :

```dart
// In publish_staging_provider.dart
import 'package:flutter/foundation.dart';

@visibleForTesting
class SinglePublishStagingNotifier extends Notifier<PublishStagingData?> {
  // ...
}

@visibleForTesting
class BatchPublishStagingNotifier extends Notifier<BatchPublishStagingData?> {
  // ...
}
```

---

## 6. Tests

**Widget tests primitives** (~8, `test/widgets/wizard/`) :
- `token_text_field_test.dart` (3 tests) : renders with tokens.panel2 bg, focused border accent, onChanged fires.
- `labeled_field_test.dart` (3 tests) : label caps-mono, child renders, helpText show/hide.
- `readonly_field_test.dart` (2 tests) : label+value, trailingIcon tap fires.

**Widget tests dialogs + Help** (~10) :
- Game Translation : step nav, create button, cancel dismisses.
- New Project : step nav, create button, detected-mod auto-skip, cancel dismisses.
- Help : section selection updates content, error state renders, empty state.

**Goldens à régénérer** :
- Workshop Publish single × 2 — doivent rester byte-identiques (verify sans `--update-goldens`).
- Workshop Publish batch × 2 — doivent rester byte-identiques.
- Pack Compilation editor × 2 — drift possible (ref.listen timing). Regen si justifié.

**Nouveaux goldens** (2 thèmes × 3 écrans = 6) :
- Game Translation dialog step 1 populated.
- New Project dialog step 1 populated.
- Help screen with 3 sample sections.

**Cible tests** : 1318 → **~1340** (+22 bruts après adaptations des tests dialog existants).

---

## 7. Migration

### 7.1 Worktree

- Branche : `feat/ui-cleanup` depuis main.
- Worktree : `.worktrees/ui-cleanup/`.
- Setup : `cp -r ../../windows ./`, `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`.

### 7.2 Task order (séquentiel, 1 commit par task)

| Task | Contenu | Verification |
|---|---|---|
| 1 | Extract `TokenTextField` + `LabeledField` + `ReadonlyField` primitives + tests · migrate Workshop Publish single + batch imports | Workshop goldens byte-identiques |
| 2 | 5c P3 (narrow try/catch) + P4 (@visibleForTesting) on workshop publish + staging notifiers | `flutter analyze` clean, workshop tests verts |
| 3 | 5c P1 (remove 100ms race via ref.listen) + P2 (controller sync via ref.listen) on pack editor | Pack editor golden stable ou drift justifié (regen si propre) |
| 4 | Help screen + `help_section_content` + `help_toc_sidebar` retoken β · tests + 2 goldens | Tests verts + 2 goldens générés |
| 5 | Game Translation dialog + 3 step files + add_language_wizard_dialog retoken β · tests + 2 goldens | Tests verts + 2 goldens générés |
| 6 | New Project dialog + 3 step files retoken β · tests + 2 goldens | Tests verts + 2 goldens générés |
| 7 | `flutter analyze` complet, full test suite, fix any drift | `flutter test` vert à ~1340 |

### 7.3 Conventions

- Commits anglais, format `type: description`, NO AI mention.
- Tokens exclusivement via `context.tokens` — zero `Colors.xxxxxx`, zero `Theme.of().colorScheme.xxx`.
- `FluentScaffold` retiré du Help screen.

---

## 8. Risques

- **Workshop goldens drift** après extraction des primitives — pur rename privé→public, si drift c'est un bug. Investiguer avant regen.
- **Pack editor golden drift** après P1/P2 — `ref.listen` timing diffère de `Future.delayed(100ms)`. Golden peut drift d'1 frame. Regen OK si content pixel-identique, seulement timing change.
- **`ref.listen` double-registration** — Task 3 utilise `ref.listen` dans `build()` pour P1 et `ref.listenManual` dans `initState` pour P2. Attention à ne pas doubler les listeners. Riverpod auto-cleanup de `ref.listen` dans build ; `ref.listenManual` nécessite manual cleanup (pas nécessaire ici si scope de l'écran).
- **Dialog goldens sur AlertDialog** — capturer un AlertDialog en golden exige `tester.pumpWidget(...)` + `tester.tap(Button-that-opens-dialog)` + `tester.pumpAndSettle()`. Fixture un peu plus complexe qu'un screen direct.
- **`add_language_wizard_dialog`** — ce dialog est secondaire, invoqué depuis `step_select_targets`. Retokenisation requise mais pas de golden dédié (covered par les tests de StepSelectTargets).
- **`SettingsServiceProvider` accessibility dans `_loadTemplates`** — le `debugPrint` révèle les erreurs précédemment masquées. Attendre des warnings en mode debug lors de tests ; acceptable.
- **`FluentScaffold` sur Help** — removal peut légèrement changer le layout si `FluentScaffold` appliquait du padding/background. Regen les goldens Help après.

---

## 9. Follow-ups déférés

- **Plan 5e** : Settings retokenisation complète (~20 widget files). Scope dédié.
- **`StatusPillPalette`** — YAGNI, extract quand 3e consommateur.
- **`LogTerminal` token retokenization** — si besoin de thème clair un jour.
- **Goldens pour step 2+3 des dialogs** — ajoutés si besoin (step 1 couvre l'essentiel du chrome).

---

## 10. Open questions pour le plan d'implémentation

1. **Help header height** — 72px vs plus compact (48-56) ? Décision au plan. Reco : 72px pour matcher l'impact visuel de Home.
2. **`_StepHeader` widget** — private dans chaque dialog ou extraire une primitive `lib/widgets/wizard/step_header.dart` ? 2 consommateurs seulement, YAGNI probable.
3. **Dialog dimensions** — width 680 × height 520 fixes (actuels) ou proportionnels à la surface ? Reco : garder les actuels, les dialogs ont du sens en taille fixe.
4. **`@visibleForTesting` import** — vient de `package:flutter/foundation.dart` (déjà dispo) ou `package:meta/meta.dart` (équivalent). Décision au plan : `foundation.dart` pour éviter une dep supplémentaire.
