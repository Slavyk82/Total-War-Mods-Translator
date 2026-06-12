# Plan — Remonter la couverture de `lib/services`

> Date : 2026-06-12 · Suite des zones rouges (voir
> [2026-06-12-red-zone-coverage.md](2026-06-12-red-zone-coverage.md)).
> Couverture globale de départ : **42,3 %** (23 055 / 54 472).

## Pourquoi `lib/services`

C'est le **plus gros levier global** : **18 676 lignes** (un tiers du code) à
seulement **34,6 %** (6 455 couvertes), réparties sur 265 fichiers. La règle
d'architecture impose que `lib/services/**` soit du **Dart pur, deps injectées
par constructeur** — donc unitairement testable sans Flutter ni GetIt. Le ratio
effort/gain y est le meilleur du dépôt.

## Cible

Faire passer `services` de **34,6 % → ~50 %** ⇒ **~+2 900 lignes** ⇒ couverture
globale **~47–48 %**. Atteignable en traitant les Tiers 1 et 2 ci-dessous ; le
Tier 3 (I/O/plateforme) est hors périmètre.

## Heuristique de tri (et son piège)

Trier par **lignes manquantes** (gain absolu), puis par **pureté**. Un
`grep dart:io|Process|File(` classe vite un fichier, **mais ce n'est qu'une
heuristique** : `file/utils/file_validator.dart` importe `dart:io` et reste de
la **logique pure** (il valide des modèles/strings en mémoire). **Vérifier les
méthodes, pas les imports.**

## Conventions à réutiliser

- **mocktail** pour les deps injectées ; `Result.when(ok/err)` partout.
- Timestamps modèles = `int` epoch (pas `DateTime`).
- Pour le code lisant un `File`, écrire un fichier temporaire
  (`Directory.systemTemp.createTempSync`) en `setUp`/`tearDown` — déjà fait dans
  `test/unit/services/file/...`. Préférer toutefois tester les **sous-parsers
  purs** (qui prennent bytes/String) plutôt que le wrapper I/O.
- Voir [[widget-test-scaffolding]] et le flake [[token-encoder-tests-flaky-parallel]].
- Vérif : `flutter test` puis `flutter test --coverage` ; un commit par phase.

---

## Phase A — Logique pure (ROI maximal, ~haute confiance)

Aucun I/O réel : entrées = modèles/strings, sorties = valeurs. mocktail au plus
pour un logger.

| Fichier | Manquant | Approche |
|---------|----------|----------|
| `translation/prompt_builder_service_impl.dart` | 0/219 | ✅ **FAIT.** Construit le prompt LLM ; 22 tests sur toutes les variations. **Plus gros gain pur du dépôt.** |
| `file/utils/file_validator.dart` | 1/138 | **Pur malgré `dart:io`.** `validateLocalizationFile` / `validateEntry` / `validateTsvLine` sur des modèles in-memory. |
| `llm/llm_custom_rules_service.dart` | 0/115 | Repo `LlmCustomRuleRepository` injecté → mocktail + fake logger ; pas de DB directe. |
| `file/parsers/` (binary_loc / tsv / encoding_detector) | à vérifier | Sous-parsers purs (bytes/String) sous-jacents à `localization_parser_impl`. Confirmer pureté puis tester round-trips parse/format. |

**Gain estimé : ~470 lignes.** Verrouille les patterns avant le Tier 2.

> **Correction (constatée à l'exécution).** Les managers `concurrency/`
> (pessimistic 202, conflict_resolver 163, optimistic 127, batch_isolation 149)
> et `shared/event_bus.dart` ne sont **PAS** de la logique en mémoire : ils
> dépendent du singleton statique `DatabaseService.database`. Ils sont testables
> mais via une **vraie DB sqflite_ffi de test** (intégration, sensible au flake
> [[flutter-test-sqlite-dll-lock]]) — déplacés en **Phase D (DB-intégration)**
> ci-dessous, hors de cette phase « logique pure ». Leçon : « pas de `dart:io` »
> ne garantit pas la pureté — vérifier aussi la dépendance à `DatabaseService`.

## Phase B — Service impls à deps injectées (mocker repos/clients)

`ProviderContainer` non requis (Dart pur) — instancier le service avec des mocks
mocktail de ses repos/clients.

| Fichier | Manquant | Deps à mocker |
|---------|----------|---------------|
| `mods/mod_update_analysis_service.dart` | 52/250 | repos d'analyse/cache ; brancher des Result ok/err. |
| `llm/llm_service_impl.dart` | 37/224 | client LLM + glossaire ; tester découpage/retry/erreurs (pas d'appel réseau réel). |
| `glossary/glossary_service_impl.dart` | 36/216 | glossary repo ; CRUD + provisioning. |
| `translation_memory/tm_matching_service.dart` | 53/188 | logique de matching (en partie pure) — fuzzy/exact/seuils. |
| `translation_memory/tm_crud_service.dart` | 50/177 | TM repo ; insert/update/delete/query. |
| `glossary/glossary_import_service.dart` | 25/159 | parsing d'import + repo ; lignes valides/invalides. |
| `history/history_service_impl.dart` | 25/145 | history repo ; push/undo/redo/limites. |

**Gain estimé : ~1 200 lignes.**

## Phase C (hors périmètre) — I/O & plateforme

Faible ROI sans infra lourde ; **ne pas traiter dans ce plan** (les logguer si
on borne la couverture) :

- `file/mixins/file_operations_mixin.dart` (0/231), `localization_parser_impl.dart` (wrapper File)
- `rpfm/rpfm_cli_manager.dart`, `rpfm/mixins/rpfm_extraction_mixin.dart` — **CLI externe**
- `file/file_watch_service.dart` — watcher FS · `concurrency/batch_isolation_manager.dart` — isolates
- `steam/steam_detection_service.dart`, `steam/workshop_api_service_impl.dart`, `workshop_metadata_service.dart` — plateforme/réseau
- `shared/process_service.dart` — `Process`

---

## Phase D (nouvelle) — Managers DB-backed (intégration sqflite_ffi)

Nécessitent une DB de test en mémoire (`test/helpers/test_database.dart`),
pas des mocks. ROI correct (~640 lignes à 0 %) mais setup + flake sqlite.

- `concurrency/optimistic_lock_manager.dart` (0/127) — checkVersion / update /
  increment / reset / batch / hasBeenModified sur une table versionnée de test.
- `concurrency/pessimistic_lock_manager.dart` (0/202)
- `concurrency/conflict_resolver.dart` (0/163)
- `concurrency/batch_isolation_manager.dart` (0/149)
- `shared/event_bus.dart` (5/139) — vérifier la dépendance DB avant.

## Ordre & arrêt

1. **Phase A** d'abord (pur, rapide, le plus rentable).
2. **Phase B** ensuite (mocks ; le gros du volume restant).
3. Recalculer après chaque phase ; **s'arrêter dès que `services` ≈ 50 %** — au-delà, le ROI bascule vers le Tier 3 I/O.

## Note de méthode

Avant de tester un fichier « I/O » du Tier C, vérifier s'il **délègue** à des
helpers purs (comme `localization_parser_impl` → `parsers/`) : tester les
helpers donne le même gain de lignes sans monter d'infra fichier.
