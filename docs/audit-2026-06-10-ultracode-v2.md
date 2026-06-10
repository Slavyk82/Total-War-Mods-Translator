# TWMT Deep Audit — 2026-06-10 (ultracode v2)

Multi-agent audit: 19 subsystem finders + 3 cross-cutting lenses → dedup → adversarial
severity-aware verification (high/critical: 3 diverse skeptic lenses + majority vote;
medium/low: single refuter) → synthesis. Clean-tree, full-codebase (~53.6k hand-written
Dart LOC), targeting *new* real bugs (prior audits ran 2026-06-09/10).

**28 confirmed findings** (out of 31 deduped candidates): **3 High, 10 Medium, 15 Low.**

> Note: the import_export finding pair is carried over from the first (rate-limited) run;
> the remaining 26 were found and verified in the chunked re-run.

---

## High

### Streaming UTF-8 decode aborts mid-translation on multibyte split (all 4 LLM providers)
`anthropic_provider.dart:190-191` · `deepseek_provider.dart:170-171` · `openai_provider.dart:183-184` · `gemini_provider.dart:172-173`
**Root cause (shared):** each provider's `translateStreaming` does `buffer += utf8.decode(chunk)` per raw Dio byte chunk. Default `allowMalformed:false` throws `FormatException` whenever a multibyte char (accent/Cyrillic/CJK/emoji) straddles a chunk boundary. The throw sits inside `await for` but outside the inner `jsonDecode` try/catch, so the outer catch yields one "Streaming error" and terminates the stream — aborting the translation and discarding already-produced text.
**Trigger:** routine — non-ASCII output is the norm for translation; any chunk boundary mid-character.
**Fix:** pipe the byte stream through `utf8.decoder` as a stream transformer (`stream.cast<List<int>>().transform(utf8.decoder)`) so partial sequences are buffered across chunks; `allowMalformed:true` is an inferior fallback. Apply identically to all four providers.
*(Anthropic & DeepSeek rated High; OpenAI & Gemini rated Medium — same root cause, fix together.)*

### Create-project dialog swallows init failure → orphaned empty project, hidden error
`create_project/create_project_dialog.dart:279-293` (caller), `302-370` (`_initializeProjectFiles`)
`_initializeProjectFiles` is `Future<void>` and handles every failure internally (empty RPFM schema path; `initService.initializeProject` returns `Err`) by only calling `setState(_errorMessage=…)` and returning — never throwing. The caller falls through to `Navigator.pop(projectId)`, so the dialog closes as success: error banner never seen + a `projects`/`project_language` row left with 0 units and no rollback.
**Fix:** make `_initializeProjectFiles` return failure (or rethrow); on failure do not invalidate/pop — roll back via `projectRepo.delete(projectId)` and surface the error, mirroring the already-fixed `create_game_translation_dialog`.

---

## Medium

### RPFM TSV importer drops every entry whose text is literally `"false"`
`tsv_localization_parser.dart:86-87` — `if (text == 'false') continue;` tests the **text** column (`parts[1]`), not the boolean tooltip column (`parts[2]`). Any source string equal to `"false"` is dropped on import (this is the primary `ILocalizationParser`, DI `file_service_locator.dart:56`). **Fix:** remove the check entirely.

### Within-file duplicate key for a new unit errors out and drops 2nd+ occurrence
`import_executor.dart:346-356` — For a not-yet-in-DB key appearing twice: row 1 creates unit+version; row 2 is routed to conflict-resolution for a version that doesn't exist, fails "Unresolved conflict," value lost. **Fix:** track keys created/updated during the run; treat a repeat key as deterministic in-run update or counted skip.

### Inspector drops unsaved target edit when the edited row is filtered out
`editor_inspector_panel.dart:187-228, 235-248` — Type a translation (`_targetDirty=true`, `_boundUnitId=A`) without blurring, then filter A out. `_rebindIfNeeded` hits `if (idx<0) return;` without flushing; later `_flushDirtyIfNeeded` finds `indexWhere(A)==-1` and returns — edit never persisted. **Fix:** resolve previous row's persisted text from the unfiltered source, or flush eagerly on bound-id change/disappearance.

### Compilation can silently produce an empty (translation-less) `.pack` and report success
`rpfm_pack_operations_mixin.dart:110-265` — When both `tsvFiles` and `locFiles` are empty, neither add-branch runs; the empty pack passes the size check and returns `Ok`. `generatePack` never aborts on `totalFilesGenerated==0`, so an empty high-load-order pack ships marked Generated. **Fix:** return `Err` + cleanup on empty input; abort `generatePack` when `totalFilesGenerated==0`.

### Glossary usage-count increment bumps `updated_at` → perpetual DeepL re-sync
`glossary_repository.dart:415-426` — `incrementUsageCount()` writes `updated_at=now` on every match (hot path); `doesMappingNeedResync()` compares `MAX(updated_at) > syncedAt`, so after the first matched term every translation reports the DeepL glossary as needing resync (API churn, limited slot consumption). **Fix:** don't touch `updated_at` in `incrementUsageCount`, or add a dedicated `content_updated_at`.

### Regex/literal substring search: duplicate rows + unstable pagination
`regex_query_builder.dart:81-101` — `LEFT JOIN translation_versions` with no `DISTINCT`/`GROUP BY`/`ORDER BY`. Units with N versions yield N duplicates; over-fetch + `skip(offset)` (`search_providers.dart:153-156`) drops/repeats rows across pages. **Fix:** add `ORDER BY tu.id` + `DISTINCT`/`GROUP BY tu.id` (or drop the version join for source-only searches).

### SQL-injection keyword filter rejects common English search terms
`fts_query_builder.dart:482-483` — Throws on `\b(DROP|DELETE|UPDATE|INSERT|ALTER|CREATE|EXEC|EXECUTE)\b`. MATCH value is already a quote-doubled single-quoted literal (injection impossible), but searching "update"/"create"/"delete" throws `ArgumentError` → "Unexpected error during search," failing the whole search. **Fix:** drop the English-word/UNION/tautology blocklist for FTS MATCH values.

### findFuzzyMatches under-retrieves: combined-score candidates dropped by Levenshtein-only prefilter
`tm_matching_service.dart:288-292` — Passes `minConfidence:minSimilarity` to `findMatches`, whose prefilter uses Levenshtein only. A candidate with Levenshtein 0.80 / JW 0.95 / token 0.95 (combined 0.89 ≥ 0.85) is dropped before the 3-algorithm rescore. Isolate paths widen with `minSimilarity-0.1`; the sync path (`findBestMatch:594`) does not. **Fix:** widen the prefilter to `(minSimilarity-0.1).clamp(...)`.

### Stale steamcmd cached credentials → unrecoverable auth error (no Steam Guard retry)
`workshop_publish_service_impl.dart:151-234` — When the cached session is invalidated server-side, the command builds `+login <user> +quit` with no password/Guard code, fails, returns `SteamAuthenticationException` (hard, non-retryable; nothing deletes `config.vdf`/`ssfn`). User permanently stuck on the failing cached path. **Fix:** on cached-login failure, invalidate the cached-credentials assumption so the flow falls back to full `+login user password code`.

### Game-translation project stores raw TW pack code as `sourceLanguageCode`
`create_game_translation_dialog.dart:187` — Persists `sourcePack.languageCode` (raw `cn`/`jp`/`kr`/`tw`/`cz`/`br`) instead of the ISO/DB code, though the wizard uses `mapPackCodeToDbCode` everywhere else. Downstream (`editor_inspector_panel.dart:384`, `tm_crud_service.dart:95`) can't resolve the language id → TM lookups fail. **Fix:** store `mapPackCodeToDbCode(sourcePack.languageCode)`.

---

## Low

### TSV importers strip significant leading/trailing whitespace (two parsers)
`tsv_localization_parser.dart:80-84` · `tsv_parser.dart:82-85` (stream variant 168-171) — Both `.trim()` the value before storing as sourceText (`project_initialization_service_impl.dart:230`). TW strings often carry significant edge spaces; the binary `.loc` path doesn't trim, so binary vs TSV imports diverge and re-export silently alters strings. `tsv_localization_parser` also drops whitespace-only values. **Fix:** unescape the raw joined value without `.trim()` (strip only trailing `\r`).

### JSON import yields zero rows on object root
`import_file_reader.dart:53-63` — Only `data is List` handled; a Map root leaves rows empty and returns `Ok` with `totalRows=0` ("successful import of nothing"). **Fix:** handle wrapped-array/key→object shapes, else `Err(Unsupported JSON structure)`.

### upsertBatch REPLACEs intra-batch duplicates → lost translations + over-count
`translation_memory_batch_mixin.dart:126-139` — Existing-row prefetch checks only the DB. Two batch entries sharing `(source_hash, target_language_id)` but new to the DB both take INSERT/`ConflictAlgorithm.replace`; the second deletes the first, yet `processedCount` increments for both. `TextNormalizer` collapses `Attack`/`attack` to one hash. **Fix:** add a first-wins `Set<String>` of `'<hash>:<langId>'` keys (as `bulkImportTmxEntries` already does).

### Batch cancellation reports in-flight items as "failed" not "cancelled"
`workshop_publish_service_impl.dart:814-825` — On cancel, the reconciliation loop reports uncompleted items via `onItemComplete(Err(...))` → status `failed`. The notifier only re-labels still-`pending`/`inProgress` items as cancelled, so cancelled items show as failed. **Fix:** when `_isCancelled`, report a cancelled result.

### Extraction temp directory leaked when pack yields no TSV loc files
`mod_update_analysis_service.dart:253-255` — `_extractPackUnits` early-returns `Ok([])` when `extractedFiles` is empty, bypassing the cleanup that deletes `extraction.outputDirectory`. Each re-scan of such a pack leaks one `rpfm_extract_tsv_*` dir. **Fix:** delete `outputDirectory` in the `locFiles.isEmpty` branch (or try/finally).

### FTS "rebuild" command fails on contentless `translation_versions_fts`
`migration_fix_escaped_newlines.dart:92-105` (line 95) — `INSERT INTO …_fts(…_fts) VALUES('rebuild')` is invalid on a contentless FTS5 table; always throws, swallowed as "FTS rebuild skipped." Impact limited (trigger + priority-230 migration reconcile). **Fix:** explicit `DELETE`+`INSERT … SELECT` (as `ValidationIssuesJsonDataMigration` does), or drop `_rebuildFtsIndex()`.

### `GlossaryServiceImpl.checkConsistency` ignores per-entry `case_sensitive`
`glossary_service_impl.dart:549-559` — Always compares case-insensitively, contradicting `GlossaryMatchingService.checkConsistency:191-193`. No production callers yet, but divergent/incorrect. **Fix:** honor `entry.caseSensitive` or delegate to `_matchingService.checkConsistency`.

### DeepL TSV export can emit duplicate source terms → DeepL rejects whole glossary
`glossary_deepl_service.dart:268-279` — `_convertToDeepLFormat` writes one line per entry with no source-term dedup; the DB UNIQUE includes `case_sensitive`, so two entries with the same trimmed source emit identical lines → DeepL HTTP 400, failing `createDeepLGlossary` for the whole glossary. **Fix:** dedup by trimmed source term; skip empty source/target.

### `searchTranslationMemory` silently ignores `sourceLanguage` filter
`search_service_impl.dart:162-189` — Accepts `String? sourceLanguage` (documented) but never uses it; results span all source languages. **Fix:** thread it into the query (`tm.source_language = …`) or remove the misleading parameter.

### LlmCustomRules mutations never invalidate `enabledRulesCountProvider` → stale badge
`llm_custom_rules_providers.dart:30-107` & `110-114` — Mutations call only `ref.invalidateSelf()`; the count provider doesn't watch the rules provider, so the accordion active-count badge goes stale after add/delete/toggle. Sibling `IgnoredSourceTexts` invalidates both. **Fix:** add `ref.invalidate(enabledRulesCountProvider)` to each mutation.

### Concurrent DeepL glossary sync: orphaned server glossaries + duplicate mappings
`deepl_glossary_sync_service.dart:41-188` — `ensureGlossarySynced()` is an unguarded check-then-act with external side effects. In parallel LLM batches, several chunks see `existingMapping==null` concurrently and each calls `createDeepLGlossary()` + `insertDeepLMapping()` → N-1 orphaned DeepL glossaries (limited slots) + duplicate mappings. **Fix:** serialize per `(glossaryId, source, target)` via in-flight future map / async mutex, or UNIQUE constraint + reconcile-on-conflict.

### Pack-import grid captures theme tokens once → stale colors after theme switch
`pack_import_dialog.dart:85-99` — `_PackImportDataSource` captures `context.tokens` by value at preview load; toggling theme rebuilds chrome but not grid rows. **Fix:** refresh the data source on theme change, or resolve colors from the cell `BuildContext`.

---

## Themes & systemic risks

1. **Encoding & data fidelity on import-export is the highest-leverage area.** The same class of bug recurs independently: four LLM providers split UTF-8 the same wrong way; two TSV parsers trim significant whitespace the same way; the binary `.loc` path disagrees with both TSV paths. A shared, tested streaming-decode helper and a single "no-trim, preserve-verbatim" TSV value contract would close most of these at once.
2. **Failure paths that report success / leave orphans.** Create-project swallows init errors and orphans a row; compilation ships an empty pack as "Generated"; concurrent DeepL sync orphans server glossaries; Steam cancel mislabels items. The fixed `create_game_translation_dialog` (throw → catch → rollback → surface) is the correct template for all create/generate flows.
3. **Two divergent implementations of the same logic.** `checkConsistency` (impl vs matching service), the fuzzy-match prefilter (sync vs isolate), and dedup (present in `bulkImportTmxEntries`, absent in `upsertBatch`) have already drifted. Consolidate onto one implementation per concern (delegate, don't reimplement).
4. **`updated_at` overloading & reactive desync.** Mixing usage-stat writes into a content-change timestamp drives perpetual DeepL resync; missing cross-provider invalidation leaves a stale UI badge. Separate the concerns.
5. **SQL hygiene in search.** Missing `ORDER BY`/`DISTINCT` and an overzealous injection blocklist both indicate the search query builders warrant a focused correctness pass.
