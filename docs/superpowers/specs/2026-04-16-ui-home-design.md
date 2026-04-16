# TWMT — UI redesign — Plan 3 · Home dashboard — design spec

**Date:** 2026-04-16
**Status:** design · pending implementation plan
**Parent spec:** `docs/superpowers/specs/2026-04-14-ui-redesign-design.md` (§7.4 archetype, §9 vanity removal)
**Mockup:** `.superpowers/brainstorm/2035-1776190006/content/home-v2.html`

---

## 1. Intent

Remplacer l'actuel `HomeScreen` (Welcome + vanity stats + recent) par un dashboard actionnable qui raconte le workflow en 4 étapes, met en avant les tâches qui attendent une action, et persiste un journal d'événements réutilisable par d'autres écrans futurs.

L'écran suit l'archétype "Dashboard" du spec parent §7.4 et applique la suppression des vanity metrics prescrite en §9.

All UI strings are in English (spec parent §11 — EN-only).

---

## 2. Scope

**In scope**
- Nouveau `HomeScreen` composé de 5 blocs (header, workflow ribbon, action grid, recent list, activity feed).
- État vide unique (`projects == 0`) remplace `RecentProjectsList + ActivityFeedPanel` par un `EmptyStateGuide` 3 étapes.
- Nouveau module feature `activity` (table `activity_events`, repository, service logger, provider de feed).
- Instrumentation de 5 services existants pour émettre des events (`translationBatchCompleted`, `packCompiled`, `projectPublished`, `modUpdatesDetected`, `glossaryEnriched`).
- Invalidation ciblée des providers Home côté émetteur d'event.
- Flag `hideBreadcrumb` sur le shell (ou équivalent) pour ne pas afficher le crumb sur la Home.
- Suppression des widgets et du provider `dashboardStatsProvider` devenus obsolètes.

**Out of scope** (reporté à Plans 4/5 ou au-delà)
- Command palette globale (`⌘K`) — bouton présent mais placeholder désactivé.
- Wizard standalone "New project" — le CTA `+ New project` route vers `/sources/mods`.
- Migration du breadcrumb du shell vers la toolbar de chaque écran (suivi déjà consigné comme follow-up du Plan 2).
- Pagination / filtrage avancé de l'activity feed — limite figée à 20 events.
- Filtrage des listes cibles depuis la Home via query params (`?filter=needs-review`, etc.) — la Home écrit le query param, mais l'interprétation côté écran cible arrive en Plan 5 (Projects) et futur plan Mods.

---

## 3. Layout & composants

**Arborescence du nouveau `HomeScreen`**

```
HomeScreen (ConsumerWidget)
└── FluentScaffold (hideBreadcrumb: true)
    └── SingleChildScrollView
        └── Column
            ├── HomePageHeader
            │     • Display title "Home"
            │     • Status sub-line (logique §3.1)
            │     • Right cluster : [Command ⌘K · placeholder désactivé] [+ New project → /sources/mods]
            │
            ├── WorkflowRibbon                       (section "Workflow")
            │     4 cartes reliées par flèches :
            │     (1) Detect · (2) Translate · (3) Compile · (4) Publish
            │     États visuels : done / current / next (styles tokens spec parent §7.4)
            │
            ├── ActionGrid                           (section "Needs attention")
            │     4 cartes cliquables :
            │     To review · Ready to compile · Mod updates · Ready to publish
            │     Highlight accent + dot pulsé top-right quand count > 0 ET action urgente
            │
            └── HomeRecentActivity (Row)
                ├── RecentProjectsList  (flex 2, section "Recent")
                │     Jusqu'à 5 projets, next-action badge (§3.2)
                └── ActivityFeedPanel   (flex 1, section "Activity")
                      Jusqu'à 20 events récents
```

### 3.1 — Sub-line status logic

Priorité décroissante (première condition vraie gagne) :

1. `projectsToReviewCount > 0` → `"N project(s) need your attention"`
2. `projectsReadyToCompileCount > 0` → `"N project(s) ready to compile"`
3. `modsWithUpdatesCount > 0` → `"N mod update(s) available"`
4. sinon → `"All caught up"`

### 3.2 — Next-action logic (hiérarchie 4 états, priorités décroissantes)

```
1. needsReview > 0                                → "To review"
2. translatedPct == 0                             → "Translate"
3. translatedPct == 100 && no pack generated yet  → "Ready to compile"
4. sinon                                          → "Continue"
```

Retourne une valeur d'enum `NextProjectAction` portée par un modèle `ProjectWithNextAction { Project project, NextProjectAction action }`.

### 3.3 — Empty state (projects == 0)

- `WorkflowRibbon` : carte 1 en état `current`, cartes 2-4 en `next` avec metrics = 0.
- `ActionGrid` : 4 cartes affichées à 0, sans highlight ni dot pulsé.
- Le bloc `HomeRecentActivity` est remplacé par un `EmptyStateGuide` full-width qui présente 3 étapes numérotées :
  1. `"Detect your mods in Sources"` → CTA route `/sources/mods`
  2. `"Create a project from a mod"` → CTA route `/sources/mods`
  3. `"Translate the units"` → CTA route `/work/projects`

### 3.4 — Widgets atomiques réutilisables

Placés dans `lib/widgets/cards/` pour les Plans 4/5 :
- `TokenCard` — primitive (bg panel-2, border, radius 10, padding token-driven).
- `ActionCard` — TokenCard + label uppercase font-mono + large value + desc, variante `highlight` pour l'action urgente.
- `WorkflowCard` — TokenCard + step number badge + title display + state pill + metric + CTA row ; variantes `done` / `current` / `next`.

Tous consomment exclusivement `context.tokens` (règle absolue du spec parent §4.3 : zéro `#xxxxxx` en dur).

---

## 4. Data flow & providers

Les providers sont **primitifs et composés** — pas d'agrégateur monolithique. Chaque carte lit son propre provider ; les providers partagent les mêmes sources de données pour garantir la cohérence des compteurs entre workflow ribbon et action grid.

```
Workflow ribbon
  modsDiscoveredCountProvider          → features/mods repository
  modsWithUpdatesCountProvider         → features/mods repository
  activeProjectsCountProvider          → projectRepository (filtered by selected game)
  projectsReadyToCompileProvider       → projects 100% translated ET pas de pack généré
  packsAwaitingPublishProvider         → pack_compilation repository (compiled ET !published)

Action grid (partage les primitifs)
  projectsToReviewProvider             = projects avec needsReview > 0
  projectsReadyToCompileProvider       (réutilisé)
  modsWithUpdatesCountProvider         (réutilisé)
  packsAwaitingPublishProvider         (réutilisé)

Recent
  recentProjectsProvider               (refactoré : retourne List<ProjectWithNextAction>)

Activity
  activityFeedProvider                 → lit les 20 derniers ActivityEvent, triés desc
```

Tous ces providers respectent le game filter (`selectedGameProvider`) déjà en place.

### 4.1 — Invalidation (stratégie Q9 option A — Riverpod invalidation ciblée)

Chaque émission d'event log déclenche l'invalidation des providers impactés, côté service émetteur :

| Event émis | Providers invalidés |
|---|---|
| `translationBatchCompleted` | `activityFeedProvider`, `recentProjectsProvider`, `projectsToReviewProvider`, `projectsReadyToCompileProvider`, `activeProjectsCountProvider` |
| `packCompiled` | `activityFeedProvider`, `recentProjectsProvider`, `projectsReadyToCompileProvider`, `packsAwaitingPublishProvider` |
| `projectPublished` | `activityFeedProvider`, `packsAwaitingPublishProvider` |
| `modUpdatesDetected` | `activityFeedProvider`, `modsWithUpdatesCountProvider`, `modsDiscoveredCountProvider` |
| `glossaryEnriched` | `activityFeedProvider` |

---

## 5. Event log (module `activity`)

### 5.1 — Feature directory

```
lib/features/activity/
├── models/
│   └── activity_event.dart
├── database/
│   └── activity_events_table.dart
├── repositories/
│   ├── activity_event_repository.dart
│   └── activity_event_repository_impl.dart
├── services/
│   ├── activity_logger.dart
│   └── activity_logger_impl.dart
└── providers/
    └── activity_feed_provider.dart
```

### 5.2 — Domain model

```dart
enum ActivityEventType {
  translationBatchCompleted,
  packCompiled,
  projectPublished,
  modUpdatesDetected,
  glossaryEnriched,
}

class ActivityEvent {
  final int id;
  final ActivityEventType type;
  final DateTime timestamp;
  final String? projectId;      // UUID, null pour modUpdatesDetected
  final String? gameCode;       // null si event global
  final Map<String, dynamic> payload;
}
```

`payload` contient les détails spécifiques au type (ex. `{ "count": 124, "method": "llm" }` pour `translationBatchCompleted`).

### 5.3 — Schéma DB (migration incrémentale)

```sql
CREATE TABLE activity_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  project_id TEXT,
  game_code TEXT,
  payload TEXT NOT NULL
);
CREATE INDEX idx_activity_events_ts ON activity_events(timestamp DESC);
CREATE INDEX idx_activity_events_game ON activity_events(game_code, timestamp DESC);
```

`project_id` a `ON DELETE SET NULL` pour préserver l'historique si un projet est supprimé.
La migration est incrémentale : `schemaVersion + 1` ajoute table + index, pas de backfill. La feed démarre vide pour les users existants après upgrade.

### 5.4 — Repository API

```dart
abstract class ActivityEventRepository {
  Future<Result<ActivityEvent, AppError>> insert(ActivityEvent event);
  Future<Result<List<ActivityEvent>, AppError>> getRecent({
    String? gameCode,
    int limit = 20,
  });
}
```

### 5.5 — ActivityLogger — fire-and-forget

```dart
abstract class ActivityLogger {
  Future<void> log(
    ActivityEventType type, {
    String? projectId,
    String? gameCode,
    Map<String, dynamic> payload = const {},
  });
}
```

L'implémentation catch toute erreur du repo et la log via le logger applicatif standard — **jamais** de throw. Un event perdu ne doit jamais faire échouer une traduction, compilation ou publication.

### 5.6 — Sites d'instrumentation

| Service existant | Event émis | Payload |
|---|---|---|
| `services/translation/handlers/translation_batch_*` | `translationBatchCompleted` | `{ count, method: "llm"│"manual", projectName }` |
| `services/pack/pack_compilation_service` | `packCompiled` | `{ projectName, packFileName }` |
| `services/steam/workshop_publish_service_impl` | `projectPublished` | `{ projectName, workshopId? }` |
| `services/mods/mod_update_analysis_service` | `modUpdatesDetected` | `{ count }` |
| `features/glossary/providers/glossary_providers` (add flow) | `glossaryEnriched` | `{ count }` |

### 5.7 — Dette DI minimisée

Le paramètre `ActivityLogger` est **optionnel (nullable)** dans les constructeurs des services existants. Les call sites `log(...)` deviennent `logger?.log(...)`. Ceci garantit que les tests existants (qui construisent ces services avec des fakes) n'ont pas besoin d'être modifiés.

---

## 6. Routing & navigation

Aucune nouvelle route. `/work/home` pointe vers le nouveau `HomeScreen`.

**CTAs internes et routes cibles**

| Élément | Action |
|---|---|
| `HomePageHeader` · `+ New project` | push `/sources/mods` |
| `HomePageHeader` · `Command ⌘K` | désactivé (placeholder, pas d'action) |
| `WorkflowCard` · Detect | push `/sources/mods` |
| `WorkflowCard` · Translate | push `/work/projects` |
| `WorkflowCard` · Compile | push `/publishing/compile` |
| `WorkflowCard` · Publish | push `/publishing/workshop` |
| `ActionCard` · To review | push `/work/projects?filter=needs-review` |
| `ActionCard` · Ready to compile | push `/work/projects?filter=ready-to-compile` |
| `ActionCard` · Mod updates | push `/sources/mods?filter=updates` |
| `ActionCard` · Ready to publish | push `/publishing/workshop` |
| `RecentProjectsList` row click | push `/work/projects/:id` |
| `EmptyStateGuide` step 1 & 2 CTA | push `/sources/mods` |
| `EmptyStateGuide` step 3 CTA | push `/work/projects` |

Les query params `?filter=...` sont écrits par le Plan 3 mais interprétés au Plan 5 (Projects) et à un plan Mods futur. En attendant, les écrans cibles ignorent le filtre — la navigation fonctionne, le filtre sera appliqué automatiquement quand les plans suivants arriveront.

**Hide breadcrumb** — `FluentScaffold` (ou le porteur du breadcrumb dans `MainLayoutRouter`) accepte un flag `hideBreadcrumb: bool = false`. `HomeScreen` passe `true`. Décision d'implémentation (flag par écran vs règle `NavigationTree` sur la racine d'un groupe) à prendre au plan d'implémentation ; flag par écran recommandé pour rester minimal.

---

## 7. Migration & suppressions

**Widgets supprimés** (après complétion de la migration)
- `lib/features/home/widgets/welcome_card.dart`
- `lib/features/home/widgets/stats_cards.dart`
- `lib/features/home/widgets/recent_projects_card.dart`

**Providers modifiés / supprimés**
- `dashboardStatsProvider` — supprimé, vanity metrics remplacées par les providers primitifs §4.
- `recentProjectsProvider` — refactoré pour retourner `List<ProjectWithNextAction>` au lieu de `List<Project>`.

**Tests à actualiser**
Tous les tests qui importent les widgets/providers supprimés ou refactorés, identifiés au moment de l'exécution du plan.

**Backwards compat** — aucune. `dashboardStatsProvider` n'était consommé que par `StatsCards`, lui aussi supprimé.

---

## 8. Testing

### 8.1 — Unit tests

- `ActivityEventRepository` (Drift réel, pas de mock DB — feedback mémoire projet) : insert, getRecent avec et sans `gameCode`, ordre desc, limit 20.
- `ActivityLogger` : logger appelle repo avec bons args ; en cas d'erreur repo, capture et retourne sans throw.
- Providers primitifs (`projectsToReviewProvider`, `projectsReadyToCompileProvider`, `modsWithUpdatesCountProvider`, `activeProjectsCountProvider`, `packsAwaitingPublishProvider`, `modsDiscoveredCountProvider`) : fixtures avec variations d'état, vérifier compteurs corrects + respect du game filter.
- `recentProjectsProvider` refactoré : chaque règle de `NextProjectAction` (§3.2) testée par cas, priorité respectée.
- `activityFeedProvider` : limit 20, tri desc, game filter.
- `HomePageHeader` sub-line logic (§3.1) : priorité needsReview > readyToCompile > modUpdates > fallback.

### 8.2 — Widget tests

- `WorkflowRibbon` : renders 4 cards, états `done/current/next` correctement appliqués selon data.
- `ActionGrid` : dot pulsé seulement quand `count > 0`, highlight sur urgences.
- `RecentProjectsList` : renders le bon next-action badge pour chaque ligne, rend rien si liste vide (le parent gère l'empty state).
- `ActivityFeedPanel` : affiche events avec timestamp relatif (`3 min ago`, `yesterday`), placeholder quand feed vide.
- `EmptyStateGuide` : visible quand `projects == 0`, 3 steps rendus, CTAs cliquables.
- `HomePageHeader` : sub-line reflète la logique §3.1 selon mock providers.

### 8.3 — Integration (HomeScreen complet)

- Route `/work/home` rend tous les blocs en mode données normales.
- Mode empty (`projects == 0`) : ribbon + grid à 0, `EmptyStateGuide` remplace `RecentActivity`.
- Changement de game filter : providers re-query, compteurs à jour.
- Click sur `+ New project` → push `/sources/mods` vérifié via mock router.

### 8.4 — Invalidation integration (critique)

- Simuler `packCompiled` → `ActivityFeedPanel` affiche la nouvelle ligne ; `projectsReadyToCompile` décrémente ; `packsAwaitingPublish` incrémente.
- Un test par type d'event (5 tests).

### 8.5 — Golden tests

2 thèmes × 2 variantes = 4 goldens (fixtures avec dates figées) :
- `home_dashboard_atelier.png`, `home_dashboard_forge.png`
- `home_empty_atelier.png`, `home_empty_forge.png`

### 8.6 — DB migration

Test `v(N) → v(N+1)` : table + index créés, données existantes préservées, insert post-migration OK.

Estimation : ~40 nouveaux tests (baseline 1227 → ~1267).

---

## 9. Open questions / à clarifier au plan d'implémentation

1. **Emplacement exact du flag `hideBreadcrumb`** — `FluentScaffold` ou widget porteur du breadcrumb dans `MainLayoutRouter` ? À vérifier dans l'impl existante au début du plan.
2. **Payload JSON vs colonnes typées** — on part sur `payload TEXT (JSON)` pour la flexibilité ; si les requêtes futures exigent un filtrage par champ du payload, migration possible plus tard.
3. **Formatage des timestamps de l'activity feed** — `DateFormat` + logique relative (`3 min ago`, `yesterday`, date absolue au-delà d'une semaine). Exact formatting à figer côté implémentation.
4. **Test ordering de l'activity feed** — les events d'un même timestamp retournés par `getRecent` ont un tri déterministe ? Si SQLite retourne dans l'ordre d'insertion pour égalité, OK. Sinon, ajouter `ORDER BY timestamp DESC, id DESC`.
5. **Déduplication d'events** — si deux batches de traduction d'affilée émettent deux events dans la même seconde, doit-on les regrouper côté UI ? Pour le Plan 3, non — affichage brut.

---

## 10. Implementation dependencies

- Plan 1 (shipped) : tokens `context.tokens`, scrollbar themée, thèmes Atelier/Forge.
- Plan 2 (shipped) : routes nested, breadcrumb au shell level, widget `Breadcrumb` existant.
- Aucun prérequis supplémentaire.

Le Plan 3 est le dernier à pouvoir démarrer indépendamment avant que Plans 4 et 5 commencent — il établit les primitives `TokenCard` / `ActionCard` / `WorkflowCard` que les plans suivants réutiliseront.
