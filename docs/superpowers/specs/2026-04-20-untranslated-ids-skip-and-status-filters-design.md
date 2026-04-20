# Untranslated unit IDs: align skip and status filters with stats — Design

## Problem

The `Translate All` confirmation dialog reports `1612 untranslated units` while
the sidebar subtitle reads `20 units` for the same project/language/open
editor. Both numbers should agree.

The gap comes from two divergent SQL predicates:

- **Subtitle** (`editorStatsProvider.pendingCount`) is derived from
  `getLanguageStatistics` in `translation_version_statistics_mixin.dart`.
  That query counts rows where `tv.status IN ('pending', 'translating')` AND
  the unit is not obsolete AND the unit passes `_excludeSkipUnitsCondition`
  — a composite predicate that rejects `[HIDDEN]` prefixes, fully-bracketed
  source texts like `[ok]` / `[col:yellow]`, and any user-configurable skip
  text.

- **Dialog** (`unitIds.length` in `handleTranslateAll`) is derived from
  `TranslationVersionRepository.getUntranslatedIds`. That query matches rows
  where `tv.translated_text IS NULL OR = ''` AND the unit is not obsolete
  AND the source text does NOT start with `[HIDDEN]`. It has no status
  filter and no fully-bracketed / user-skip filter.

In a Total War mod the two predicates diverge dramatically:

- Fully-bracketed strings (`[ok]`, `[placeholder]`, `[unit_key]`) are
  common. They have empty `translated_text` by design — they are not meant
  to be translated — so they fall straight into `getUntranslatedIds`'s net
  but are correctly excluded from `pendingCount`.
- `status='translated'` rows with `translated_text=''` (known status
  inconsistency — the schema references `reanalyzeAllStatuses` for exactly
  this class of drift) also slip through.
- User-configurable skip texts (`placeholder`, `dummy`, and whatever the
  user has added) match the stats exclusion but not the repository's.

The same gap exists on the sister query `filterUntranslatedIds` used by
`handleTranslateSelected`; the popup for a selected range is also inflated
when the selection contains bracket-only / skip-listed units.

## Scope

- **In:** align `getUntranslatedIds` and `filterUntranslatedIds` with
  `getLanguageStatistics.pendingCount`'s predicate so the confirmation
  dialog and the sidebar subtitle agree, and the batch actually enqueues
  the units the user expects.
- **Out:** fixing the underlying status-inconsistency drift (that's
  `reanalyzeAllStatuses`'s job), touching the translation batch execution
  path, or changing how TM hits are handled at execution time.

## Design

### New predicate, shared with stats

Both queries adopt the exact predicate that `pendingCount` uses:

1. `tv.status IN ('pending', 'translating')`
2. `tu.is_obsolete = 0`
3. The composite skip filter currently living on
   `TranslationVersionStatisticsMixin` as `_excludeSkipUnitsCondition`.

The skip filter is already battle-tested (HIDDEN prefix, fully-bracketed
detection excluding BBCode, user skip-list). We reuse it rather than
re-deriving.

### Making the skip filter reusable

`_excludeSkipUnitsCondition` is private to the statistics mixin and lives
in a different Dart library from `TranslationVersionRepository`, so it
cannot be invoked from the repository's own methods today. Two options:

- **(A)** Rename to public `excludeSkipUnitsCondition` (single
  underscore-drop, update the three in-file call sites). Zero semantic
  change.
- **(B)** Inline the ~12 lines of SQL into both `getUntranslatedIds` and
  `filterUntranslatedIds`. Simpler Dart, but duplicates a predicate that
  already appears in four queries inside the mixin — so duplication would
  go from 4 to 6.

We pick **(A)**. It keeps the canonical definition in one place and
requires only a mechanical rename. Privacy was incidental, not load-bearing
— the predicate is pure SQL with no state.

### `getUntranslatedIds`

Before:

```sql
SELECT tu.id
FROM translation_versions tv
INNER JOIN translation_units tu ON tv.unit_id = tu.id
WHERE tv.project_language_id = ?
  AND (tv.translated_text IS NULL OR tv.translated_text = '')
  AND tu.is_obsolete = 0
  AND UPPER(TRIM(tu.source_text)) NOT LIKE '[HIDDEN]%'
ORDER BY tu.key
```

After:

```sql
SELECT tu.id
FROM translation_versions tv
INNER JOIN translation_units tu ON tv.unit_id = tu.id
WHERE tv.project_language_id = ?
  AND tv.status IN ('pending', 'translating')
  AND tu.is_obsolete = 0
  AND $excludeSkipUnitsCondition
ORDER BY tu.key
```

The `translated_text IS NULL OR = ''` predicate is dropped. A status in
`('pending', 'translating')` is a stronger guarantee of "has no translation
and is actionable" than the raw empty-text check — status is the source of
truth for the UI, and the status-vs-text drift is exactly what we want to
exclude. Bracket-only / user-skip exclusion is handled entirely by
`excludeSkipUnitsCondition`.

### `filterUntranslatedIds`

Today this query does not join `translation_units` at all — it relies on
an `IN (…)` clause over unit IDs and filters by empty text. To apply the
shared predicate (which references `tu.source_text`) we have to add the
join.

Before:

```sql
SELECT unit_id
FROM translation_versions
WHERE unit_id IN (…)
  AND project_language_id = ?
  AND (translated_text IS NULL OR translated_text = '')
```

After:

```sql
SELECT tu.id
FROM translation_versions tv
INNER JOIN translation_units tu ON tv.unit_id = tu.id
WHERE tu.id IN (…)
  AND tv.project_language_id = ?
  AND tv.status IN ('pending', 'translating')
  AND tu.is_obsolete = 0
  AND $excludeSkipUnitsCondition
```

Same predicate as `getUntranslatedIds`; the only structural difference is
the `IN (…)` membership test over a caller-supplied list of unit IDs.

### Behavioural consequences (documented)

- Bracket-only units and user-skip units stop being enqueued by `Translate
  All` / `Translate Selected`. This is correct — they have nothing to
  translate; today they are enqueued, hit either the batch's TM path or the
  LLM, and either way they waste work.
- `status='translated' with empty text` rows (inconsistency) are no longer
  enqueued. The tool to force-retranslate them is `reanalyzeAllStatuses`
  followed by a bulk operation; that's the intended flow.
- `handleTranslateSelected`'s message `'Translate X untranslated units (Y
  already translated)?'` now treats status≠pending/translating rows as
  "already translated" from the user's perspective. Honest framing.

## Test plan

Two new test groups in a new file
`test/unit/repositories/translation_version_repository_untranslated_filter_test.dart`,
using `TestDatabase.openMigrated()` (the pattern already established for
`translation_version_repository_rescan_test.dart`).

Each group seeds a mix of rows and asserts the filter behaviour:

### Group 1 — `getUntranslatedIds`

Seed (same `project_language_id = 'pl-1'`, all non-obsolete unless noted):

- `u-pending` — status `pending`, empty text, source `normal source`
- `u-translating` — status `translating`, empty text, source `normal source`
- `u-translated-with-text` — status `translated`, non-empty text, source
  `normal source`
- `u-translated-empty` — status `translated`, empty text, source `normal
  source` (inconsistency)
- `u-needs-review` — status `needs_review`, non-empty text, source `normal
  source`
- `u-hidden` — status `pending`, empty text, source `[HIDDEN] foo`
- `u-bracketed` — status `pending`, empty text, source `[ok]`
- `u-skip-text` — status `pending`, empty text, source `placeholder` (one
  of the fallback defaults of `TranslationSkipFilter`)
- `u-obsolete` — status `pending`, empty text, source `normal source`,
  `is_obsolete = 1`
- `u-wrong-lang` — status `pending`, empty text, source `normal source`,
  `project_language_id = 'pl-OTHER'`

Expected: `getUntranslatedIds('pl-1')` returns exactly
`{'u-pending', 'u-translating'}`.

### Group 2 — `filterUntranslatedIds`

Pass the full seed set's IDs as the input list (minus `u-wrong-lang`, which
we keep to verify the language filter still applies even when the ID is in
the `IN (…)` list). Assert the same exact output as Group 1:
`{'u-pending', 'u-translating'}`.

### Regression net

The existing full suite still runs. No existing test exercises
`getUntranslatedIds` / `filterUntranslatedIds` directly; the only indirect
callers are `TranslationBatchHelper.getUntranslatedUnitIds` /
`filterUntranslatedUnits`, which are pure pass-through. The widget tests
that use them (`handleTranslateAll` dialog) stub at the helper level.

## Risks

- **User expectation.** A user who has the mental model "Translate all
  means fill every empty row" will now see fewer units enqueued. The
  confirmation dialog count is honest, but the number will drop. The
  sidebar subtitle already shows this number, and the user expected
  matching here.
- **`reanalyzeAllStatuses` as the escape hatch.** Status-inconsistency
  rows that used to be scooped up by the old predicate are no longer
  translated in bulk. If the user hits a case where they genuinely want
  those units re-translated, the recovery path is: run
  `reanalyzeAllStatuses` (which flips the status back to `pending` where
  appropriate), then `Translate All`. This matches the schema's existing
  design intent.
- **`excludeSkipUnitsCondition` references `tu.*`.** Both queries now join
  `translation_units` as `tu`. `getUntranslatedIds` already does;
  `filterUntranslatedIds` gains the join. The `IN (…)` clause shifts from
  `unit_id IN (…)` to `tu.id IN (…)` accordingly.
