# Game-Specific Glossaries Refactor — Design

**Date:** 2026-04-24
**Status:** Approved for planning

## Goal

Remove the "universal glossary" concept. Every glossary is game-specific and bound to exactly one (game, target language) pair. One glossary per (game, language), auto-generated empty. No more manual creation UI. Existing universal glossaries are migrated via a blocking alert screen that offers CSV export and conversion to a specific game.

## Motivation

The universal-glossary concept creates ambiguity: users cannot tell at a glance which glossary applies where, and the UI forces them to manually create and name glossaries even though the (game, language) pair is the only meaningful axis. Auto-provisioning and a translation-editor-style language switcher reduce this to a single, deterministic view per context.

## Scope

**In scope**
- Data model change: glossary identified by `(game_code, target_language_id)`.
- Migration flow (alert screen) for existing universal glossaries and game-specific duplicates.
- Auto-provisioning of empty glossaries when a game is configured or a project language is added.
- Refactored glossary screen driven by the sidebar's `selectedGameProvider` and a new language switcher.
- Removal of manual glossary creation UI and related plumbing.

**Out of scope**
- Changes to glossary entries (source_term / target_term / notes) schema.
- Changes to import / export formats beyond the already-existing CSV export.
- Glossary matching / DeepL / statistics services (untouched beyond the `isGlobal` parameter removal).

## Non-goals

- Providing per-installation glossaries (we aggregate by game code — Steam vs GOG vs duplicate installs share one glossary per language).
- Supporting more than one glossary per (game, language) after migration.
- Offering a "merge later" tool: duplicates are resolved during the one-shot migration.

## Decisions (from brainstorming)

| Question | Decision |
| --- | --- |
| Pre-existing duplicate game-specific glossaries | **Merge automatically** during migration, dedup by source_term (case-insensitive, trimmed), keep most recent entry on conflict (`updated_at`). |
| Grain of "per game" | **Per `game_code`** (not per `game_installation_id`). FK replaced by a TEXT column referencing the static game catalogue. |
| Auto-creation timing | **Eager** — on game configuration and on project-language addition. |
| Collision on conversion | **Merge** the converted universal into the existing (game, language) glossary, with the same dedup rule. |
| Multiple conversions | **Allowed line-by-line** in the migration screen; several universals can target the same game → merged + deduped. |
| UI structure | **No game dropdown in glossary screen**: game comes from the existing sidebar `selectedGameProvider`. Only a language chip at the top, inspired by `editor_language_switcher`. |
| UI language | **All user-facing strings in English exclusively.** |
| Empty states (no project / no language) | Informative message, no error. |

## Data Model

### `glossaries` table

**Removed**
- `is_global INTEGER` (and its CHECK constraint)
- `game_installation_id TEXT` (FK to `game_installations`)
- `UNIQUE(name)` constraint

**Added**
- `game_code TEXT NOT NULL`
- `UNIQUE(game_code, target_language_id)`

**Unchanged**
- `id`, `name` (now just a display label, auto-generated), `description`, `target_language_id`, `created_at`, `updated_at`

### `Glossary` Dart model

- Drop `isGlobal`, `gameInstallationId`.
- Add `gameCode` (non-null `String`).
- Update `copyWith`, `==`, `hashCode`, `toJson` / `fromJson`.

### Auto-generated name

`"{gameName} · {languageCode}"` — e.g. `"Total War: WARHAMMER III · fr"`. No uniqueness requirement on `name` anymore; the uniqueness is enforced on `(game_code, target_language_id)`.

## Migration Strategy

Two-phase SQLite migration.

### Phase 1 — Partial schema migration (automatic, at boot)

1. Add nullable `game_code TEXT` column.
2. Populate `game_code` from `game_installations.game_code` for all game-specific glossaries (`is_global = 0`).
3. Leave `game_code = NULL` for all universal glossaries (`is_global = 1`).
4. Do **not** drop `is_global` or `game_installation_id` yet.
5. Do **not** add the unique constraint yet.

At this point the schema is "half-migrated" — the app must not be used normally until phase 2 runs.

### Phase 2 — Application-driven migration (user-facing alert)

Phase 2 has two parts: **detection** (runs at every boot) and **finalization** (runs once, after the user validates the migration screen).

**Detection** — at boot, after phase 1, run the following predicate:

```sql
SELECT 1 FROM glossaries WHERE game_code IS NULL
UNION ALL
SELECT 1 FROM glossaries
  WHERE game_code IS NOT NULL
  GROUP BY game_code, target_language_id
  HAVING COUNT(*) > 1
LIMIT 1;
```

If the query returns a row, the app pushes a blocking route `GlossaryMigrationScreen` from the bootstrap flow. No other screen is reachable until the migration is resolved.

**Finalization** — once the user validates the migration screen:

1. For each universal that the user chose to convert: apply conversion (see "Conversion" below).
2. Delete universals that the user did not convert.
3. For each (game_code, target_language_id) with >1 glossary: merge duplicates (see "Merge" below).
4. Finalize schema:
   - `ALTER TABLE glossaries ... game_code NOT NULL`
   - `CREATE UNIQUE INDEX glossaries_game_lang_uq ON glossaries(game_code, target_language_id)`
   - Drop columns `is_global` and `game_installation_id`
   - Drop `UNIQUE(name)` constraint
5. Close the migration screen and reload the app state.

### Conversion (universal → game-specific)

Given a universal glossary `G` (with `target_language_id = L`) and a chosen `game_code = C`:

- If a glossary `X` for `(C, L)` already exists:
  - Merge `G`'s entries into `X` (dedup on `source_term`, case-insensitive + trimmed; on conflict keep the most recent entry by `updated_at`).
  - Delete `G`.
- Else:
  - Update `G`: set `game_code = C`. `G`'s id remains valid.

### Merge (duplicates of same (game, language))

For each group of >1 glossaries sharing `(game_code, target_language_id)`:

1. Pick the oldest glossary (by `created_at`) as the survivor.
2. Reassign all entries from the other glossaries into the survivor.
3. For source_term collisions (case-insensitive + trimmed): keep the entry with the highest `updated_at`.
4. Delete the other glossaries.

## Migration Screen — `GlossaryMigrationScreen`

Blocking modal route, pushed by the bootstrap when phase-2 migration is pending.

**Layout**

Top section — **Universal glossaries to resolve** (shown only if at least one exists):

- One row per universal glossary. Each row displays:
  - Name, description (if any), target language code, entry count.
  - `Export CSV` button — calls `GlossaryExportService.exportToCsv(glossaryId, filePath)` via a file-picker.
  - `Convert to…` dropdown — lists configured games (from `configuredGamesProvider`) + a `— Don't convert —` option.
- Persistent warning at the section footer:
  > "Universal glossaries not converted will be deleted permanently."

Bottom section — **Duplicate game-specific glossaries** (shown only if any exist):

- For each `(game_code, target_language_id)` with more than one glossary:
  - List the names and entry counts.
  - Static message:
    > "These glossaries will be merged automatically. Duplicate entries (same source term, case-insensitive) will be deduplicated, keeping the most recent one."
- No user choice in this section.

**Footer bar**

- `Cancel migration` button → quits the app (no half-migrated usage allowed).
- `Apply and continue` button → runs the `GlossaryMigrationService` finalization pipeline, then closes and reloads.

## Auto-Provisioning

New service `GlossaryAutoProvisioningService` in `lib/services/glossary/`.

**API**

- `provisionForGame(String gameCode)` — for the given game, for each distinct `target_language_id` used by existing projects of that game, insert an empty glossary if none exists for `(gameCode, languageId)`.
- `provisionForProjectLanguage(String gameCode, String targetLanguageId)` — insert an empty glossary for the pair if not already present.

Both methods are idempotent (no-op when the row exists).

**Triggers**

1. **Game configured** — listen to `configuredGamesProvider`. When a new game appears in the list (i.e., path was added in settings), call `provisionForGame(newGame.code)`.
2. **Language added to project** — hook into the code path that adds a language to a project (likely `AddLanguageDialog` submission / associated provider). Call `provisionForProjectLanguage(project.gameCode, languageId)`.

## Refactored Glossary Screen

### Removed code

- `glossary_new_dialog.dart` and all its call sites (FAB, menu, any action buttons).
- `glossary_list.dart` + any accompanying viewmodel for the list view.
- `selectedGlossaryProvider` — no more "pick one from a list".
- `includeUniversal` and `isGlobal` parameters on all providers, services, and repositories.

### New structure of `GlossaryScreen`

```
┌────────────────────────────────────────────────┐
│ Header                                         │
│   [language chip ▾]                            │
│   (inspired by editor_language_switcher)       │
├────────────────────────────────────────────────┤
│ Toolbar: search, import CSV, export CSV, ...   │
├────────────────────────────────────────────────┤
│ Entries grid (SfDataGrid, unchanged)           │
│ bound to (selectedGame.code, selectedLanguage) │
└────────────────────────────────────────────────┘
```

### Display states (all strings in English)

1. **No game selected** — centered message: `"Select a game from the sidebar to view its glossary."`
2. **Game selected, no projects yet for this game** — centered message: `"No projects yet for {gameName}. A glossary will be generated automatically when you create your first project."` No chip, no editor.
3. **Game selected, projects exist, no languages yet** — centered message: `"No target languages configured for projects of {gameName} yet. A glossary will be generated when you add a language to a project."`
4. **Game + language selected, glossary empty** — soft empty state in the grid area: `"No entries yet. Import a CSV or add your first entry."`
5. **Nominal** — normal editor.

### New widget — `GlossaryLanguageSwitcher`

Adapted from `editor_language_switcher.dart`:

- Uses `MenuAnchor + Chip`.
- Data source: `glossaryAvailableLanguagesProvider(gameCode)` — union of distinct `target_language_id` over projects of the selected game.
- Selection state: `selectedGlossaryLanguageProvider` — persisted per game via `settingsService` (key like `glossary_selected_language_{gameCode}`).
- No "delete" action on language entries.
- No "add language" button (languages are managed at project level).

### New providers

- `glossaryAvailableLanguagesProvider(String gameCode)` — returns distinct `target_language_id` used by projects of the given game.
- `selectedGlossaryLanguageProvider` — `AsyncNotifier` persisting the per-game language selection.
- `currentGlossaryProvider` — watches `(selectedGame, selectedGlossaryLanguage)`, returns the glossary for the pair. Falls back to `getOrCreate` if the row has been deleted manually (defensive).

## Modules and Testing

| Module | Location | Primary responsibility | Tests |
| --- | --- | --- | --- |
| `GlossaryMigrationService` | `lib/services/glossary/glossary_migration_service.dart` | Detect + execute phase 2 | Unit (in-memory SQLite): detection queries, conversion, merge, finalization |
| `GlossaryAutoProvisioningService` | `lib/services/glossary/glossary_auto_provisioning_service.dart` | Create empty glossaries on triggers | Unit + integration (verify hooks fire and are idempotent) |
| `GlossaryMigrationScreen` | `lib/features/glossary/screens/glossary_migration_screen.dart` | User-facing migration UI | Widget tests covering: universals only, duplicates only, mixed, empty state, export CSV action, apply pipeline |
| `GlossaryScreen` refactor | `lib/features/glossary/screens/glossary_screen.dart` | New language-driven editor | Widget tests covering all five display states |
| `GlossaryLanguageSwitcher` | `lib/features/glossary/widgets/glossary_language_switcher.dart` | Language chip | Widget tests |
| Providers | `lib/features/glossary/providers/glossary_providers.dart` | New providers, remove old ones | Provider tests |
| DB Migrations | `lib/database/migrations/` | Phase 1 + Phase 2 schema | Unit tests on migration runner |

## Implementation Order

1. **Schema phase 1 + model + repo** — migrate model/repo/service types (remove `isGlobal`, add `gameCode`). Keep old columns readable until phase 2. Tests pass.
2. **`GlossaryMigrationService`** + unit tests.
3. **`GlossaryMigrationScreen`** + bootstrap integration + widget tests.
4. **`GlossaryAutoProvisioningService`** + hook listeners + tests.
5. **`GlossaryScreen` refactor** — new widgets and providers + widget tests.
6. **Dead code cleanup** — remove `glossary_new_dialog.dart`, `glossary_list.dart`, `selectedGlossaryProvider`, legacy parameters. Also audit: `GlossaryImportExportService`, `glossaryStatisticsProvider`, `glossarySearchResultsProvider`, `glossaryFilterStateProvider` — strip any universal/global code paths.
7. **Schema phase 2** — wire into `GlossaryMigrationService.finalizeSchema()` and ship.

## Risks and Open Questions

- **Settings-driven language persistence:** storing `selected_glossary_language_{gameCode}` as settings keys is straightforward but duplicates the pattern of `selected_game_code`. Acceptable for this scope; can be refactored later if many such keys accumulate.
- **Race between phase 1 and phase 2:** phase 1 runs automatically at boot. If the user kills the app between phase 1 and phase 2, the DB is half-migrated. On next boot the detection predicate fires again and pushes the migration screen — this is idempotent.
- **Conversion of a universal whose target_language_id no longer exists** (language deleted from all projects): the glossary still has a valid `target_language_id` FK since `ON DELETE RESTRICT` on `languages`. No action needed.
- **CSV export during migration:** reuses `GlossaryExportService.exportToCsv` as-is. No new format.
