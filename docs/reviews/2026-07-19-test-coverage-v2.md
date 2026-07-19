# Rapport de couverture des tests unitaires — v2 (état post-nettoyage)

- **Date** : 19 juillet 2026
- **Base** : commit `4a6f82b` (après élagage du code mort + tests routeur/modèles)
- **Commande** : `flutter test --coverage` (suite complète)
- **Suite** : 6 353 tests réussis, 4 ignorés, **0 échec réel**
  (un run parallèle a montré 2 échecs transitoires — le flaky token-encoder
  connu ; le run de référence en reporter JSON sur le même commit était à 0 échec)
- **Source** : `coverage/lcov.info` (733 fichiers instrumentés)

> Snapshot autonome mesuré à neuf. Le journal du travail (suppressions,
> ajouts de tests, refactor events) est dans `2026-07-19-test-coverage.md`.

## Synthèse

| Périmètre | Fichiers | Lignes couvertes | Lignes exécutables | Couverture |
|---|---:|---:|---:|---:|
| **Tout `lib/` instrumenté** | 733 | 44 001 | 52 907 | **83,2 %** |
| Hors code généré (`.g.dart`, `.freezed.dart`, `.mocks.dart`) | 636 | 40 596 | 48 338 | **84,0 %** |
| Code généré seul | 97 | 3 405 | 4 569 | 74,5 % |

Évolution depuis la mesure initiale (avant nettoyage) : **81,4 % → 83,2 %**
global, **82,0 % → 84,0 %** hors générés.

Fichiers de `lib/` jamais chargés par un test : **18 hors générés** (contre 46
initialement), dont 9 interfaces `i_*.dart` (peu de code exécutable) et
`main.dart` (non testable unitairement). La couverture réelle ajustée reste
proche du taux instrumenté vu que le résidu non chargé est surtout des
interfaces.

### Distribution des fichiers instrumentés (hors générés)

| Tranche | ≥ 90 % | 75–90 % | 50–75 % | < 50 % | 0 % |
|---|---:|---:|---:|---:|---:|
| Fichiers | 335 | 143 | 92 | 55 | 11 |

## Couverture par module (hors générés, du moins couvert au plus couvert)

| Module | Fichiers | Couvertes / exécutables | Couverture |
|---|---:|---:|---:|
| `lib/import_export` (features) | 11 | 488 / 683 | **71,4 %** |
| `lib/theme` | 9 | 131 / 173 | 75,7 % |
| `lib/providers` | 32 | 1 412 / 1 837 | 76,9 % |
| `lib/features/mods` | 7 | 741 / 953 | 77,8 % |
| `lib/features/settings` | 33 | 1 933 / 2 461 | 78,5 % |
| `lib/i18n` | 1 | 4 / 5 | 80,0 % |
| `lib/features/pack_compilation` | 16 | 1 432 / 1 790 | 80,0 % |
| `lib/features/bootstrap` | 3 | 222 / 275 | 80,7 % |
| `lib/features/home` | 10 | 263 / 325 | 80,9 % |
| `lib/services` | 239 | 13 781 / 16 934 | 81,4 % |
| `lib/features/projects` | 24 | 1 974 / 2 372 | 83,2 % |
| `lib/features/translation_editor` | 48 | 3 603 / 4 318 | 83,4 % |
| `lib/features/steam_publish` | 20 | 2 333 / 2 791 | 83,6 % |
| `lib/features/game_translation` | 8 | 705 / 820 | 86,0 % |
| `lib/features/glossary` | 11 | 1 153 / 1 320 | 87,3 % |
| `lib/features/search` | 2 | 129 / 146 | 88,4 % |
| `lib/models` | 42 | 1 755 / 1 980 | 88,6 % |
| `lib/widgets` | 65 | 3 574 / 4 002 | 89,3 % |
| `lib/features/activity` | 2 | 36 / 40 | 90,0 % |
| `lib/config` | 8 | 232 / 246 | 94,3 % |
| `lib/features/translation_memory` | 10 | 1 353 / 1 410 | 96,0 % |
| `lib/repositories` | 29 | 3 153 / 3 266 | 96,5 % |
| `lib/utils` | 5 | 167 / 169 | 98,8 % |
| `lib/features/release_notes` | 1 | 22 / 22 | 100,0 % |

Progrès notables depuis l'initial : `config` 40 % → **94,3 %** (tests routeur),
`models` 59 % → **88,6 %** (tests de modèles + retrait des events morts). Points
faibles restants : `import_export` (71 %), `theme` (76 %), `providers` (77 %).

## Top 15 des fichiers avec le plus de lignes non couvertes

| Lignes manquantes | Couverture | Fichier |
|---:|---:|---|
| 179 | 47,7 % | `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart` |
| 153 | 71,6 % | `lib/features/steam_publish/screens/workshop_publish_screen.dart` |
| 133 | 71,3 % | `lib/features/projects/screens/projects_screen.dart` |
| 133 | 24,4 % | `lib/services/rpfm/rpfm_cli_manager.dart` |
| 112 | 23,8 % | `lib/services/database/database_service.dart` |
| 95 | 50,0 % | `lib/features/steam_publish/screens/steam_publish_screen.dart` |
| 88 | 63,6 % | `lib/features/translation_editor/screens/export_progress_screen.dart` |
| 86 | 59,8 % | `lib/features/translation_editor/screens/translation_editor_screen.dart` |
| 80 | 44,1 % | `lib/features/mods/utils/mods_screen_controller.dart` |
| 78 | 71,5 % | `lib/features/projects/widgets/create_project/create_project_dialog.dart` |
| 74 | 14,0 % | `lib/providers/shared/service_providers.dart` |
| 72 | 12,2 % | `lib/services/service_locator.dart` |
| 66 | 50,4 % | `lib/features/translation_editor/screens/translation_progress_screen.dart` |
| 65 | 50,4 % | `lib/features/translation_editor/screens/actions/editor_actions_translation.dart` |
| 65 | 40,9 % | `lib/services/steam/steamcmd_manager.dart` |

Ce sont surtout des écrans (widgets d'UI riches) et des points de câblage DI
(`service_providers`, `service_locator`) — coûteux à tester unitairement, à
couvrir plutôt par des tests d'intégration ciblés.

## Fichiers instrumentés à 0 % (11)

| Lignes | Fichier |
|---:|---|
| 48 | `lib/features/settings/widgets/folders_settings_tab.dart` |
| 46 | `lib/widgets/fluent/fluent_outlined_button.dart` |
| 43 | `lib/features/mods/utils/mods_dialog_helper.dart` |
| 35 | `lib/widgets/fluent/fluent_icon_button.dart` |
| 23 | `lib/features/settings/widgets/general/language_preferences_section.dart` |
| 20 | `lib/features/settings/widgets/general_settings_tab.dart` |
| 18 | `lib/services/toast_notification_service.dart` |
| 14 | `lib/features/translation_editor/screens/actions/editor_actions_undo_redo.dart` |
| 14 | `lib/features/translation_editor/screens/actions/editor_actions_import.dart` |
| 7 | `lib/features/settings/widgets/llm/llm_provider_header.dart` |
| 1 | `lib/config/app_constants.dart` |

`fluent_outlined_button` / `fluent_icon_button` sont utilisés (2 et 6 fichiers)
mais non exercés directement — candidats à des widget tests simples.

## Fichiers jamais chargés par un test (18, hors générés)

| Lignes brutes | Fichier | Note |
|---:|---|---|
| 414 | `lib/main.dart` | point d'entrée, non testable unitairement |
| 336 | `lib/services/glossary/i_glossary_service.dart` | interface |
| 193 | `lib/widgets/dialogs/data_migration_dialog.dart` | UI de migration |
| 163 | `lib/providers/data_migration_provider.dart` | provider de migration |
| 139 | `lib/services/search/i_search_service.dart` | interface |
| 119 | `lib/services/history/i_history_service.dart` | interface |
| 79 | `lib/providers/history/history_providers.dart` | |
| 78 | `lib/widgets/fluent/fluent_widgets.dart` | barrel (ré-exports) |
| 70 | `lib/services/steam/i_workshop_api_service.dart` | interface |
| 61 | `lib/services/steam/i_steamcmd_service.dart` | interface |
| 57 | `lib/config/settings_keys.dart` | constantes |
| 54 | `lib/services/steam/i_workshop_publish_service.dart` | interface |
| 35 | `lib/services/file/i_pack_image_generator_service.dart` | interface |
| 32 | `lib/services/validation/i_translation_validation_service.dart` | interface |
| 25 | `lib/services/shared/i_logging_service.dart` | interface |
| 23 | `lib/features/activity/repositories/activity_event_repository.dart` | interface repo |
| 19 | `lib/features/activity/services/activity_logger.dart` | interface |
| 17 | `lib/services/validation/validation_schema.dart` | schéma |

Neuf sont des interfaces `i_*.dart` (contrats sans logique exécutable). Le
résidu réellement testable et non couvert est faible : le flux de migration de
données (`data_migration_dialog` + `data_migration_provider`) et
`history_providers` sont les cibles les plus utiles.

## Méthodologie et limites

- Couverture **par ligne** (LH/LF du lcov Flutter) ; pas de couverture de
  branches.
- Un fichier jamais importé par un test n'apparaît pas dans `lcov.info` ; le
  taux instrumenté surestime donc légèrement, mais le résidu (18 fichiers,
  surtout interfaces) rend l'écart faible.
- Le code généré est inclus dans le taux global mais exclu des analyses
  détaillées.

## Recommandations restantes

1. **`import_export` (71 %)** : module le moins couvert ; cibler la logique de
   parsing/résolution de conflits (hors UI).
2. **Flux de migration de données** jamais exercé (`data_migration_dialog` +
   `data_migration_provider`) — chemin sensible, à couvrir.
3. **Widgets fluent à 0 %** (`fluent_outlined_button`, `fluent_icon_button`) :
   widget tests simples et à fort ratio couverture/effort.
4. Les gros écrans peu couverts (pack_compilation, workshop_publish, projects)
   relèvent de tests d'intégration plutôt que de tests unitaires.

---

# Addendum — Renforcement des points faibles (19 juillet 2026)

Les recommandations 1 à 3 ont été appliquées : **239 tests ajoutés sur 20
fichiers** (import_export models/services, providers logiques, tokens de thème,
widgets fluent à 0 %, flux de migration). Suite complète : **6 592 tests,
0 échec** ; `flutter analyze` propre. Aucun fichier `lib/` modifié.

### Global

| Périmètre | Avant | Après |
|---|---:|---:|
| Instrumenté | 83,2 % | **84,6 %** |
| Hors code généré | 84,0 % | **85,0 %** |
| Fichiers < 50 % (hors générés) | 55 | 48 |
| Fichiers à 0 % (hors générés) | 11 | 9 |
| Fichiers jamais chargés (hors générés) | 18 | 16 |

### Modules ciblés

| Module | Avant | Après |
|---|---:|---:|
| `lib/features/import_export` | 71,4 % | **96,8 %** |
| `lib/theme` | 75,7 % | **99,4 %** |
| `lib/providers` | 76,9 % | **85,9 %** |
| `lib/widgets` | 89,3 % | **91,5 %** |

### Fichiers ciblés (couverture après)

| Fichier | Avant | Après |
|---|---:|---:|
| `import_export/models/import_preview.dart` | 4,8 % | **100 %** |
| `import_export/models/export_result.dart` | 4,8 % | **100 %** |
| `import_export/models/import_result.dart` | 5,9 % | **100 %** |
| `import_export/models/import_export_settings.dart` | 62,1 % | **100 %** |
| `import_export/models/import_conflict.dart` | 66,7 % | **100 %** |
| `import_export/services/import_file_reader.dart` | 75,0 % | **100 %** |
| `import_export/services/import_conflict_detector.dart` | 67,2 % | 95,5 % |
| `import_export/services/import_executor.dart` | 85,6 % | 90,4 % |
| `providers/translation/batch_state_provider.dart` | 31,0 % | **100 %** |
| `providers/release_notes_providers.dart` | 3,8 % | **100 %** |
| `providers/import_export/export_provider.dart` | 59,7 % | 97,4 % |
| `providers/import_export/import_provider.dart` | 48,2 % | 92,7 % |
| `theme/twmt_theme_tokens.dart` | 64,7 % | **100 %** |
| `widgets/fluent/fluent_outlined_button.dart` | 0 % | 97,8 % |
| `widgets/fluent/fluent_icon_button.dart` | 0 % | 97,1 % |
| `providers/data_migration_provider.dart` | 0 % (jamais chargé) | **100 %** |
| `widgets/dialogs/data_migration_dialog.dart` | 0 % (jamais chargé) | **100 %** |

### Observations remontées (non corrigées)

1. `DataMigrationState.copyWith` utilise `error: error` (pas `error ?? this.error`)
   — tout `copyWith` qui omet `error` l'efface. Inoffensif aujourd'hui (seul le
   bloc catch porte une erreur, et l'effacer au retry est voulu), mais fragile si
   le champ `error` est lu à d'autres endroits plus tard. Épinglé par un test.
2. Testabilité : `import_provider` / `export_provider` instancient
   `ImportExportService` en interne au lieu de l'injecter via un provider, ce qui
   force à mocker 5 dépendances de bas niveau plutôt qu'un seul service. Un
   `importExportServiceProvider` simplifierait ces tests.
