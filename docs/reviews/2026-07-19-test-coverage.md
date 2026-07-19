# Rapport de couverture des tests unitaires

- **Date** : 19 juillet 2026
- **Version** : v2.0.3 (commit `2e83982`)
- **Commande** : `flutter test --coverage` (suite complète, ~3 min)
- **Résultat de la suite** : 6 085 tests réussis, 4 ignorés, **6 échecs**
- **Source** : `coverage/lcov.info` (745 fichiers instrumentés)

> Note sur les 6 échecs : la suite a été lancée avec le reporter compact, les tests
> en échec n'ont pas été identifiés individuellement dans ce run. Un test
> token-encoder est connu pour échouer par intermittence en exécution parallèle
> (il passe en isolation) ; les échecs n'invalident pas les données de couverture.

## Synthèse

| Périmètre | Fichiers | Lignes couvertes | Lignes exécutables | Couverture |
|---|---:|---:|---:|---:|
| **Tout `lib/` instrumenté** | 745 | 43 670 | 53 673 | **81,4 %** |
| Hors code généré (`.g.dart`, `.freezed.dart`, `.mocks.dart`) | 646 | 40 120 | 48 946 | **82,0 %** |
| Code généré seul | 99 | 3 550 | 4 727 | 75,1 % |

**Attention** : `lcov.info` ne contient que les fichiers *chargés* par au moins un
test. **63 fichiers de `lib/` n'apparaissent pas du tout** (46 hors générés,
soit 8 468 lignes brutes ≈ 2 800 lignes exécutables estimées). En les comptant
à 0 %, la couverture réelle hors générés est estimée à **≈ 77,5 %**.

### Distribution des fichiers instrumentés (hors générés)

| Tranche | ≥ 90 % | 75–90 % | 50–75 % | < 50 % | 0 % |
|---|---:|---:|---:|---:|---:|
| Fichiers | 319 | 144 | 94 | 72 | 17 |

## Couverture par module (hors générés, du moins couvert au plus couvert)

| Module | Fichiers | Couvertes / exécutables | Couverture |
|---|---:|---:|---:|
| `lib/config` | 8 | 99 / 246 | **40,2 %** |
| `lib/models` | 45 | 1 264 / 2 141 | **59,0 %** |
| `lib/features/import_export` | 11 | 488 / 683 | 71,4 % |
| `lib/providers` | 33 | 1 415 / 1 900 | 74,5 % |
| `lib/theme` | 9 | 131 / 173 | 75,7 % |
| `lib/features/mods` | 7 | 740 / 953 | 77,6 % |
| `lib/features/settings` | 33 | 1 933 / 2 461 | 78,5 % |
| `lib/i18n` | 1 | 4 / 5 | 80,0 % |
| `lib/features/pack_compilation` | 16 | 1 432 / 1 790 | 80,0 % |
| `lib/features/bootstrap` | 3 | 222 / 275 | 80,7 % |
| `lib/features/home` | 10 | 263 / 325 | 80,9 % |
| `lib/services` | 240 | 13 929 / 17 088 | 81,5 % |
| `lib/features/projects` | 24 | 1 973 / 2 372 | 83,2 % |
| `lib/features/translation_editor` | 48 | 3 602 / 4 318 | 83,4 % |
| `lib/features/steam_publish` | 20 | 2 333 / 2 791 | 83,6 % |
| `lib/widgets` | 70 | 3 574 / 4 232 | 84,5 % |
| `lib/features/game_translation` | 8 | 705 / 820 | 86,0 % |
| `lib/features/glossary` | 11 | 1 153 / 1 320 | 87,3 % |
| `lib/features/search` | 2 | 129 / 146 | 88,4 % |
| `lib/features/activity` | 2 | 36 / 40 | 90,0 % |
| `lib/features/translation_memory` | 10 | 1 353 / 1 410 | 96,0 % |
| `lib/repositories` | 29 | 3 153 / 3 266 | 96,5 % |
| `lib/utils` | 5 | 167 / 169 | 98,8 % |
| `lib/features/release_notes` | 1 | 22 / 22 | 100,0 % |

Points forts : les couches données (`repositories` 96,5 %, `translation_memory`
96 %) et `utils` sont très bien couvertes. Points faibles : `config` (routeur,
transitions), `models` (beaucoup de classes de données peu exercées) et
`import_export`.

## Top 20 des fichiers avec le plus de lignes non couvertes

| Lignes manquantes | Couverture | Fichier |
|---:|---:|---|
| 179 | 47,7 % | `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` |
| 153 | 71,6 % | `lib/features/steam_publish/screens/workshop_publish_screen.dart` |
| 134 | 71,1 % | `lib/features/projects/screens/projects_screen.dart` |
| 133 | 24,4 % | `lib/services/rpfm/rpfm_cli_manager.dart` |
| 112 | 23,8 % | `lib/services/database/database_service.dart` |
| 99 | 14,7 % | `lib/config/router/app_router.dart` |
| 95 | 50,0 % | `lib/features/steam_publish/screens/steam_publish_screen.dart` |
| 88 | 63,6 % | `lib/features/translation_editor/screens/export_progress_screen.dart` |
| 87 | 59,3 % | `lib/features/translation_editor/screens/translation_editor_screen.dart` |
| 80 | 44,1 % | `lib/features/mods/utils/mods_screen_controller.dart` |
| 78 | 71,5 % | `lib/features/projects/widgets/create_project/create_project_dialog.dart` |
| 74 | 14,0 % | `lib/providers/shared/service_providers.dart` |
| 72 | 12,2 % | `lib/services/service_locator.dart` |
| 66 | 50,4 % | `lib/features/translation_editor/screens/translation_progress_screen.dart` |
| 65 | 50,4 % | `lib/features/translation_editor/screens/actions/editor_actions_translation.dart` |
| 65 | 40,9 % | `lib/services/steam/steamcmd_manager.dart` |
| 62 | 71,4 % | `lib/providers/projects_data_providers.dart` |
| 60 | 79,9 % | `lib/services/backup/database_backup_service.dart` |
| 60 | 62,0 % | `lib/services/steam/steam_detection_service.dart` |
| 60 | 57,1 % | `lib/features/translation_editor/widgets/grid_actions_handler.dart` |

## Fichiers instrumentés à 0 % (17)

Principalement la famille de widgets `lib/widgets/fluent/fluent_*.dart`
(checkbox, boutons, text field, toggle — ~310 lignes cumulées), plus :
`lib/config/router/route_transitions.dart`,
`lib/features/mods/utils/mods_dialog_helper.dart`,
`lib/features/settings/widgets/folders_settings_tab.dart`,
`lib/features/settings/widgets/general_settings_tab.dart`,
`lib/features/settings/widgets/general/language_preferences_section.dart`,
`lib/features/translation_editor/screens/actions/editor_actions_import.dart`,
`lib/features/translation_editor/screens/actions/editor_actions_undo_redo.dart`,
`lib/services/toast_notification_service.dart`.

## Fichiers jamais chargés par un test (absents du lcov)

46 fichiers hors générés (8 468 lignes brutes), invisibles dans le taux global.
Dont 9 interfaces `i_*.dart` (peu de code exécutable) — mais aussi du vrai code :

| Lignes brutes | Fichier |
|---:|---|
| 573 | `lib/features/translation/widgets/history_timeline_panel.dart` |
| 483 | `lib/features/translation_editor/widgets/editor_validation_panel.dart` |
| 457 | `lib/features/translation/widgets/version_comparison_dialog.dart` |
| 453 | `lib/services/database/example_repository.dart` |
| 416 | `lib/utils/validators.dart` |
| 414 | `lib/main.dart` |
| 391 | `lib/utils/retry_utils.dart` |
| 350 | `lib/services/shared/cache_service.dart` |
| 338 | `lib/services/monitoring/performance_monitor.dart` |
| 336 | `lib/features/mods/widgets/mod_update_dialog.dart` |
| 259 | `lib/features/search/widgets/search_result_card.dart` |
| 253 | `lib/services/text/french_hyphen_fixer.dart` |
| 249 | `lib/features/mods/widgets/whats_new_dialog.dart` |
| 225 | `lib/services/common/clipboard_service.dart` |

(+ 32 autres fichiers plus petits ; `lib/main.dart` est attendu — non testable
unitairement. Plusieurs de ces fichiers semblent être du code mort potentiel :
`example_repository.dart`, les widgets de l'ancienne feature `translation/`.)

## Méthodologie et limites

- Couverture **par ligne** (LH/LF du lcov Flutter) ; pas de couverture de
  branches.
- Un fichier jamais importé par un test n'apparaît pas dans `lcov.info` — le
  taux « brut » surestime donc la couverture. L'estimation ajustée (≈ 77,5 %)
  applique le ratio moyen lignes exécutables/lignes brutes du dépôt (33,5 %)
  aux 46 fichiers manquants.
- Le code généré (`build_runner`) est inclus dans le taux global mais exclu des
  analyses détaillées.

## Recommandations

1. **Trier le code mort** : `example_repository.dart`, les widgets de
   `lib/features/translation/` (feature remplacée par `translation_editor` ?)
   et `fluent_widgets.dart` — les supprimer vaut mieux que les tester.
2. **Couvrir les utilitaires purs jamais chargés** : `validators.dart`,
   `retry_utils.dart`, `cache_service.dart`, `french_hyphen_fixer.dart` sont du
   Dart pur, faciles à tester et à fort levier (~1 400 lignes brutes).
3. **`lib/config/router`** (40 %) : `app_router.dart` et `route_transitions.dart`
   se testent bien avec des widget tests de navigation.
4. **`lib/models`** (59 %) : cibler les modèles à logique (sérialisation,
   validation) plutôt que les simples data classes.
5. **Identifier les 6 tests en échec** (run avec `--reporter expanded` ou
   `--file-reporter json:...`) pour distinguer le flaky connu des vraies
   régressions.

---

# Addendum — Recommandations appliquées (19 juillet 2026)

Toutes les recommandations ont été appliquées le jour même. Résultat :

| Indicateur | Avant | Après |
|---|---:|---:|
| Couverture globale (instrumentée) | 81,4 % | **83,2 %** |
| Couverture hors code généré | 82,0 % | **84,0 %** |
| Suite de tests | 6 085 ✅ / 6 échecs | **6 483 ✅ / 0 échec** |
| Fichiers `lib/` jamais chargés (hors générés) | 46 | **18** |
| Fichiers instrumentés à 0 % (hors générés) | 17 | 11 |
| Fichiers < 50 % (hors générés) | 72 | 56 |

## Rec 1 + 2 — Code mort : 34 fichiers supprimés (~7 200 lignes)

La vérification d'usage (imports `lib/` + `test/`, noms de classes, barrels) a
révélé que **les 4 « utilitaires purs » de la recommandation 2 étaient en
réalité du code mort** (0 importeur) — ils ont donc été supprimés, pas testés.
Fichiers supprimés (+ 4 `.g.dart` non suivis par git) :

- **Services** : `example_repository.dart`, `metadata_migration_service.dart`,
  `cache_service.dart`, `performance_monitor.dart` (+ dossier `monitoring/`),
  `clipboard_service.dart` (+ `common/`), `french_hyphen_fixer.dart` (+ `text/`)
- **Utils** : `validators.dart`, `retry_utils.dart`
- **Features** : `lib/features/translation/` en entier (2 widgets),
  `editor_validation_panel.dart`, `whats_new_dialog.dart`,
  `mod_update_dialog.dart`, `search_result_card.dart`, `fluent_buttons.dart`,
  `search_pagination_controls.dart`, `glossary_screen_components.dart`,
  `glossary_toolbar.dart`, 4 widgets `settings/widgets/llm/` (model_card,
  dialog_header, empty_state, legend), `project_with_next_action.dart`
- **Modèles/Providers** : `pagination.dart`, `mod_version_change.dart`,
  `language_manual.dart`, `active_batches_provider.dart` (+ leurs `.g.dart`)
- **Widgets/Theme** : `fluent_colors.dart`, `fluent_checkbox.dart`,
  `fluent_dialog_button.dart`, `fluent_text_button.dart`,
  `fluent_text_field.dart`, `fluent_toggle_switch.dart` (exports retirés du
  barrel `fluent_widgets.dart` ; `FluentIconButton` et `FluentOutlinedButton`
  sont utilisés et conservés)

`flutter analyze` propre après suppression. Les 18 fichiers restants jamais
chargés sont légitimes : `main.dart`, 9 interfaces `i_*.dart`, le barrel
`fluent_widgets.dart`, et quelques fichiers vivants mais atteints uniquement
via des chemins non testés (`data_migration_dialog/provider`,
`history_providers.dart`, `settings_keys.dart`, `activity_*`,
`validation_schema.dart`).

## Rec 3 — Routeur : 40,2 % → 94,3 % (`lib/config`)

Les 4 fichiers de `lib/config/router/` sont à **100 %** :
`app_router.dart` 116/116 (redirects, table des 15 routes, pageBuilders,
errorBuilder, extensions `goX()`), `route_transitions.dart` 22/22,
`navigation_state_provider.dart` 38/38 (+ `.g.dart` 15/15).
Fichiers : `test/config/router/route_transitions_test.dart` (nouveau, 10 tests),
`app_router_test.dart` (30 → 53 tests), `navigation_state_provider_test.dart`
(5 → 11 tests).

## Rec 4 — Modèles : 59,0 % → 89,5 %

15 nouveaux fichiers de tests (354 tests) sous `test/models/{domain,events}/` ;
les 15 modèles ciblés (les pires du rapport) sont tous à **100 %** :
tm_events, translation_batch_unit, project, compilation, mod_version,
translation_memory_entry, project_events, project_language, translation_events,
setting, translation_unit, llm_provider_model, game_installation,
translation_provider, translation_version.

## Rec 5 — Tests en échec : identifiés et corrigés

- **4 échecs reproductibles en isolation** dans
  `test/features/steam_publish/providers/published_subs_cache_provider_test.dart` :
  tests obsolètes après le commit `2bd7976` (lecture des Workshop IDs depuis
  `project_publication` au lieu de `projects.published_steam_id`). Le container
  de test n'overridait pas `projectPublicationRepositoryProvider` →
  `ServiceLocator` non initialisé → ProviderException. **Corrigé** (mock du
  repository, seed via `ProjectPublication`) ; la prod était correcte.
- Les ~2 autres échecs du run initial n'ont pas été reproduits (flaky connu
  token-encoder en parallélisme).

## Anomalies remontées (non corrigées, à trancher)

1. **Tous les `toJson()` des events** (`tm_events.dart`, `project_events.dart`,
   `translation_events.dart`) sont des stubs `throw UnimplementedError` — tout
   chemin qui sérialiserait un event plantera. Les tests actuels épinglent ce
   comportement.
2. `Project._boolFromInt` renvoie `false` pour toute chaîne (`'1'` → false)
   alors que le `BoolIntConverter` partagé parse `'1'`/`'true'` → true.
   Pas de bug vivant (SQLite stocke des ints), mais incohérent.
3. Seuils divergents : `TmSuggestion.isFrequentlyUsed` = `usageCount >= 5`
   vs `TranslationMemoryEntry.isFrequentlyUsed` = `usageCount > 5`.

---

# Addendum 2 — Anomalies traitées (19 juillet 2026)

Enquête sur les 3 anomalies : **aucune n'était un bug vivant**. Toutes
remontaient à une même racine — un sous-système d'events (persistance + stats
temps réel) échafaudé mais **jamais branché**. Preuves collectées dans le code :

- `EventBus.persistEvents` vaut `false` par défaut et n'est jamais passé à `true`
  en prod (seulement dans les tests).
- La table `event_store` n'est **créée par aucune migration** — la persistance
  n'a donc jamais eu de destination réelle ; seuls les auto-tests la créaient à
  la main.
- Les classes d'events `tm_events` / `project_events` / `translation_events`
  ne sont **jamais publiées** (seul `TranslationAddedEvent` apparaît, dans un
  commentaire). Ce qui circule réellement : les `Batch*Event`, avec un `toJson()`
  réel.
- Leurs stream providers ont **0 consommateur** (sauf `translationAddedEvents`,
  lu par `TranslationStatistics` — lui-même watché par **aucune UI**, et
  écoutant un event qui ne se déclenche jamais).
- `TmSuggestion` (anomalie 3) : **0 usage** ; le provider de suggestions vivant
  utilise `TmMatch`, un autre type.

## Décision appliquée : élagage (Option A) + convertisseur partagé (anomalie 2)

**Supprimé (code mort, ~1 150 lignes nettes) :**
- `lib/models/events/{tm_events,project_events,translation_events}.dart`
- `lib/providers/statistics/translation_statistics_provider.dart` (+ `.g.dart`)
- `lib/services/shared/models/event_record.dart` (`EventRecord`,
  `EventStatistics`) (+ `.g.dart`)
- 5 fichiers de tests associés (dont les 3 tests d'events écrits en Addendum 1,
  qui épinglaient le comportement de code désormais supprimé)

**Allégé :**
- `lib/services/shared/event_bus.dart` : **493 → 80 lignes**. Retrait de toute
  la persistance morte (`persistEvents`, `_persistEvent`, `getEventHistory`,
  `replayEvents`, `getStatistics`, `purgeOldEvents`, `searchEvents`, buffer de
  replay). Conservé : le pub/sub vivant (`on<T>`, `publish`, `publishSync`,
  `events`, `dispose`). Couverture : **14/14 (100 %)**.
- `lib/providers/events/event_stream_providers.dart` : 18 → 10 providers (les
  streams `Batch*` vivants, seuls consommés).

**Anomalie 2 corrigée :** `Project.hasModUpdateImpact` utilise désormais le
`@BoolIntConverter()` partagé au lieu des helpers one-off `_boolFromInt` /
`_boolToInt` (qui divergeaient du convertisseur partagé sur le parsing des
chaînes). Comportement identique en prod (SQLite renvoie des entiers).

**Anomalies 1 et 3 résolues par suppression** (les stubs `toJson` qui
levaient `UnimplementedError` et les getters `isFrequentlyUsed` divergents
faisaient partie du code mort retiré).

## Vérification

- `flutter analyze` : propre.
- Suite complète : **6 353 tests, 0 échec** (un `-1` transitoire d'un run
  antérieur était le flaky token-encoder connu, non reproduit en ré-exécution).
- Couverture : **83,2 % global / 84,0 % hors générés** (stable — le code mort
  supprimé était surtout couvert à 100 % *et* retiré du dénominateur). `models`
  passe de 89,5 % à 88,6 % (retrait des 3 fichiers d'events à 100 %).
