# Restore published Steam IDs via `project_publication`

**Date:** 2026-06-14
**Status:** Approved (design)
**Area:** Steam Publish feature (`lib/features/steam_publish`), database migrations, repositories

## Problem

The Steam Publish screen shows "—" (no Steam ID) for every project, even though
the user has 342 published translations with real Workshop IDs. The data is
intact in a **`project_publication`** table in the production DB, keyed by
`(project_id, language_code)` — e.g. project *Legendary Lore* → `fr` →
`3664274763` (distinct from the source mod id `2789857945`).

The current committed code does **not** read that table. It reads the flat
`projects.published_steam_id` column (via `ProjectPublishItem.publishedSteamId =>
project.publishedSteamId`), which is empty in this DB (and was even dropped by a
throwaway, uncommitted migration on 2026-06-14 20:04). Result: the publish list
displays nothing and items are wrongly treated as unpublishable.

### Evidence

- `project_publication`: 342 rows, all `language_code = 'fr'`, one per project,
  every `steam_id != mod_steam_id` (genuinely the translation's own id).
- `projects.published_steam_id`: NULL for all projects even in the 16:17 backup;
  the column itself is currently absent in the live DB.
- `project_publication` appears in **no committed code** anywhere in git
  (working tree, all branches, history) — it originates from discarded/uncommitted
  work. We treat the observed table schema as the contract.

### Why writes matter too

The committed code *writes* published ids to `projects.published_steam_id` in
three places (manual edit, single publish, batch publish). Other installs may
therefore hold their ids in that column. Switching reads to `project_publication`
without rapatriating that legacy data would break the display for those users.

## Goals

- Publish screen displays the published Steam ID stored in `project_publication`,
  resolved by the project's **target language**.
- Edits and successful publishes persist to `project_publication`.
- Legacy ids in `projects.published_steam_id` are migrated forward (no data loss
  for other installs).
- Fresh installs get the table created automatically.

## Non-goals

- No change to **compilation** publishing (compilations keep their own
  `published_steam_id` column and work today).
- No dropping of `projects.published_steam_id` (left vestigial to avoid a
  destructive schema change; simply no longer read or written for projects).
- No per-language explosion of the publish list (one row per project — see
  language resolution below).

## Design

### Language resolution rule

The list shows one row per project, but `project_publication` is per
`(project, language)`. For a given project, the displayed/edited id is the row
matching the project's **target language**, resolved as:

1. The project's target languages come from `project_languages` (already loaded
   in `publishableItems` as `langCodes`).
2. Pick the publication row whose `language_code` equals the project's first
   target language; if `fr` is among the target languages prefer the exact
   match; if no row matches a target language but rows exist, fall back to the
   single/first available row.

All current data is `fr`, so this is unambiguous in practice; the rule only
matters for multi-language projects.

### 1. Data layer

**Migration `CreateProjectPublicationTableMigration`** (idempotent, registered
in `MigrationRegistry`):

- `CREATE TABLE IF NOT EXISTS project_publication (project_id TEXT NOT NULL,
  language_code TEXT NOT NULL, steam_id TEXT, published_at INTEGER,
  PRIMARY KEY (project_id, language_code))` — matches the observed schema exactly.
- **Backfill** from the legacy column, guarded by a `PRAGMA table_info(projects)`
  check that `published_steam_id` exists: for each project with a non-empty
  `published_steam_id`, `INSERT OR IGNORE INTO project_publication` using the
  project's resolved target language and the legacy `published_at`.
- `isApplied()` returns true once the table exists **and** (if the legacy column
  is present) the backfill has run; simplest: gate `isApplied()` on table
  existence and make the backfill itself `INSERT OR IGNORE` (safe to repeat).
- Priority: after the projects table/columns exist and after
  `ProjectTypeMigration`; before index migrations. Concretely a priority in the
  ~95–115 band (e.g. 96), and confirmed not to collide with existing priorities.

**Model `ProjectPublication`** (`lib/models/domain/project_publication.dart`):
fields `projectId`, `languageCode`, `steamId` (nullable), `publishedAt`
(nullable), with json mapping matching the column names.

**Repository `ProjectPublicationRepository`**
(`lib/repositories/project_publication_repository.dart`):

- `getAll()` → all rows (bulk load for the provider; avoids N+1).
- `getByProject(projectId)` → rows for one project.
- `upsert(projectId, languageCode, steamId, publishedAt)` →
  `INSERT ... ON CONFLICT(project_id, language_code) DO UPDATE`.

Wire it into `lib/providers/shared/repository_providers.dart` (and GetIt
registration if the repo layer requires it, following the existing pattern).

### 2. Read path

`publishableItems` (`steam_publish_providers.dart`):

- Load `projectPublicationRepo.getAll()` once, index into
  `Map<String, List<ProjectPublication>>` by `project_id`.
- For each project, resolve the published id/timestamp via the language rule and
  pass them into `ProjectPublishItem`.

`ProjectPublishItem`: add constructor params `publishedSteamId` /
`publishedAt`; the getters return these resolved values instead of
`project.publishedSteamId` / `project.publishedAt`. Everything downstream
(`SteamIdCell`, `_isPublishable`, `outdated` filter, subscriber-total) already
flows through these getters and needs no further change.

### 3. Write path

Replace the three `projects.published_steam_id` writers with
`projectPublicationRepo.upsert(...)`, supplying the project's resolved target
language:

- `steam_id_editing.dart` `saveWorkshopId` (manual edit) — language from the
  `ProjectPublishItem`'s resolved target language.
- `workshop_publish_notifier.dart` (single publish success).
- `batch_workshop_publish_notifier.dart` (batch publish success).

For the notifiers, the target language is resolved at write time from the
project's languages (or threaded via the publish item) — the implementation plan
will pick the least invasive option after reading the batch item plumbing.

`projects.published_steam_id` is no longer read or written for projects.

### 4. Testing

- **Migration test**: table creation, backfill from a legacy `published_steam_id`
  column (with target-language resolution), idempotence (run twice → no error,
  no dup), and the no-legacy-column case (this user's DB shape).
- **Repository test**: `getAll` / `getByProject` / `upsert` (insert + conflict
  update), against `TestDatabase` (in-memory) per repo-test conventions.
- **Provider test**: `publishableItems` resolves the correct id by target
  language; multi-language fallback behaves per the rule.

## Risks / edge cases

- Legacy column absent (live DB) → backfill guarded by PRAGMA check, becomes a
  no-op.
- Multi-language project with several publication rows → resolution rule picks
  the target-language row deterministically; documented and tested.
- Tests must never touch the production DB (use `TestDatabase` / mocked
  `path_provider`), per project guardrails.
