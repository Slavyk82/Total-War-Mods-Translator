# Plan — Remonter la couverture des zones rouges

> Date : 2026-06-12 · Couverture globale de départ : **39,6 %** (21 577 / 54 472)

## Cible

Trois zones sous les 25 % concentrent **603 / 3 366 lignes couvertes (17,9 %)** :

| Zone | Départ | Cible | Lignes à gagner |
|------|--------|-------|-----------------|
| `features/release_notes` | 0 % (0/22) | ~90 % | +20 |
| `features/game_translation` | 11 % (90/820) | ~55 % | +360 |
| `features/settings` | 20 % (513/2524) | ~55 % | +880 |

Atteindre ces cibles ⇒ **~+1 260 lignes** ⇒ couverture globale **~42 %**.

## Conventions à réutiliser (déjà en place)

- **Mocks** : `mocktail` (`class _MockX extends Mock implements X {}`).
- **Providers** : `ProviderContainer(overrides: [xProvider.overrideWithValue(mock)])` + `addTearDown(container.dispose)`. Modèle de référence : `test/features/settings/providers/maintenance_providers_test.dart`.
- **Fakes partagés** : `test/helpers/fakes/` (`FakeLogger`, etc.) — réutiliser, ne pas re-mocker le logger.
- **Widgets** : `pumpWidget` avec `ProviderScope(overrides: …)` ; voir `test/features/settings/widgets/llm_provider_section_test.dart`.
- **DataGrid** : Syncfusion obligatoire (CLAUDE.md). Tester d'abord la `*DataSource` (logique pure) séparément du widget grille.
- Un fichier de test par fichier source, arbo miroir sous `test/`.
- Vérif finale : `flutter test` puis `flutter test --coverage` (les 2147 tests doivent rester verts).

---

## Phase 1 — Logique pure & providers (ROI maximal, ~haute confiance)

Pas de `pumpWidget`, juste mocktail + `ProviderContainer`. Cibles les plus rentables.

| # | Fichier source | Lignes | Approche |
|---|----------------|--------|----------|
| 1.1 | `release_notes/services/release_notes_service.dart` | 0/22 | Service pur. Mock `SettingsService` + `AppUpdateService`. 4 cas : même version → null ; premier run (vide) → stocke + null ; nouvelle version match → release ; mismatch → markSeen + null. |
| 1.2 | `game_translation/providers/game_translation_providers.dart` | 3/51 | `ProviderContainer` + overrides des repos/services lus. Tester chargement, états d'erreur, refresh. |
| 1.3 | `settings/providers/ignored_source_texts_providers.dart` (+ `.g.dart` 6/33) | 0/51 | `ProviderContainer`, mock du repo. CRUD + invalidation. |
| 1.4 | `game_translation/.../game_translation_creation_state.dart` | 0/12 | Classe d'état : copyWith / égalité / valeurs initiales. |
| 1.5 | `game_translation/.../source_language_resolver.dart` | 2/7 | **Étendre** le test existant : couvrir `resolve()` (pack null, match, no-match) et alias de codes. |

**Gain estimé : ~110 lignes.** Faible risque, sert d'échauffement.

## Phase 2 — DataSources & sections sans dialog (medium)

Les `*DataSource` Syncfusion sont de la logique de mapping testable hors UI lourde.

| # | Fichier source | Lignes | Approche |
|---|----------------|--------|----------|
| 2.1 | `settings/widgets/language_settings_data_source.dart` | 0/89 | Construire avec données factices ; vérifier rows/cellules, callbacks d'édition. Modèle : `llm_custom_rules_data_source_test.dart` (déjà à 68 %). |
| 2.2 | `settings/widgets/ignored_source_texts_data_source.dart` | 0/75 | idem. |
| 2.3 | `settings/widgets/general/rpfm_section.dart` | 9/136 | `pumpWidget` + `ProviderScope`. Un test existe (`rpfm_section_default_schema_path_test.dart`) → l'étendre aux chemins/erreurs. |
| 2.4 | `settings/widgets/general/app_language_section.dart` | 1/39 | pumpWidget : rendu + sélection langue → set provider. |
| 2.5 | `settings/widgets/general/backup_section.dart` | 0/149 | pumpWidget, mock backup providers (existants à 85 %). Boutons backup/restore. |
| 2.6 | `settings/widgets/general/workshop_section.dart` · `pack_prefix_section.dart` · `game_installations_section.dart` · `language_preferences_section.dart` | 0/274 | pumpWidget par section, vérifier rendu + interaction principale. |
| 2.7 | `settings/widgets/ignored_source_texts_section.dart` · `llm_custom_rules_section.dart` · `llm/llm_model_row.dart` | ~2/261 | pumpWidget, états liste vide / peuplée. |

**Gain estimé : ~600 lignes.**

## Phase 3 — Dialogs & DataGrids (plus coûteux)

Tests `pumpWidget` complets (ouverture, saisie, validation, confirmation/annulation).

| # | Fichier source | Lignes | Approche |
|---|----------------|--------|----------|
| 3.1 | `game_translation/.../create_game_translation_dialog.dart` | 1/236 | Wizard multi-étapes : pump le dialog, parcourir les steps, valider le submit. Le plus gros gain unitaire. |
| 3.2 | `game_translation/.../step_select_source.dart` · `step_select_targets.dart` · `add_language_wizard_dialog.dart` | 2/399 | Tester chaque step isolément avec un state injecté. |
| 3.3 | `settings/widgets/*_datagrid.dart` (llm_custom_rules, ignored_source_texts, language_settings) | 0/324 | pumpWidget grille + DataSource déjà testée en Phase 2 ; vérifier rendu colonnes + édition. |
| 3.4 | Dialogs settings : `add_custom_language_dialog` · `ignored_source_text_editor_dialog` · `llm_custom_rule_editor_dialog` · `dialogs/backup_restore_confirmation_dialog` | 3/356 | Ouverture, validation de formulaire, retour valeur / annulation. |

**Gain estimé : ~550 lignes.** À faire en dernier (effort le plus élevé par ligne).

---

## Ordre d'exécution recommandé

1. **Phase 1 d'abord** (rapide, verrouille les patterns providers/services).
2. **Phase 2** (le gros du volume `settings`, risque modéré).
3. **Phase 3** seulement si la cible 55 % n'est pas atteinte — sinon s'arrêter, le ROI chute.

Après chaque phase : relancer `flutter test --coverage` et recalculer le delta avant d'enchaîner (un commit par phase).

## Note hors périmètre

Le plus gros levier **global** n'est pas une zone rouge mais `lib/services` (34,6 %, 18 676 lignes — un tiers du code, et *pure Dart* donc facile à tester unitairement). À considérer dans un plan séparé une fois les zones rouges traitées.
