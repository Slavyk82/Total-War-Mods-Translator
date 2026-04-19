# Validation Issue Type — Structured Persistence + Forced Rescan

**Date:** 2026-04-19
**Status:** Approved, ready for planning
**Scope:** Translation validation persistence layer, Validation Review screen, application bootstrap

---

## Problem

In the **Validation Review** screen, the **Issue Type** column is supposed to show the rule that triggered each validation flag. In reality it always shows `validation_issue` and the **Description** always shows `Translation needs review`, regardless of what actually failed. Every row looks identical.

### Root cause

- `ValidationPersistenceHandler.validateAndSave` and the rescan action both persist validation issues as `jsonEncode(result.allMessages)` — a JSON array of plain strings with no rule identity attached.
- `ValidationError` (the per-check output of `ValidationServiceImpl`) has no `rule` field. The rule that produced a given message is discarded at the boundary.
- The reader `_parseValidationIssues` in `editor_actions_validation.dart` tries to regex-match `{type:…, severity:…, description:…}` against the stored payload. That pattern never matches a JSON string array, so every row falls through to the generic fallback `{type: 'validation_issue', description: 'Translation needs review'}`.

Restoring the information means persisting the rule alongside the message, end-to-end.

---

## Approach

Adopt **structured persistence** (no heuristic back-inference from message text):

1. Introduce an explicit `ValidationRule` identifier and carry it through `ValidationError` → `ValidationResult` → persistence → UI.
2. Store each issue as a JSON object `{rule, severity, message}` in `translation_versions.validation_issues`.
3. Because old rows are irrecoverable (the rule was never stored), force a one-shot rescan of all existing `translation_versions` on next launch, with a user-facing progress UI and resilient resume-on-interruption behaviour.

---

## 1. Rule identifier

### 1.1 New enum

Create `lib/services/translation/models/validation_rule.dart`:

```dart
enum ValidationRule {
  completeness,
  length,
  variables,
  markup,
  encoding,
  glossary,
  security,
  truncation,
  repeatedWord,
  endPunctuation,
  numbers,
}
```

One value per check in `ValidationServiceImpl`. The three sub-checks of `checkCommonMistakes` are split into `repeatedWord`, `endPunctuation`, `numbers` for column granularity.

### 1.2 Humanised labels

Add `extension ValidationRuleDisplay on ValidationRule` with a `label` getter returning a short English title shown in the column:

| Rule | Label |
|---|---|
| `completeness` | Completeness |
| `length` | Length |
| `variables` | Variables |
| `markup` | Markup tags |
| `encoding` | Encoding |
| `glossary` | Glossary |
| `security` | Security |
| `truncation` | Truncation |
| `repeatedWord` | Repeated word |
| `endPunctuation` | Punctuation |
| `numbers` | Numbers |

### 1.3 Wire into `ValidationError`

`ValidationError` (`lib/services/translation/models/translation_exceptions.dart`) gains a non-nullable `rule` field. Every `return ValidationError(...)` site in `ValidationServiceImpl` passes its rule. Constructor default is disallowed — the rule must be explicit at every call site.

---

## 2. Propagation through `ValidationResult`

Today `ValidationResult` exposes only `errors: List<String>` and `warnings: List<String>`. To keep rule identity, we add a parallel structured view.

### 2.1 New structured entry

Extend `ValidationResult` (`lib/models/common/validation_result.dart`) with a new field:

```dart
final List<ValidationIssueEntry> issues;
```

where `ValidationIssueEntry` is a small value object:

```dart
class ValidationIssueEntry {
  final ValidationRule rule;
  final ValidationSeverity severity;
  final String message;
}
```

`errors` / `warnings` / `allMessages` remain for backward compatibility but are derived from `issues` (kept consistent via the factory / copyWith).

### 2.2 `ValidationServiceImpl` updates

`_addError` becomes `_appendIssue` and builds `ValidationIssueEntry` values directly from `ValidationError`. The final `ValidationResult` carries the full structured list.

### 2.3 `ValidationPersistenceHandler` updates

`ValidationPersistenceHandler.validateAndSave` replaces

```dart
validationIssuesJson = jsonEncode(result.allMessages);
```

with

```dart
validationIssuesJson = jsonEncode(
  result.issues.map((i) => {
    'rule': i.rule.name,
    'severity': i.severity.name,
    'message': i.message,
  }).toList(),
);
```

Same change in `EditorActionsValidation.handleRescanValidation` at the equivalent write site.

---

## 3. Reader side — Validation Review screen

### 3.1 Replace the regex parser

In `editor_actions_validation.dart`, `_parseValidationIssues` is rewritten to `jsonDecode` the payload and map each entry to `_StoredValidationIssue(type: rule, severity, description: message)`. The regex branch and the generic fallback `'Translation needs review'` are both removed.

If decoding fails (the payload is unexpectedly malformed despite the migration — e.g. a row written by a pre-structured build that escaped the migration), log a warning and surface the row with `rule = 'legacy'` rather than silently hiding it.

### 3.2 DataGrid

`ValidationReviewDataSource._buildIssueTypeCell` receives the `rule` string. A small mapping function (owned by the UI layer and reading the `ValidationRule.label` extension) produces the humanised label shown in the column. Existing severity colouring is unchanged.

`_StoredValidationIssue.description` now contains the actual validator message, so the **Description** column finally varies per row.

---

## 4. Schema migration + forced rescan

### 4.1 Schema column

Add `validation_schema_version INTEGER NOT NULL DEFAULT 0` to `translation_versions`. Current version = `1`. A new DB migration file handles the `ALTER TABLE`. The column is owned by the version row, not by the project — this keeps resume granularity at the row level.

### 4.2 `ValidationRescanGate` widget

New widget mounted in `main.dart` as a gate between app bootstrap and the root router. Responsibilities:

1. On first frame, query `COUNT(*) FROM translation_versions WHERE validation_schema_version < 1 AND translated_text IS NOT NULL`.
2. If `0`, render nothing and forward straight to the app.
3. Otherwise:
   1. Run a **calibration pass**: validate 20 sample rows to measure ms/unit on the current machine. Do not persist anything from calibration.
   2. Compute `estimatedDuration = remaining * msPerUnit`.
   3. Detect whether this is a first run or a resume:
      - First run: no row has `validation_schema_version = 1` yet.
      - Resume: at least one row is already at `1`.
   4. Show the appropriate blocking `AlertDialog` (see §6).
4. On the user's confirmation, open the progress dialog and start the scan loop.

### 4.3 Scan loop

```
while true:
  page = getLegacyValidationPage(limit: 500)   // versions with schema_version < 1
  if page empty: break
  units = unitRepo.getByIds(page.map(v -> v.unitId).toSet())
  for each version in page:
    result = validationService.validateTranslation(...)
    newStatus = needsReview if result.hasErrors || result.hasWarnings else translated
    newIssuesJson = jsonEncode(result.issues)    // new structured format
    accumulate update
    if accumulator.size >= 100:
      updateValidationBatch(accumulator, schemaVersion: 1)
      accumulator.clear()
      updateEta()
  flush accumulator if non-empty
```

Each `updateValidationBatch` commit **also writes `validation_schema_version = 1`** on the rows it updated. This is the atomic unit of forward progress: a crash mid-batch at worst loses up to 100 units of work, which are simply re-picked on the next run.

### 4.4 ETA computation

Maintain a moving average of `elapsed_ms_per_unit` over the last 50 units. The displayed ETA is `movingAverage * unitsRemaining`, refreshed on each 100-unit commit. The initial estimate uses the calibration pass mean.

### 4.5 Non-cancellable

The progress dialog exposes no Cancel button. The user can still close the window or kill the app, which pauses the process; resume is automatic on next launch. A footer note (§6) makes this explicit.

### 4.6 Completion

When the scan loop exits cleanly, the gate closes its dialogs, shows a transient success toast via `FluentToast.success`, and forwards to the normal router. Total elapsed wall time is included in the toast text.

---

## 5. Repository surface

Additions to `TranslationVersionRepository`:

- `Future<Result<int, _>> countLegacyValidationRows()` — versions where `validation_schema_version < 1 AND translated_text IS NOT NULL`.
- `Future<Result<int, _>> countMigratedValidationRows()` — versions where `validation_schema_version = 1` (used to detect resume).
- `Future<Result<List<TranslationVersion>, _>> getLegacyValidationPage({int limit})` — returns the next page, ordered by `id` for deterministic paging.
- Extension of the existing `updateValidationBatch` signature so it can bump `validation_schema_version` atomically alongside `status` and `validation_issues`.

---

## 6. UI strings (English, authoritative wording)

Placeholders below use `{total}`, `{done}`, `{remaining}` for unit counts and `{eta}` for the duration string (e.g. `3m 20s`, `1h 5m`).

### First run dialog

> **Validation data update required**
>
> This release uses a new, richer format for translation validation diagnostics. All existing translations need to be rescanned once to benefit from it.
>
> **{total} units to rescan • Estimated: ~{eta}**
>
> This will only run once. Do not close the app until it completes — if interrupted, the update will resume on next launch.
>
> `[ Start rescan ]`

### Resume dialog

> **Resuming validation update**
>
> A previous update was interrupted. **{done} of {total} units already processed. Remaining: {remaining} units • Estimated: ~{eta}.**
>
> `[ Continue ]`

### Progress dialog

- Title: `Updating validation data`
- Body: `Rescanned {done} of {total} — ETA {mm:ss}`
- Progress bar: determinate, `value = done / total`
- Footer: `Closing the app will pause the update; it will resume on next launch.`

### Completion toast

> `Validation data update complete ({total} units processed in {mm:ss}).`

Numbers use thousands separators (`12,000`). Durations omit leading zero units (`~3m 20s`, not `~0h 3m 20s`).

---

## 7. Testing

### Unit
- `ValidationServiceImpl`: each `ValidationError` carries the expected `ValidationRule` (one focused test per check — completeness, length, variables/missing, variables/extra, markup/count, markup/balance, encoding/replacement, encoding/control, glossary, security/sql, security/script, truncation/ellipsis, truncation/short, commonMistakes/repeatedWord, commonMistakes/endPunctuation, commonMistakes/numbers).
- `ValidationResult`: `errors`, `warnings`, `allMessages` stay consistent with `issues`.
- `ValidationPersistenceHandler`: written `validation_issues` payload round-trips to an identical `List<ValidationIssueEntry>`.
- `_parseValidationIssues` (or its replacement): decodes the new structured JSON; decoding failure surfaces a `legacy` rule rather than throwing.

### Widget
- `ValidationReviewDataSource` renders the humanised rule label (e.g. `Variables`, `Markup tags`) and the real validator message.
- `ValidationRescanGate`:
  - Zero legacy rows → forwards immediately, no dialog shown.
  - Non-zero first-run → shows first-run dialog with the correct counts.
  - Non-zero with some already at version 1 → shows resume dialog.
  - Progress dialog updates ETA as the scan progresses (mock validation service, simulate paging).
  - No Cancel button exposed.

### Integration
- Migration from a DB containing legacy `List<String>` payloads: after the gate completes, all rows have `validation_schema_version = 1`, `validation_issues` is structured JSON, and the Validation Review screen displays per-rule issue types.
- Simulated interruption: kill the scan after N commits; on next boot, gate shows resume dialog with correct residual count and completes the remaining rows.

---

## 8. Out of scope (explicit non-goals)

- No retroactive reconstruction of the original rule for rows that were stored in the legacy format — the rescan produces fresh, accurate data, so inference is unnecessary.
- No new validation rules or rule tuning. This spec only carries existing rules through to the UI.
- No change to the Validation Review screen's selection / accept / reject / edit flows.
- No changes to validation for non-translated versions.

---

## 9. Risk log

| Risk | Mitigation |
|---|---|
| Rescan takes much longer than estimated on large DBs | Paged scan (500 at a time), 100-unit commit, moving-average ETA refreshed on every batch, calibration pass before the first estimate |
| Crash mid-batch | Worst case loses one in-flight batch (≤100 units). `validation_schema_version` is updated only as part of the successful batch commit |
| User kills the app during the scan | Expected and safe — resume on next boot, dialog text explicitly tells the user this |
| New rule added later without a `ValidationRule` value | Enum is the single source of truth; the compiler will force wiring — no silent regression |
| Post-migration writer regression producing legacy-format payloads | Reader handles decode failure by surfacing `rule = 'legacy'` with the raw string as description, keeping the UI functional and the bug visible |
