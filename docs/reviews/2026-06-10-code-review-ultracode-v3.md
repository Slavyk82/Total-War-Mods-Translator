# Revue de code complète (v3) — Total War Mods Translator

Date : 2026-06-10

## Méthodologie

Audit multi-agents « ultracode » : 19 relecteurs indépendants (16 zones couvrant l'intégralité de `lib/` — ~800 fichiers — plus 3 lentilles transversales : concurrence, cycle de vie des ressources, intégrité des données), suivis d'une vérification adversariale de chaque constat par 2 sceptiques indépendants (lecture directe du code, des appelants et du schéma), avec un 3e agent en départage en cas de désaccord. 156 agents au total. 71 constats bruts → 65 après dédoublonnage → **56 confirmés**, 9 réfutés. Les descriptions des constats sont conservées dans la langue de travail des agents (anglais) ; le cadrage est en français.

## Résumé exécutif

Troisième passe après les revues des 7 et 9 juin (46 défauts corrigés). Le stock de défauts reste substantiel mais change de nature : un seul constat critique (l'import TMX est entièrement cassé), et le risque se déplace vers des **familles systémiques** que les passes précédentes avaient déjà effleurées sans les épuiser :

1. **`Result` ignorés → faux succès silencieux** (récidive du thème n°3 de la v2). Suppression d'entrée de glossaire, `setProjects` de compilation, sauvegarde du Workshop ID (deux variantes), rescan de validation qui affiche un toast de succès sur erreur, export TMX qui ignore les options choisies : l'utilisateur reçoit une confirmation alors que rien n'a été écrit.

2. **Recherche FTS5 structurellement défaillante.** Le classement est inversé (`ORDER BY rank DESC` sur bm25 négatif : les meilleurs résultats sont coupés par le `LIMIT`), les requêtes de matching TM ne sont pas quotées (toute ponctuation lève une erreur de syntaxe FTS5 et casse le fuzzy matching), et le filtre de colonne ne s'applique qu'au premier terme `OR`.

3. **Mémoire de traduction / TMX.** L'import TMX stocke des codes `xml:lang` bruts dans des colonnes FK numériques (échec systématique — critique), crashe en plein import sur segments dupliqués (TM partiellement importée), et le rebuild regroupe par texte source seul, affectant des traductions à la mauvaise langue cible.

4. **Cycle de vie Riverpod.** Usage de `ref`/`state` après dispose (file de mises à jour de mods abandonnée avec `StateError`, providers de backup et de maintenance), écran d'export par lots qui réinitialise l'état sans annuler l'export en cours, pile undo/redo dans un provider `autoDispose` uniquement lu via `ref.read` (l'undo ne peut jamais aboutir).

5. **Annulation et processus externes (steamcmd/RPFM).** Le code de sortie -1 d'un kill est confondu avec le timeout, le bouton Stop déclenche 3 retries puis marque le batch `failed` au lieu de `cancelled`, le `CancelToken` est perdu sur le chemin DeepL+glossaire, et un échec de `pack add` laisse un `.pack` partiel dans le répertoire `data` du jeu.

6. **Migrations DB à garde défaillante.** `DeepSeekChatRestoreMigration` teste l'état vivant de la ligne au lieu d'un registre de migrations et ré-active le modèle à chaque démarrage contre la volonté de l'utilisateur ; insertion de `gpt-5.5` avec `is_default=1` contournant le trigger d'unicité ; `ALTER` non atomiques dont la reprise perd `published_at`.

Chaque constat ci-dessous a survécu à la vérification adversariale ; les candidats dont une prémisse porteuse s'effondrait ont été écartés (9, listés en annexe — dont un réfuté par test empirique du mapping Unicode de la VM Dart, et un autre parce que le chemin d'appel est mort dans l'UI actuelle).

## Décompte par sévérité

| Sévérité | Nombre |
|----------|--------|
| Critique | 1 |
| Élevé | 9 |
| Moyen | 30 |
| Faible | 16 |

## Critique (1)

### TMX import stores raw xml:lang codes in FK language-ID columns, so every TMX import fails (or writes invisible entries)

fichier `lib/services/translation_memory/tmx_service.dart:508` · source svc-glossary-tm, xcut-data-integrity · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : persistTmxEntries() builds TranslationMemoryEntry with sourceLanguageId/targetLanguageId taken verbatim from the TMX tuv xml:lang attributes (e.g. 'en', 'fr-FR'). But translation_memory.source_language_id/target_language_id are FOREIGN KEYs to languages(id), whose ids are in 'lang_xx' form (schema.sql seeds 'lang_en', 'lang_fr'; exportToTmx in tm_import_export_service.dart line 149 even calls stripLanguagePrefix on the stored id, confirming the 'lang_' format). DatabaseService._onConfigure executes 'PRAGMA foreign_keys = ON', so the txn.insert inside bulkImportTmxEntries (translation_memory_batch_mixin.dart line 242, ConflictAlgorithm.abort) hits a FK violation for every new row, the chunk transaction rolls back and importFromTmx always returns Err — the TMX import feature (including re-importing TWMT's own exports, which write bare codes like 'fr' in xml:lang) can never succeed. No caller maps the codes: UI → tm_providers.importFromTmx → TranslationMemoryServiceImpl → TmImportExportService → TmxService.persistTmxEntries with raw TmxEntry languages. Were FK enforcement ever off, the rows would instead be orphans invisible to all lookups, which resolve language ids via LanguageRepository.getByCode ('lang_xx').

```
sourceLanguageId: entry.sourceLanguage,
          targetLanguageId: entry.targetLanguage,
```

## Élevé (9)

### Stop button triggers up to 3 pointless retries and marks the batch 'failed' instead of 'cancelled'

fichier `lib/services/translation/handlers/llm_retry_handler.dart:51` · source svc-translation

**Problème** : When the user clicks Stop, BatchProgressManager.stop() cancels the Dio token of the in-flight request. The provider maps DioExceptionType.cancel to the default LlmNetworkException (verified in anthropic_provider.dart:643 — there is no DioExceptionType.cancel branch), and LlmServiceImpl passes the error through unchanged. translateWithRetry then classifies this user-initiated cancellation as retryable and re-issues the request up to 3 times with 2s/4s/8s backoff (~14s total), never checking the cancellation token (it receives dioCancelToken but never consults isCancelled between attempts). After retries are exhausted the Err propagates to TranslationErrorRecovery._handleFatalError, which throws TranslationOrchestrationException (not CancelledException), so in the single-batch path the orchestrator's generic catch runs _handleErrorInternal: the user-stopped batch is persisted as status=failed with errorMessage and retryCount incremented, and a BatchFailedEvent is published — even though the user deliberately stopped it and stop() already published BatchCancelledEvent.

```
final isRetryable = error is LlmServerException ||
          error is LlmRateLimitException ||
          error is LlmNetworkException;
```

### TM rebuild groups entries by source text only, assigning translations to the wrong target language

fichier `lib/services/translation_memory/tm_maintenance_service.dart:122` · source svc-glossary-tm · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : rebuildFromTranslations() collects rows into entriesToAdd (sourceText, targetText) and records the language in targetLanguageMap keyed ONLY by sourceText: 'targetLanguageMap[entry.sourceText] = targetLanguageId'. When the same source_text was LLM-translated into two or more target languages (a normal multi-language project; getMissingTmTranslations ORDER BY tu.source_text guarantees such rows land adjacent in the same 500-row batch), the map entry is overwritten by the last language. At grouping time (line 134: 'final langId = targetLanguageMap[entry.sourceText]!;') BOTH translations are grouped under that one language and passed to addTranslationsBatch with that language code. Because both rows then share the same sourceHash+target_language_id, upsertBatch's INSERT OR REPLACE makes the last one win: e.g. the French translation is stored as the German TM entry's translated_text, and the French TM entry is never created — silent cross-language corruption of the translation memory during rebuild.

```
entriesToAdd.add((sourceText: sourceText, targetText: targetText));
            targetLanguageMap[sourceText] = targetLanguageId;
```

### FTS5 search results ordered worst-first: ORDER BY rank DESC inverts bm25 relevance

fichier `lib/services/search/utils/fts_query_builder.dart:60` · source svc-infra

**Problème** : All three FTS5 queries (translation units line 60, translation versions line 131, translation memory line 188) sort with 'ORDER BY rank DESC'. In SQLite FTS5 the rank column is bm25(), which returns NEGATIVE values where a smaller (more negative) value means a BETTER match; the idiomatic ordering is 'ORDER BY rank' (ascending). With DESC the least relevant matches come first, and because every query has a LIMIT clause (default 100, max 1000), whenever a search term matches more rows than the limit the MOST relevant rows are the ones cut off and never returned to the user. The same inversion propagates to SearchServiceImpl.searchAll (lib/services/search/search_service_impl.dart line 305), which copies the raw negative rank into relevanceScore and sorts descending ('allResults.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore))'), again putting the worst cross-source matches first before truncating with take(limit). Trigger: any FTS search whose term matches more rows than the limit (common terms like unit names in large mods).

```
WHERE translation_units_fts MATCH '$sanitizedQuery'\n      ${filterClause.isNotEmpty ? 'AND $filterClause' : ''}\n      ORDER BY rank DESC\n      $limitClause
```

### TMX import crashes mid-import on duplicate source segments (UNIQUE violation), leaving partially imported TM

fichier `lib/repositories/mixins/translation_memory_batch_mixin.dart:242` · source repositories, xcut-data-integrity

**Problème** : bulkImportTmxEntries pre-computes existingIds from a SELECT, then inserts every entry not found there with ConflictAlgorithm.abort. The lookup map is never updated as inserts happen inside the chunk, so when a TMX file contains two entries with the same (source_hash, target_language_id) within one 500-entry chunk (duplicate source segments are common in real TMX exports, and distinct sources can collide after _normalizer.normalize() in tmx_service.dart:502-503), both take the INSERT path. The second insert violates UNIQUE(source_hash, target_language_id) (lib/database/schema.sql:257), the chunk transaction rolls back, and the whole import returns Err — but earlier chunks were committed in separate per-chunk transactions, so the user gets 'Failed to persist TMX entries' with a silently half-imported translation memory. No upstream dedupe exists in tmx_service.dart. The sibling method upsertBatch (line 136) avoids this by using ConflictAlgorithm.replace.

```
await txn.insert(
  tableName,
  toMap(entry),
  conflictAlgorithm: ConflictAlgorithm.abort,
);
```

### findMatches builds unquoted FTS5 query: any source text with punctuation (period, apostrophe, hyphen) throws an FTS5 syntax error, breaking fuzzy TM matching

fichier `lib/repositories/mixins/translation_memory_fts_mixin.dart:203` · source repositories, xcut-data-integrity

**Problème** : _buildFts5Query splits the source text on whitespace, strips only double quotes, and joins the bare words with ' OR ' for the MATCH clause at line 62. FTS5 barewords may only contain alphanumerics/underscore/codepoints>=127, so ordinary game text fails: 'Increases melee attack.' produces MATCH 'increases OR melee OR attack.' -> 'fts5: syntax error near "."'; "don't" -> syntax error near "'"; 'well-trained' -> 'no such column: trained' (verified empirically against SQLite FTS5). The exception turns into Err from executeQuery, so TranslationMemoryRepository.findMatches fails for most natural-language sentences — tm_matching_service.dart:294 converts it to a TmLookupException (errors the lookup flow) and the batch path at line 403 silently records 'no match', so fuzzy TM matching effectively never works for punctuated text. The sister method _buildFts5SearchQuery (line 235) correctly strips specials and quotes each token ('"$w"*'); _buildFts5Query does neither, and its fallback at line 199 returns the raw unescaped text.

```
// Build OR query: word1 OR word2 OR word3
return words.join(' OR ');
```

### startUpdates loop uses ref/state after notifier disposal — remaining queued updates silently abandoned with unhandled StateError

fichier `lib/providers/mods/mod_update_provider.dart:156` · source providers-models

**Problème** : ModUpdateQueue is an autoDispose @riverpod notifier. Its only watcher is ModUpdateDialog (lib/features/mods/widgets/mod_update_dialog.dart:17), which offers a 'Hide' button while updates are running (line 100-104: label is t.mods.actions.hide when !allComplete, onTap pops the dialog). startUpdates() is invoked fire-and-forget from whats_new_dialog.dart:101 ('ref.read(modUpdateQueueProvider.notifier).startUpdates();' — not awaited). Trigger: queue 2+ mods via 'Update All', then click 'Hide' while mod #1 is downloading. The dialog pops, the last listener is removed, and the autoDispose notifier is disposed. The in-flight _updateProject finishes (its helpers are ref.mounted-guarded), but the for-loop in startUpdates then proceeds to mod #2: it reads the `state` getter (line 156) and _updateProject immediately calls ref.read(steamCmdServiceProvider) etc. (lines 168-171) before its try block — both throw StateError on a disposed notifier/ref. Because startUpdates() was never awaited, the StateError is an unhandled async exception, and every remaining queued mod update is silently never performed, while the user (who pressed 'Hide', not 'Cancel') believes updates continue in the background. The file's own comments show dispose-mid-download is an anticipated scenario (_updateStatus: 'these helpers run after long awaits... Writing state then throws StateError'), but the loop in startUpdates and the pre-try ref.read calls in _updateProject were left unguarded (no `if (!ref.mounted) break;`).

```
for (final updateInfo in pendingProjects) {
      if (state[updateInfo.projectId]?.status == ModUpdateStatus.cancelled) {
        continue;
      }
      await _runExclusive(() => _updateProject(updateInfo.projectId));
    }
```

### Leaving batch export screen resets provider state without cancelling the running export

fichier `lib/features/projects/screens/batch_pack_export_screen.dart:52` · source feat-projects-home

**Problème** : The leave-confirmation dialog explicitly promises 'The export will be cancelled' (projects.dialogs.confirmLeave.message), but neither _handleBack (lines 79-87) nor dispose() ever calls `cancel()`. dispose() instead calls `reset()`, which replaces the state with a fresh BatchPackExportState while the async `exportBatch` loop in BatchPackExportNotifier is still awaiting `exportToPack`. Consequences: (1) the export keeps running in the background, silently writing .pack files into the game data folder with no UI and no way to stop it; (2) the running loop's subsequent `state.copyWith(...)` writes resurrect inconsistent state on top of the reset (totalProjects=0 while completedProjects climbs, projectStatuses shrunk to one entry); (3) because reset() clears `isExporting`, the `if (state.isExporting) return` re-entry guard in exportBatch is defeated, so starting a second batch export while the orphaned one is still running launches two concurrent loops that interleave state writes and can export the same project's pack file concurrently.

```
@override
  void dispose() {
    _elapsedTimer?.cancel();
    ref.read(batchPackExportProvider.notifier).reset();
    super.dispose();
  }
```

### Glossary entry delete ignores Result and never invalidates providers — false success toast and stale grid

fichier `lib/features/glossary/providers/glossary_providers.dart:307` · source feat-data-misc

**Problème** : GlossaryService.deleteEntry returns Result<void, GlossaryException> and never throws (glossary_service_impl.dart:367-385 wraps all failures in Err). GlossaryEntryEditor.delete awaits it and discards the Result, and unlike save() it performs no invalidation of glossaryEntriesProvider / glossarySearchResultsProvider / glossaryStatisticsProvider. The only caller, GlossaryDataGrid._deleteEntry (lib/features/glossary/widgets/glossary_datagrid.dart:221-246), wraps the call in try/catch and shows the 'entry deleted successfully' toast on the non-throwing path — so (a) a failed delete (DB error, entry not found) still shows the success toast, and (b) even a successful delete leaves the deleted row visible in the grid because nothing refetches the entries provider (autoDispose providers stay cached while watched). Contrast with TmDeleteState.deleteEntry in tm_providers.dart which checks the Result and invalidates four providers.

```
Future<void> delete(String entryId) async {
    final service = ref.read(glossaryServiceProvider);
    await service.deleteEntry(entryId);

    // Clear editor state only if still mounted
    if (ref.mounted) {
      state = null;
    }
  }
```

### Failed TSV add during pack creation leaves a partial/corrupt .pack in the game's live data directory

fichier `lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:237` · source xcut-data-integrity

**Problème** : ExportOrchestratorService.exportToPack builds the pack directly at its final destination inside the game's data folder (packPath = path.join(gameDataPath, packFileName), export_orchestrator_service.dart:195) instead of a temp path + atomic rename. createPack first runs 'pack create' at that path (clobbering the user's previously working translation pack from the last export), then adds TSV files one process at a time. Both cancellation paths delete the partial pack (File(outputPackPath).delete()), but the TSV-add-failure path at lines 232-241 returns Err WITHOUT deleting it. Trigger: RPFM rejects any one TSV mid-loop (schema mismatch after an RPFM/schema update, malformed row, AV lock). Consequence: the previous good pack is gone and a half-built pack with only some .loc files remains in the data folder; the game launcher loads it, producing missing/corrupted translations in-game, while the app reports the export as failed and never cleans the destination up.

```
if (exitCode != 0) {
            final stderr = await stderrFuture;
            final error = RpfmOutputParser.parseErrorMessage(stderr);
            logger.error('Failed to add TSV file: $error');
            logger.error('RPFM stderr: $stderr');
            return Err(RpfmPackingException(
```

## Moyen (30)

### DeepSeekChatRestoreMigration force re-enables deepseek-chat on every startup, overriding user disable and auto-archival

fichier `lib/services/database/migrations/migration_deepseek_chat_restore.dart:33` · source svc-database

**Problème** : isApplied() does not check whether the migration ran; it checks the row's live flags: it returns true only while deepseek-chat is enabled AND unarchived. The migration runner (MigrationService.ensurePerformanceIndexes) re-evaluates isApplied() on every app launch. Trigger: the user disables 'DeepSeek V3.2' in Settings (LlmProviderModelRepository.disable sets is_enabled=0), or the automatic stale-model archiver (archiveStaleModels, which runs after a provider model fetch — relevant once DeepSeek drops the alias on 2026-07-24) archives it (is_archived=1, is_enabled=0). On the next startup isApplied() returns false and execute() runs its unconditional UPDATE `SET is_enabled = 1, is_archived = 0 WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'`, resurrecting the model. The single UPDATE sets is_archived=0 together with is_enabled=1, so the schema guard trigger trg_llm_models_prevent_enable_archived (WHEN NEW.is_enabled=1 AND NEW.is_archived=1) does not block it. Consequence: the user's disable choice is silently reverted on every launch, and a deprecated/removed model is permanently re-exposed in the picker no matter how often it is disabled or auto-archived.

```
"SELECT COUNT(*) as cnt FROM llm_provider_models " "WHERE model_id = 'deepseek-chat' AND is_archived = 0 AND is_enabled = 1",  ...  UPDATE llm_provider_models SET is_enabled = 1, is_archived = 0 ... WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'
```

### Aggregated parallel-chunk progress (tokensUsed, failedUnits, full llmLogs) is discarded; completed batch reports tokensUsed=0

fichier `lib/services/translation/translation_orchestrator_impl.dart:379` · source svc-translation · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : In parallel mode, ParallelBatchProcessor's per-chunk progress callback (parallel_batch_processor.dart:93-101, parallelProgressUpdate) copies only phaseDetail/currentPhase/llmLogs onto a stable base, stripping tokensUsed and failedUnits, so BatchProgressManager's stored progress never receives token counts during processing. The correct totals are computed once at the end in _aggregateResults and returned as finalProgress/progressAfterLlm — but the orchestrator immediately discards it: getProgress(batchId) is always non-null (set since the initial progress emission), so the `?? progressAfterLlm` fallback never fires. Consequently the completed TranslationProgress, the BatchCompletedEvent, and the 'Batch translation completed' log all report tokensUsed: 0 (and failedUnits missing the units the LLM response omitted) whenever parallelBatches > 1. The same mechanism also loses LLM exchange log entries shown in the UI: a chunk emission whose counters are not lower than the manager's overwrites llmLogs with only [base + own log], dropping other chunks' previously merged logs, and the complete allLlmLogs list in the discarded finalProgress never reaches the stream.

```
currentProgress =
          _batchProgressManager.getProgress(batchId) ?? progressAfterLlm;
```

### Headless bulk translate reports 0 translated units when translations come from Translation Memory

fichier `lib/services/translation/headless_batch_translation_runner.dart:116` · source svc-translation

**Problème** : TranslationProgress.successfulUnits is only incremented by ValidationPersistenceHandler for LLM/cache translations; TM exact/fuzzy matches bump skippedUnits instead. The orchestrator explicitly acknowledges this (translation_orchestrator_impl.dart:417-425) and compensates by adding tmOnlyMatched into the BatchCompletedEvent and phaseDetail — but it never folds them into the progress counters emitted on the stream. HeadlessBatchTranslationRunner reads progress.successfulUnits from the completed stream event, so when skipTM=false and units are resolved via TM (common for shared strings), the returned count undercounts — e.g. a fully TM-covered run returns 0. This value is shown directly to the user by bulk operations: bulk_operations_handlers.dart builds the outcome message 'X units translated' from it, reporting '0 units translated' for a successful run.

```
if (progress.status == TranslationProgressStatus.completed) {
          translated = progress.successfulUnits;
          break;
        }
```

### CancelToken silently dropped on DeepL-with-glossary translation path

fichier `lib/services/llm/llm_service_impl.dart:180` · source svc-llm

**Problème** : LlmServiceImpl.translateBatch receives a Dio CancelToken from the real translation flow (lib/services/translation/handlers/llm_retry_handler.dart:39-42 passes cancelToken into every attempt). When the provider is DeepL and the request has a glossaryId, _translateWithDeepLGlossary is invoked; its two fallback branches correctly forward cancelToken to provider.translate (lines 156, 168), but the main success branch calls provider.translateWithGlossary WITHOUT the token — and DeepLProvider.translateWithGlossary (lib/services/llm/providers/deepl_provider.dart:315-343) does not even accept a cancelToken parameter, so its inner _apiClient.translate call (which supports cancelToken) runs uncancellable. Trigger: user presses Stop/cancel while a DeepL+glossary batch is in flight. Consequence: the HTTP request keeps running to completion, continuing to consume DeepL character quota and delaying shutdown of the batch, while every non-glossary path cancels correctly — clearly an oversight, since the same method threads the token everywhere else.

```
final result = await provider.translateWithGlossary(
        request: request,
        apiKey: apiKey,
        glossaryId: deeplGlossaryId,
      );
```

### Empty completion with finish_reason 'length' misclassified as content filtering — unit permanently skipped instead of retried with more tokens

fichier `lib/services/llm/providers/openai_provider.dart:390` · source svc-llm

**Problème** : _parseResponse throws LlmContentFilteredException whenever content is null/empty, regardless of finish_reason. The payload uses max_completion_tokens (line 321) targeting modern OpenAI reasoning models, which spend completion budget on reasoning tokens: when max_completion_tokens (default 4096) is exhausted by reasoning, the API returns an EMPTY content string with finish_reason 'length' — a documented behavior, not moderation. The recovery pipeline (lib/services/translation/handlers/translation_error_recovery.dart:124) reacts to LlmContentFilteredException on a single unit by SKIPPING it permanently ('content filtered'), whereas a truncation/parse error would trigger _retryWithMoreTokens (doubling maxTokens). So a unit that merely needed a larger token budget is silently left untranslated and reported to the user as policy-blocked content. Same over-broad condition is duplicated in deepseek_provider.dart:373-374. The condition should treat finishReason == 'length' as a token-limit case, not a content filter.

```
if (finishReason == 'content_filter' ||
          (content == null || content.trim().isEmpty)) {
        ...
        throw LlmContentFilteredException(
```

### CSV parser turns empty quoted fields ("") into a literal double-quote character

fichier `lib/services/file/file_import_export_service.dart:246` · source svc-file

**Problème** : In _parseCsv, the escaped-quote branch fires without checking inQuotes. For an empty quoted field — e.g. the row a,"",b produced by any writer that quotes all fields (R write.csv, pandas QUOTE_ALL, many export tools) — the first '"' sees a following '"' and is treated as an escaped quote: a literal '"' is written to the buffer and the second quote is skipped, so the field parses as the one-character string '"' instead of the empty string. (Trace: i=0 'a'; ',' closes field; i=2 '"' with content[3]=='"' -> buffer '"', skip; i=4 ',' closes field with value '"'.) This corrupts every empty quoted field on the live import paths importFromCsv -> glossary CSV import (glossary_providers.dart:376) and translation import (import_file_reader.dart:23): empty columns (e.g. glossary notes/description) silently become '"' in the database. A four-quote field """" (value should be '"') similarly decodes to '""'. The fix requires the escaped-quote branch to apply only when inQuotes is true.

```
if (char == '"') {
  // Handle double quotes (escaped quote)
  if (i + 1 < content.length && content[i + 1] == '"') {
    buffer.write('"');
    i++; // Skip next quote
  } else {
    inQuotes = !inQuotes;
  }
```

### TM rebuild loop bound uses a count with different DISTINCT cardinality than the paged query, silently skipping tail rows

fichier `lib/services/translation_memory/tm_maintenance_service.dart:79` · source svc-glossary-tm

**Problème** : The paging loop 'for (var offset = 0; offset < total; offset += batchSize)' bounds iteration by countLlmTranslations(), which computes COUNT(DISTINCT tu.source_text || '|' || pl.language_id) — distinct (source, language) PAIRS. But getMissingTmTranslations() pages over SELECT DISTINCT tu.source_text, tv.translated_text, pl.language_id — distinct TRIPLES. Whenever the same (source_text, language) pair has more than one distinct translated_text (multiple translation_versions of a unit, or the same source string in different units translated differently by the LLM — very common for repeated Total War strings), the row set is strictly larger than 'total', so the loop terminates before fetching the final pages and those translations are never added to the TM, with no error or log. The progress callback total is wrong for the same reason.

```
for (var offset = 0; offset < total; offset += batchSize) {  // total = COUNT(DISTINCT tu.source_text || '|' || pl.language_id), but pages are SELECT DISTINCT tu.source_text, tv.translated_text, pl.language_id
```

### Glossary migration deletes universal glossaries with foreign_keys OFF, permanently orphaning their glossary_entries rows

fichier `lib/services/glossary/glossary_migration_service.dart:103` · source svc-glossary-tm · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : applyMigration() wraps the whole transaction with 'PRAGMA foreign_keys = OFF' (line 43, required for the table rebuild). But step 1 (user chose gameCode == null → txn.delete at lines 60-64) and step 2 ('DELETE ... WHERE game_code IS NULL', line 103) rely on glossary_entries' 'FOREIGN KEY (glossary_id) REFERENCES glossaries(id) ON DELETE CASCADE' (schema.sql line 305) to remove the entries — and CASCADE does not fire while foreign_keys is OFF. Unlike the duplicate-merge path (which explicitly moves/deletes entries via _mergeEntriesDedup before deleting the glossary), the universal-deletion paths delete only the glossaries row, leaving every glossary_entries row of those glossaries orphaned in the database forever (FK is re-enabled afterward but existing violations are not checked or cleaned). Consequence: permanent referential-integrity violations that make any later 'PRAGMA foreign_key_check' (used by other migrations in this codebase, e.g. migration_glossary_game_code_partial) report failures, plus dead rows that still match LOWER(TRIM(source_term)) dedup lookups in future merges.

```
await txn.delete('glossaries', where: 'game_code IS NULL');
```

### Any steamcmd 'Failed to update workshop item (<reason>)' output is misclassified as 'item deleted from Steam'

fichier `lib/services/steam/workshop_publish_service_impl.dart:232` · source svc-steam-rpfm-mods

**Problème** : steamcmd prints 'ERROR! Failed to update workshop item (<reason>).' for ALL workshop_build_item failures - e.g. (Access Denied), (Limit Exceeded) when the preview/content exceeds quota, (Timeout), (Failure) - not only when the item was deleted (which is the (File Not Found) reason). The substring check matches the generic prefix, so any upload failure (network blip, banned item, oversized preview) returns WorkshopItemNotFoundException telling the user 'Workshop item #X no longer exists on Steam.' (workshop_publish_notifier.dart:214 then surfaces 'Workshop item not found'). The same unconditional match exists in the batch path at line 621. A user whose upload failed transiently is told their Workshop item was deleted and is likely to republish it as a new item, creating a duplicate Workshop entry and orphaning subscribers. The check should inspect the parenthesized result reason instead of the generic prefix.

```
if (run.output.contains('Failed to update workshop item')) {
  ...
  return Err(WorkshopItemNotFoundException(
    'Workshop item #${params.publishedFileId} no longer exists on Steam.',
```

### ServiceLocator.isInitialized always returns false — DatabaseService is never registered in GetIt

fichier `lib/services/service_locator.dart:50` · source svc-infra

**Problème** : isInitialized is implemented as '_locator.isRegistered<DatabaseService>()', but no code path ever registers DatabaseService with GetIt (verified: grep for 'register.*DatabaseService' across lib/ finds nothing; CoreServiceLocator.registerInfrastructure registers only ILoggingService/EventBus/FileService, and DatabaseService is used exclusively as a static class). Consequence: the getter is permanently false even after full successful initialization. The concrete failure is in main.dart line 126, where the runZonedGuarded error handler does 'if (ServiceLocator.isInitialized) { ServiceLocator.get<ILoggingService>().error(...) } else { debugPrint(...) }' — uncaught zone errors are ALWAYS routed to debugPrint instead of the file logger. In a release Windows GUI build there is no attached console, so every uncaught async error in production is silently discarded and never reaches the twmt_*.log file. (initialize() itself survives only because the _initCompleter guard happens to make repeat calls idempotent.)

```
static bool get isInitialized => _locator.isRegistered<DatabaseService>();
```

### Failed undo/redo permanently drops the action: recovery branch is dead code comparing a value to itself

fichier `lib/services/history/undo_redo_manager.dart:182` · source svc-infra

**Problème** : In UndoRedoManager.undo(), the action is removed from _undoStack with removeLast() BEFORE 'await action.undo()' runs. If undo() throws (TranslationEditAction.undo throws whenever repository.getById or repository.update returns Err — e.g. a transient 'database is locked' error during a running batch), the catch block is supposed to re-add the action, but its condition '_undoStack.isEmpty || _undoStack.last != _undoStack.last' compares _undoStack.last to itself (always false on a non-empty stack, and the if-body is empty anyway), so the action is never restored. Result: the database was NOT changed (the exception occurred before/at the update) yet the undo step is gone from both stacks — the user permanently loses that undo entry on a transient failure. The identical dead-code bug exists in redo() at line 202 ('_redoStack.last != _redoStack.last').

```
final action = _undoStack.removeLast();\n      await action.undo();\n      ...\n    } catch (e) {\n      // Re-add action if undo failed\n      if (_undoStack.isEmpty || _undoStack.last != _undoStack.last) {\n        // Action was already removed, add it back\n      }\n      rethrow;
```

### cancelAll never stops the in-progress project after download: status helpers overwrite 'cancelled' and the DB update is applied anyway

fichier `lib/providers/mods/mod_update_provider.dart:235` · source providers-models

**Problème** : cancelAll() (lines 438-453) marks the currently in-progress project as ModUpdateStatus.cancelled and calls steamService.cancel(), which only aborts an active SteamCMD download. If the user clicks Cancel in ModUpdateDialog (mod_update_dialog.dart:97-98) while the current project is already past the download — in the detectingChanges or updatingDatabase phase — nothing stops _updateProject: it unconditionally continues, and _updateStatus(projectId, ModUpdateStatus.detectingChanges) / _updateStatus(..., updatingDatabase) / _updateStatusWithVersion(..., completed) (lines 235, 283, 317-321) blindly overwrite the 'cancelled' status without ever re-checking it. Deterministic consequence (no race needed): the item flips from the 'Cancelled' badge back to 'In progress', the analysis pipeline applies new/modified/removed keys to translation_units/translation_versions, inserts a new ModVersion row and marks it current — i.e. the project database is mutated and the item ends 'completed' even though the user explicitly cancelled it. Pending (not-yet-started) projects are correctly skipped via the check in startUpdates, so the cancellation contract is only broken for the active project.

```
ok: (result) async {
          // Update status to detecting changes
          _updateStatus(projectId, ModUpdateStatus.detectingChanges);
```

### Damerau-Levenshtein implementation counts invalid transpositions and underestimates distance

fichier `lib/utils/string_similarity.dart:294` · source widgets-shared · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : The transposition term of damerauLevenshteinDistance uses `k = db` (the current-row match tracker) where the standard algorithm requires the per-character last-occurrence row index in the source string (da[s2[j-1]]), and the `(j - 1 - db)` term uses db AFTER it was updated to j (can be negative). Verified by execution: damerauLevenshteinDistance("ca", "ab") returns 1, but the true Damerau-Levenshtein distance is 2 (no single edit/transposition turns "ca" into "ab"). The function therefore underestimates edit distance (overestimates similarity) whenever the same character matches at different positions across rows. It is exposed publicly and via Levenshtein.calculateDamerauLevenshtein in lib/services/concurrency/utils/levenshtein.dart (currently no other production callers, so impact is latent), and even its own doc example contract is violated for non-adjacent cases.

```
matrix[i + 1][j + 1] = _min4(
  matrix[i][j] + cost, // Substitution
  matrix[i + 1][j] + 1, // Insertion
  matrix[i][j + 1] + 1, // Deletion
  matrix[k][j - 1] + (i - k - 1) + 1 + (j - 1 - db), // Transposition
);
```

### Saved pt-BR app locale can never be restored — always falls back to European Portuguese

fichier `lib/main.dart:109` · source widgets-shared

**Problème** : Startup locale restore matches saved preference against `l.languageCode` only. In the generated AppLocale enum (lib/i18n/strings.g.dart), `pt(languageCode: 'pt')` and `ptBr(languageCode: 'pt', countryCode: 'BR')` share languageCode 'pt', and `pt` precedes `ptBr` in AppLocale.values, so firstWhere can never resolve ptBr. The companion save path (lib/providers/app_locale_provider.dart, `prefs.setString(_prefsKey, locale.languageCode)`) also persists only 'pt' for ptBr. Trigger: user selects 'Português (Brasil)' in settings, restarts the app. Consequence: the app silently switches to European Portuguese (`AppLocale.pt`) on every launch; the user's locale choice is permanently lost. The fix needs to persist/match the full locale tag (e.g. languageTag) instead of languageCode.

```
final match = AppLocale.values.firstWhere(
  (l) => l.languageCode == savedLocaleCode,
  orElse: () => AppLocale.en,
);
```

### "Mark as translated" never clears validation issues — copyWith(validationIssues: null) is a no-op

fichier `lib/features/translation_editor/widgets/grid_actions_handler.dart:155` · source feat-editor

**Problème** : TranslationVersion.copyWith (lib/models/domain/translation_version.dart:184-186) implements `validationIssues: clearValidationIssues ? null : (validationIssues ?? this.validationIssues)` — passing `validationIssues: null` keeps the old value; the dedicated `clearValidationIssues: true` flag must be used (as handleRejectTranslation correctly does). In handleValidate (context-menu "Mark as translated"), the comment states the intent to clear issues, but the old validation_issues JSON is carried over and written back to the DB by versionRepo.update(), which persists the full entity map. Trigger: user right-clicks flagged rows and picks "Mark as translated". Consequence: rows the user explicitly approved keep their stale validation_issues payload — `hasValidationIssues` stays true (so the showOnlyWithIssues filter and `isReadyForUse` misclassify them), and every later copyWith-based write (e.g. a subsequent cell edit) keeps dragging the dismissed issues along in the database.

```
final updatedVersion = row.version.copyWith(
  status: TranslationVersionStatus.translated,
  validationIssues: null, // Clear validation issues when manually approved
  ...
```

### Inspector "Accept" leaves stale validation issues on the row — same copyWith(null) no-op

fichier `lib/features/translation_editor/screens/actions/editor_actions_validation.dart:457` · source feat-editor · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : handleAcceptTranslation (wired to the inspector panel's Accept button for needsReview rows, see translation_editor_screen.dart:293-294) passes `validationIssues: null` to copyWith, which does NOT clear the field (copyWith uses `validationIssues ?? this.validationIssues`; clearing requires `clearValidationIssues: true`). The sibling handleRejectTranslation in the same file (line 427) correctly uses `clearValidationIssues: true`, proving the authors know null doesn't clear. Trigger: user clicks Accept on a validation issue in the inspector. Consequence: the version is persisted as status=translated but still carries the dismissed validation_issues JSON, leaving inconsistent data in the DB — `hasValidationIssues`/`isReadyForUse` report wrong values for the accepted row, and the stale payload is propagated by every subsequent copyWith-based update of that version.

```
final acceptedVersion = version.copyWith(
  status: TranslationVersionStatus.translated,
  validationIssues: null,
  updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
);
```

### Undo/redo stack lives in an autoDispose provider that is only ever ref.read — undo can never succeed

fichier `lib/features/translation_editor/providers/editor_providers.dart:31` · source feat-editor · 1/3 vérificateurs suggèrent une sévérité moindre

**Problème** : undoRedoManagerProvider is a default `@riverpod` provider (generated editor_providers.g.dart:96 has `isAutoDispose: true`) and is accessed exclusively via `ref.read` (editor_actions_cell_edit.dart:17,103; editor_actions_undo_redo.dart:9,24) — nothing in the live app watches it (the canUndo/canRedo providers in lib/providers/history/history_providers.dart are unused). Reading an unlistened autoDispose provider creates the state and disposes it right after, so every access constructs a brand-new empty UndoRedoManager. Trigger: handleCellEdit records a TranslationEditAction into a throwaway instance on every edit; when handleUndo/handleRedo later call `ref.read(undoRedoManagerProvider).undo()`, they get a fresh manager whose stack is empty, so undo() returns false and nothing happens — the undo system is silently non-functional, contradicting the provider's own doc comment ("creates a fresh instance per project editor session" — it is per read). Fix is `@Riverpod(keepAlive: true)` or holding the instance somewhere watched.

```
@riverpod
UndoRedoManager undoRedoManager(Ref ref) {
  return UndoRedoManager();
}
```

### reanalyzeAllTranslations/clearStaleAnalysisCache mutate state after await without ref.mounted guard — UnmountedRefException escapes as unhandled exception

fichier `lib/features/settings/providers/maintenance_providers.dart:150` · source feat-settings · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : maintenanceStateProvider is autoDispose (isAutoDispose: true in maintenance_providers.g.dart) and is only watched by MaintenanceSection on the General settings tab. Trigger: user clicks 'Reanalyze' (a long full-table DB scan) and then switches tab or leaves Settings while it runs; TabBarView unmounts the tab, the provider disposes. When `await repository.reanalyzeAllStatuses()` completes, the `state = state.copyWith(...)` setter calls Ref._throwIfInvalidUsage() and throws UnmountedRefException (riverpod 3.0.3). The exception is caught by the method's own catch block, but that block immediately does `state = state.copyWith(...)` again (line 162), which rethrows — and the caller `_runReanalysis` in maintenance_section.dart (line 255) invokes the future unawaited, so it surfaces as an unhandled async exception and the operation result is lost. The exact same gap exists in clearStaleAnalysisCache (lines 201 and 215). This is demonstrably a known hazard in this file: the sibling methods rebuildTranslationMemory and migrateLegacyHashes were already fixed with `if (!ref.mounted) return;` guards (lines 263, 279, 322, 337), but these two methods were missed.

```
final result = await repository.reanalyzeAllStatuses(); ... state = state.copyWith(
        isReanalyzing: false,
        clearProgress: true,  // no `if (!ref.mounted) return;` unlike rebuildTranslationMemory
```

### BackupStateNotifier sets state after long-running backup/restore awaits without ref.mounted guard — throws after dispose, error handler rethrows

fichier `lib/features/settings/providers/backup_providers.dart:159` · source feat-settings · 1/2 vérificateurs suggèrent une sévérité moindre

**Problème** : backupStateProvider is autoDispose and only watched by BackupSection on the General settings tab. importBackup awaits `_backupService.restoreBackup(sourcePath)` (a potentially long DB-replace operation, the UI is not modal during it); if the user switches tabs or navigates away meanwhile, the provider is disposed. On completion, `state = state.copyWith(...)` inside `result.when(ok:/err:)` throws UnmountedRefException (riverpod 3.0.3 throws on any state access after dispose). The outer catch block then performs `state = state.copyWith(...)` itself (line 181), which rethrows, so `importBackup` never returns its bool and the exception propagates as an unhandled error into BackupSection._importBackup's await. The same unguarded pattern exists in exportBackup (state assignments at lines 113 and 121 after `await _backupService.createBackup`). Unlike maintenance_providers.dart in the same directory — where two methods were already fixed with `if (!ref.mounted) return;` — this notifier has no guards at all.

```
final result = await _backupService.restoreBackup(sourcePath);
      return result.when(
        ok: (_) {
          ...
          state = state.copyWith(
            isImporting: false,
```

### Ready-to-compile counter uses round(), counting incomplete projects as 100% translated

fichier `lib/features/home/providers/workflow_providers.dart:80` · source feat-projects-home

**Problème** : projectsReadyToCompileCount documents 'Projects whose units are 100% translated' but computes `pct = ((translatedCount / totalCount) * 100).round()` and treats `pct >= 100` as complete. Any project at >= 99.5% (e.g. 1995/2000 units translated — a single missed unit in a large mod is enough) is counted as ready to compile. The Home 'Ready to compile' ActionCard navigates to `/work/projects?filter=ready-to-compile`, which maps to ProjectQuickFilter.hasCompleteLanguage and uses the strict `translatedUnits >= totalUnits` check (ProjectLanguageWithInfo.isComplete) — so the dashboard shows a non-zero count while the destination filter shows nothing (or fewer). The same inflated count drives homeStatusProvider's 'ready to compile' status line.

```
final pct = ((stats.translatedCount / stats.totalCount) * 100).round();
    if (pct < 100) continue;
```

### silentCleanup() never sets _silentlyCleaned=true — all guards are dead code and state is mutated after widget dispose

fichier `lib/features/steam_publish/providers/workshop_publish_notifier.dart:295` · source feat-steam-pack · 2/2 vérificateurs suggèrent une sévérité moindre

**Problème** : The field `_silentlyCleaned` is initialized false (line 75), reset to false at publish start (line 98), and checked in three guards (lines 118, 125, 149) — but it is never assigned `true` anywhere in the file. The batch counterpart (BatchWorkshopPublishNotifier.silentCleanup, batch_workshop_publish_notifier.dart:356) sets `_silentlyCleaned = true;` — the single-publish version is missing this line. Consequence: when WorkshopPublishScreen.dispose() calls silentCleanup() during an active upload, the still-pending `await service.publish(...)` resolves after cancel and, since phase is still `uploading` (not idle/cancelled) and the flag is false, falls into the error branch and sets `phase: PublishPhase.error` on the app-scoped provider — exactly the state write the method's doc comment ('Clean up without setting state') promises not to do. The stale error state is then visible for the first frame when the screen is reopened (initState resets only via Future.microtask). Worse, if the user re-enters the screen and starts a new publish before the cancelled future resolves, the old invocation's lines 145-146 cancel the NEW publish's progress/output subscriptions (shared instance fields) and `_clearCachedCredentials()` wipes the new publish's cached credentials, breaking a subsequent Steam Guard retry ('Session expired').

```
void silentCleanup() {
    _progressSub?.cancel();
    _progressSub = null;
    _outputSub?.cancel();
    _outputSub = null;
    _clearCachedCredentials();
    final service = ref.read(workshopPublishServiceProvider);
    service.cancel();
  }
```

### saveWorkshopId ignores Result of projectRepo.update/getById and reports success when nothing was saved

fichier `lib/features/steam_publish/widgets/steam_id_editing.dart:47` · source feat-steam-pack

**Problème** : `projectRepo.update()` returns `Result<Project, TWMTDatabaseException>` (base_repository.dart:34) and never throws, so the surrounding try/catch (line 57) can never observe a failed write — its error toast is dead code for the project path. If the update fails (DB error) the function still calls `ref.invalidate(publishableItemsProvider)` and returns `true`: the caller (SteamIdCell._save) closes the editor and the list refresh reverts to the old value with no error shown — the user's typed Workshop ID silently vanishes. Same for the `getById` failure branch (line 41): when the project row can't be loaded, the save is silently skipped yet the function still returns true/success. The compilation path (`compilationRepo.setWorkshopId`, line 53) also returns a Result whose error is discarded.

```
final projectResult = await projectRepo.getById(item.project.id);
      if (projectResult.isOk) {
        final updated = projectResult.value.copyWith(...);
        await projectRepo.update(updated);
      }
    ...
    ref.invalidate(publishableItemsProvider);
    return true;
```

### saveCompilation ignores the Result of compilationRepo.setProjects — project-link write failure silently reported as 'Compilation saved'

fichier `lib/features/pack_compilation/services/../providers/../providers/compilation_editor_notifier.dart:157` · source feat-steam-pack

**Problème** : `setProjects` returns `Result<void, TWMTDatabaseException>` (compilation_repository.dart:214) and never throws, so the enclosing try/catch cannot detect its failure. Both call sites (edit mode line 157, create mode line 182) discard the Result. If the transaction fails, the method still sets `successMessage: 'Compilation saved'` and returns true, and `generatePack()` (which gates on `saveCompilation`) proceeds to build the .pack from the in-memory selection — leaving the DB row's project links stale/absent. Reopening the compilation then shows a different (old or empty) project selection than the pack that was actually generated and possibly published. Note the sibling `compilationRepo.update`/`insert` calls right above DO check their Results, which shows the omission is unintentional. The same pattern recurs at line 451 (`updateAfterGeneration` Result ignored: a generated pack would never be recorded, so the Steam-publish list keeps showing 'no pack').

```
// Update projects
        await compilationRepo.setProjects(
          state.compilationId!,
          state.selectedProjectIds.toList(),
        );
```

### _saveWorkshopId discards Result of projectRepo.update / updateAfterPublish — DB write failures after a successful Workshop upload are silently lost

fichier `lib/features/steam_publish/providers/batch_workshop_publish_notifier.dart:295` · source feat-steam-pack

**Problème** : Both repository calls return `Result` types and never throw, so the catch blocks logging 'Failed to save Workshop ID for ...' (lines 297-299, 308-311) are dead code — a failed write is neither logged nor surfaced. The whole `pendingSaves` mechanism (lines 263-265) awaits these futures specifically so 'just-published items are not shown as unpublished', but a Result-level failure passes the await silently: after a successful Steam upload the publishedAt/Workshop ID is not persisted, and the refreshed list shows the item as outdated/unpublished anyway. Additionally the `projectResult.isOk == false` branch (line 289) is silently swallowed with no log at all. The identical bug exists in the single-publish notifier (workshop_publish_notifier.dart lines 168-186: `await projectRepo.update(updated)` and `updateAfterPublish` Results ignored, catch dead).

```
if (projectResult.isOk) {
          final updated = projectResult.value.copyWith(
            publishedSteamId: workshopId,
            publishedAt: now,
            updatedAt: projectResult.value.updatedAt,
          );
          await projectRepo.update(updated);
        }
      } catch (e) {
        logging.warning('Failed to save Workshop ID for ${item.name}: $e');
```

### Empty-glossary gate reads stale currentGlossaryProvider.entryCount which is never invalidated — first added/imported entries invisible

fichier `lib/features/glossary/screens/glossary_screen.dart:257` · source feat-data-misc

**Problème** : The glossary screen shows the soft-empty placeholder instead of the data grid whenever glossary.entryCount == 0, where glossary comes from currentGlossaryProvider. A repo-wide grep shows currentGlossaryProvider is never invalidated anywhere: GlossaryEntryEditorDialog._saveEntry invalidates only glossaryEntriesProvider and glossaryStatisticsProvider (glossary_entry_editor.dart:254-255), and GlossaryImportState.importCsv/importTbx/importExcel invalidate glossariesProvider/glossaryEntriesProvider/glossaryStatisticsProvider (glossary_providers.dart:397-399 etc.) — currentGlossaryProvider does not watch any of those (it watches selectedGameProvider, selectedGlossaryLanguageProvider, and the service only). Trigger: add the first entry to an empty glossary (success toast shown), or import a CSV into it — entryCount stays 0 in the cached provider value, so the screen keeps showing 'No entries yet' and the GlossaryDataGrid is never even mounted, until the user switches language/game or restarts the app.

```
child: glossary.entryCount == 0
                  ? _buildSoftEmpty(context)
                  : GlossaryDataGrid(glossaryId: glossary.id),
```

### Mods refresh listener never completes on scan error: loading state stuck true and subscription leaked

fichier `lib/features/mods/utils/mods_screen_controller.dart:52` · source feat-mods-misc

**Problème** : handleRefresh() sets modsLoadingStateProvider to true, then waits for detectedModsProvider via listenManual and only clears the loading flag when `next.hasValue && !next.isLoading`. When the rescan ends in an error with no retained data, this condition is never satisfied. Concrete trigger: DetectedMods.build rethrows RpfmNotFoundException when the RPFM CLI path is missing/invalid (lib/providers/mods/mod_list_provider.dart:63-64). On first visit the scan errors with no prior value, the screen shows the error state, and the Retry button calls handleRefresh(); the subsequent rescan errors again, producing AsyncLoading(no value) -> AsyncError(no value), so `next.hasValue` stays false. Result: modsLoadingState remains true forever — the toolbar refresh button is permanently disabled showing 'Rescanning…' — and the ProviderSubscription is never closed (a new one leaks on every retry). The boot dialog handles the identical stream correctly with `(next.hasValue && !next.isLoading) || next.hasError` (mod_scan_boot_dialog.dart:96), confirming the missing hasError branch here is a bug.

```
if (next.hasValue && !next.isLoading) {
          _ref.read(modsLoadingStateProvider.notifier).setLoading(false);
          subscription.close();
        }
```

### Validation rescan failure closes the dialog with a 'update complete' SUCCESS toast; the error is never shown

fichier `lib/features/bootstrap/widgets/validation_rescan_dialog.dart:101` · source feat-mods-misc

**Problème** : When the rescan stream errors, ValidationRescanController's onError handler sets `state.copyWith(error: e, isRunning: false, isDone: true)` while `plan` remains non-null (validation_rescan_provider.dart:184-185). The dialog's only completion branch is `if (state.isDone && !_toastFired)`, which pops the dialog and — because `plan != null` — fires FluentToast.success('Update complete'). `state.error` is never read by any part of the dialog body (_body/_titleFor have no error branch), so a mid-rescan failure (e.g., a DB error while rewriting validation rows) is silently swallowed and explicitly reported to the user as a successful completion, even though legacy rows remain unmigrated. The prepare() failure path has the same silent-close problem (error set, isDone true, plan null -> closes with no message at all).

```
Navigator.of(context).pop();
        // Only show a toast when an actual rescan finished. Pure-
        // normalization runs (no plan) complete silently.
        if (plan != null) {
          FluentToast.success(
            context,
            t.bootstrap.validationRescan.toasts.updateComplete,
          );
```

### Catch-all in project creation deletes a fully initialized project when a post-success step throws

fichier `lib/features/mods/utils/mods_screen_controller.dart:228` · source feat-mods-misc

**Problème** : In _createProjectFromMod (and identically in _createProjectFromLocalPack, lines 304-311), the try block extends past the successful initialization of the project: after `success == true` it runs `_ref.invalidate(...)`, `updateModImported(...)`, and `await openProjectEditor(context, _ref, projectId)`. openProjectEditor awaits `projectLanguagesProvider(projectId).future`, which throws `Exception('Failed to load project languages')` whenever the repository returns Err (lib/features/projects/providers/project_detail_providers.dart:46-48). Any exception thrown in these post-success steps falls into the catch block, which unconditionally executes `service.deleteProject(projectId)` — deleting the project row (and its just-imported languages/translation units) that was successfully created and initialized seconds earlier, and showing a misleading 'failed to create project' toast. A transient navigation/DB hiccup after a successful import therefore destroys the user's completed work instead of leaving the valid project in place. The cleanup-on-error should only apply to failures occurring before initialization succeeded.

```
} catch (e) {
      if (projectId != null) {
        await service.deleteProject(projectId);
      }
      if (context.mounted) {
        FluentToast.error(context, t.mods.messages.failedToCreateProject(error: e));
```

### Database backup copies live db/WAL files non-atomically; PASSIVE checkpoint result ignored — corrupt backup under concurrent writes

fichier `lib/services/backup/database_backup_service.dart:84` · source xcut-concurrency

**Problème** : createBackup() runs `await DatabaseService.checkpointWal()` (a PASSIVE checkpoint whose boolean result — `busy == 0` — is discarded; PASSIVE checkpoints silently do nothing while readers/writers are active), then reads twmt.db (line 102) and twmt.db-wal (line 113) with separate awaited `readAsBytes()` calls against the OPEN database. sqflite_ffi executes SQL on a worker isolate, so a running translation batch keeps writing during these reads, and the TM batch mixin (lib/repositories/mixins/translation_memory_batch_mixin.dart:149,265) plus the orchestrator's _cleanupBatch (translation_orchestrator_impl.dart:608) call `checkpointIfNeeded()` mid-batch. If a checkpoint lands between (or during) the two file reads, the archived twmt.db contains half-checkpointed pages while the archived -wal has been reset/truncated (salt mismatch), so on restore SQLite discards the WAL frames and the restored database is inconsistent or corrupt. Nothing prevents the user from running Settings → Backup while a batch translation is in progress, and the corruption is only discovered at restore time (silent data loss).

```
// Checkpoint WAL to ensure all data is in main database
      _logging.debug('Checkpointing WAL before backup');
      await DatabaseService.checkpointWal();
      ...
      final dbBytes = await dbFile.readAsBytes();
      ...
      final walBytes = await walFile.readAsBytes();
```

### Stale _isCancelled flag in SteamCmdServiceImpl makes the next mod download falsely report 'cancelled'

fichier `lib/services/steam/steamcmd_service_impl.dart:137` · source xcut-concurrency

**Problème** : downloadMod() never resets `_isCancelled` at the start of a run; it is only cleared in the `finally` at the END of a download (line 195). cancel() (line 244) sets `_isCancelled = true` unconditionally. Concrete trigger: ModUpdateQueue.cancelAll (lib/providers/mods/mod_update_provider.dart:449) calls `steamService.cancel()` whenever `_currentProjectId != null` — and `_currentProjectId` stays set through the post-download `detectingChanges`/`updatingDatabase` phases (cleared only in _updateProject's finally, line 352). If the user clicks cancel during those phases (no process running, the previous download's finally already reset the flag once), `_isCancelled` is left true with no in-flight download to consume it. When the user later retries (retry() is offered for cancelled entries), the full steamcmd download runs to completion and is then discarded at `if (_isCancelled)` with the bogus error 'Download cancelled by user'. The sibling WorkshopPublishServiceImpl shows the intended pattern — it resets `_isCancelled = false` at the start of publish() (workshop_publish_service_impl.dart:89).

```
if (_isCancelled) {
        return Err(const SteamServiceException(
          'Download cancelled by user',
          code: 'DOWNLOAD_CANCELLED',
        ));
      }
```

## Faible (16)

### OpenAI migration inserts gpt-5.5 with is_default=1 (contradicting its own comment), bypassing the per-provider single-default trigger and creating duplicate defaults

fichier `lib/services/database/migrations/migration_openai_v5_4_5_5_models.dart:57` · source svc-database

**Problème** : The comment two lines above says "is_default = 0 because the global default selection is owned by the provider table / user preferences", but the VALUES row passes is_default=1 (columns: ..., is_enabled, is_default, is_archived -> 1, 1, 0). The schema invariant 'one default per provider' is enforced only by trg_llm_models_single_default, which is `BEFORE UPDATE OF is_default` — it does not fire on INSERT, so nothing clears an existing default. Trigger scenario: on an upgraded database the user had previously set another OpenAI model (e.g. an API-fetched gpt-4o) as default via setAsDefault; the migration then inserts gpt-5.5 with is_default=1 and only clears is_default on the specific legacy row 'gpt-5.1-2025-11-13'. Result: two rows in provider 'openai' have is_default=1. Consumers assume uniqueness: getDefaultByProvider uses `where: 'provider_code = ? AND is_default = 1 AND is_archived = 0', limit: 1` with no ORDER BY (arbitrary row wins), and editor_toolbar_model_selector does `.where((m) => m.providerCode == activeProvider && m.isDefault)` then takes the first — so which model translations actually use becomes nondeterministic and may silently differ from the user's chosen default. (AnthropicOpus47Sonnet46Migration line 60 has the same INSERT-with-is_default=1 pattern.)

```
// Insert the new aliases. is_default = 0 because the global default
// selection is owned by the provider table / user preferences.
...
('model_gpt_5_5', 'openai', 'gpt-5.5', 'GPT-5.5', 1, 1, 0, strftime('%s', 'now'), ...)
```

### CompilationPublishFieldsMigration: two non-atomic ALTERs but isApplied checks only the first column — a crash between them permanently loses published_at

fichier `lib/services/database/migrations/migration_compilation_publish_fields.dart:30` · source svc-database

**Problème** : execute() runs two separate auto-committed DDL statements: `ALTER TABLE compilations ADD COLUMN published_steam_id TEXT` then `ALTER TABLE compilations ADD COLUMN published_at INTEGER`. isApplied() returns true as soon as published_steam_id exists. If the process is killed (crash, power loss, user closes the app during startup migrations) after the first ALTER commits but before the second runs, every subsequent startup sees isApplied() == true and the migration never runs again — the compilations table is permanently missing the published_at column. Any later compilation Workshop-publish flow that writes or reads published_at then fails with 'no such column: published_at' with no self-healing path (the migration is the only code that adds it). The fix-side pattern used elsewhere (e.g. checking each column independently, as CompilationTablesMigration._ensureLanguageIdColumn does) is not applied here. ProjectTypeMigration (project_type checked, source_language_code added second) has the identical defect.

```
return columns.any((col) => col['name'] == 'published_steam_id');  ...  ALTER TABLE compilations ADD COLUMN published_steam_id TEXT''');
      await DatabaseService.execute('''
        ALTER TABLE compilations
        ADD COLUMN published_at INTEGER
```

### TsvParser.parseString does not skip the RPFM TSV header row, producing a spurious entry per file during pack import

fichier `lib/services/file/parsers/tsv_parser.dart:56` · source svc-file

**Problème** : PackImportService.previewImport (lib/features/translation_editor/services/pack_import_service.dart:175) parses files produced by _rpfmService.extractLocalizationFilesAsTsv with LocalizationParserImpl.parseFile, which routes non-binary content to TsvParser.parseString. Every RPFM-exported loc TSV starts with the header row 'key\ttext\ttooltip' followed by the '#Loc;1;...' metadata row (this is documented and correctly skipped in the sibling TsvLocalizationParser._parseInternal, lines 56-62 of tsv_localization_parser.dart). parseString skips the '#' metadata row as a comment, but the header row passes the parts.length>=2 check; since the last column 'tooltip' is not 'true'/'false', it yields a bogus LocalizationEntry(key: 'key', value: 'text\ttooltip') for every extracted file. These fake entries inflate totalEntriesInPack / 'Found N entries in pack' and appear as bogus rows in the unmatched-entries list of the import preview shown to the user (one per loc file in the pack); if a mod ever defines a real loc key named 'key', the garbage value 'text\ttooltip' becomes importable over a real translation.

```
// Parse TSV line (Key\tValue\tBoolean)
final parts = trimmed.split('\t');

if (parts.length < 2) {
  // Invalid line - skip or throw based on options
  continue;
}
```

### IsolateSimilarityService initialization race: window where _isolate != null but _sendPort == null causes null-assertion crash and duplicate isolate leak

fichier `lib/services/translation_memory/isolate_similarity_service.dart:87` · source svc-glossary-tm, xcut-concurrency, xcut-resources

**Problème** : initialize() guards re-entry with 'if (_isolate != null) return;' but _isolate is assigned when Isolate.spawn completes (line 90) while _sendPort is assigned only later (line 106, after the handshake message arrives). A concurrent caller of calculateBatchSimilarity() in that window sees '_sendPort == null', calls initialize(), which returns immediately (because _isolate != null), and then executes '_sendPort!.send(...)' (line 186) — a null-check error that fails the lookup spuriously. In the alternative interleaving (second caller enters while the first is still awaiting Isolate.spawn, _isolate still null), TWO isolates are spawned; the second assignment overwrites _isolate/_sendPort and the first isolate is never killed (leak, since dispose() only kills the tracked one). Reachable because findFuzzyMatchesIsolate (called per-unit from tm_lookup_handler during translation) and findFuzzyMatchesBatch both lazily initialize the shared singleton.

```
Future<void> initialize() async {
    if (_isolate != null) return;  // _sendPort may still be null here
    ...
    _sendPort!.send(_IsolateRequest(
```

### downloadMod parses stderr and collects warnings before the output streams are drained

fichier `lib/services/steam/steamcmd_service_impl.dart:147` · source svc-steam-rpfm-mods

**Problème** : In SteamCmdServiceImpl.downloadMod the stdout/stderr listeners (lines 104-119) just append to StringBuffers, and the code awaits only _currentProcess!.exitCode (line 122) before reading stderr.toString() at line 147. In Dart the exitCode future can complete while stdout/stderr data events are still queued, so on a steamcmd failure _parseErrorMessage frequently sees an empty/truncated buffer and reports 'Unknown error' instead of the real cause; collected warnings can be lost the same way. The sibling WorkshopPublishServiceImpl._runSteamCmd was explicitly fixed for exactly this race (it uses an outputCompleter with the comment 'awaiting exitCode alone can truncate stdout and miss login/update failures'), but this file kept the racy pattern. Triggered on every failed or warning-producing Workshop download via the mod-update flow (mod_update_provider.dart:226).

```
final exitCode = await _currentProcess!.exitCode.timeout(...);
...
if (exitCode != 0 && exitCode != 6 && exitCode != 7) {
  final errorMsg = _parseErrorMessage(stderr.toString());
```

### User cancellation of a Workshop download is reported as a 10-minute timeout

fichier `lib/services/steam/steamcmd_service_impl.dart:130` · source svc-steam-rpfm-mods

**Problème** : cancel() kills the steamcmd process; on Windows Process.kill terminates the process so its exit code surfaces as -1 - the same sentinel the timeout handler returns. downloadMod checks 'exitCode == -1' (line 130) and returns SteamCmdTimeoutException('Download timed out', timeoutSeconds: 600) BEFORE the _isCancelled check at line 137, so the cancellation branch returning DOWNLOAD_CANCELLED is unreachable for a killed process. A user who cancels a download immediately gets an error dialog claiming the download timed out after 10 minutes, and callers that branch on the error code (timeout vs. user cancel) take the wrong path. The _isCancelled check must precede the exitCode == -1 check (the publish service has the same ordering at workshop_publish_service_impl.dart:208-220).

```
if (exitCode == -1) {
  return Err(const SteamCmdTimeoutException(
    'Download timed out',
    timeoutSeconds: 600,
  ));
}

if (_isCancelled) {
```

### Logs/cache directory derived from getTemporaryDirectory().parent breaks when TEMP is redirected

fichier `lib/config/database_config.dart:82` · source widgets-shared

**Problème** : getLogsDirectory (and getCacheDirectory at line 100) compute %LOCALAPPDATA% as the parent of getTemporaryDirectory(). On Windows, path_provider's getTemporaryDirectory() returns GetTempPath(), which honors the user's TMP/TEMP environment variables. If TEMP is redirected (common: TMP=C:\Temp, RAM-disk temp, corporate policy, cleanup tools), tempDir.parent is no longer %LOCALAPPDATA% — e.g. TMP=C:\Temp yields logs at C:\com.github.slavyk82\twmt\logs, and TMP=C:\Windows\Temp attempts to create C:\Windows\com.github.slavyk82\twmt\logs, where Directory.create throws an unhandled PathAccessException during startup's ensureDirectoriesExist (ServiceLocator.initialize rethrows, aborting app startup). Should use getApplicationCacheDirectory()/known-folder APIs or Platform.environment['LOCALAPPDATA'] instead.

```
final tempDir = await getTemporaryDirectory();
final localAppData = tempDir.parent;

final logsDir = path.join(
  localAppData.path,
  appDirectoryName,
  'logs',
);
```

### Test connection races the 600 ms debounced API-key save — validates the stale/empty stored key instead of the key in the field

fichier `lib/features/settings/widgets/llm_provider_section.dart:51` · source feat-settings

**Problème** : API-key edits are persisted only after a 600 ms idle debounce (`_onApiKeyChanged` schedules `widget.onSaveApiKey()` via Timer), while the adjacent Test button calls `LlmProviderSettings.testConnection(providerCode)`, which reads the key from `_secureStorage.read(key: ...)` (settings_providers.dart lines 320-337), not from the text field. Nothing flushes the pending debounce before testing. Trigger: paste a new API key and immediately click the Test button (within the debounce window plus the slow Windows secure-storage write). Consequence: on first-time setup the test reports 'No API key configured' despite a filled field; when replacing a bad key with a good one, the test validates the old key and reports success/failure for the wrong credential.

```
_apiKeyDebounceTimer = Timer(_apiKeyDebounce, () {
      if (mounted) widget.onSaveApiKey();
    });  // testConnection reads _secureStorage, never the controller text
```

### Default RPFM schema path hardcodes C:\Users\<USERNAME> instead of using %APPDATA% — wrong path on relocated profiles or non-C: system drives

fichier `lib/features/settings/widgets/general/rpfm_section.dart:257` · source feat-settings

**Problème** : _useDefaultRpfmSchemaPath builds the roaming-profile path by string-substituting the USERNAME environment variable into a hardcoded 'C:\Users\...' template. On any machine where the profile directory is not literally C:\Users\<USERNAME> — Windows installed on another drive letter, redirected/relocated user profiles, or a profile folder name that differs from USERNAME (common after domain logins or Microsoft-account setups where the folder is a truncated/derived name, e.g. user 'John Smith' with folder 'johns') — the 'Default' button silently writes a non-existent schemas path, which is then persisted via _saveRpfmSchemaPath and breaks RPFM schema resolution. The correct base is Platform.environment['APPDATA'] (which already resolves to the real roaming dir), making this concretely wrong rather than just stylistic.

```
final defaultPath =
        r'C:\Users\$username\AppData\Roaming\FrodoWazEre\rpfm\config\schemas'
            .replaceAll('\$username', username);
```

### Per-row retranslate omits the active-provider fallback its comment claims to mirror

fichier `lib/features/projects/widgets/bulk_review_dialog.dart:243` · source feat-projects-home

**Problème** : _resolveProviderModel's comment says it 'mirrors bulk_operations_handlers' private _resolveSelectedProvider', but it only handles the explicit `selectedLlmModelProvider` case and returns null otherwise. _resolveSelectedProvider in bulk_operations_handlers.dart additionally falls back to the `active_llm_provider` setting (returns `provider_<code>` with null modelId). Result: a user who has configured an active LLM provider but never picked a specific model in the editor can run bulk 'Translate all' and bulk 'Retranslate all' successfully, but every per-row retranslate button in the same review dialog fails with the 'no model selected' error — also when the previously selected model row was deleted (getById returns Err) the fallback is likewise skipped.

```
Future<({String providerId, String? modelId})?> _resolveProviderModel(
  WidgetRef ref,
) async {
  final selectedModelId = ref.read(selectedLlmModelProvider);
  if (selectedModelId != null) {
    ...
  }
  return null;
}
```

### Compile button bypasses the unresolved-conflicts warning while analysis is still running

fichier `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart:291` · source feat-steam-pack

**Problème** : The compile callback reads the conflict analysis with `.asData?.value`, which is null while the analysis is in AsyncLoading (it is auto-triggered on selection change and can take a while for large projects — it loads every duplicate key's units). If the user clicks Compile before the analysis completes, `analysis` is null, the 'unresolved conflicts' warning dialog is skipped entirely, and `_buildExcludedKeysByProject()` (compilation_editor_notifier.dart:206, same `.asData?.value` pattern) returns no exclusions — so the pack is compiled with conflicting keys merged last-writer-wins and the user never sees the warning the UI is designed to show. The existing `canProceedWithCompilation` provider (compilation_conflict_providers.dart:113) returns false while loading precisely to gate this, but the compile button never consults it.

```
final analysis =
          ref.read(compilationConflictAnalysisProvider).asData?.value;
      if (analysis != null && analysis.hasUnresolvedConflicts) {
        final proceed = await _showConflictWarningDialog(analysis);
```

### _uploadStartTime never reset — elapsed timer shows stale, inflated time and stops ticking on retry publish

fichier `lib/features/steam_publish/screens/workshop_publish_screen.dart:363` · source feat-steam-pack

**Problème** : The timer is started only when `state.isActive && _uploadStartTime == null`, but `_uploadStartTime` is never set back to null when an upload ends (only `_elapsedTimer` is cancelled at line 369-372). After a failed/cancelled publish the user clicks Retry (notifier reset to idle) and then Update again: on the second upload `_uploadStartTime` is still non-null, so the periodic 1-second timer is never recreated. `_formatElapsed()` then computes the difference from the FIRST attempt's start time — including all idle time the user spent on the error panel and form — and only updates when unrelated rebuilds occur (progress stream events), so the displayed elapsed time is both wrong and frozen between progress updates.

```
if (state.isActive && _uploadStartTime == null) {
      _uploadStartTime = DateTime.now();
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
```

### Editing a glossary entry while a search is active leaves stale results — glossarySearchResultsProvider never invalidated

fichier `lib/features/glossary/widgets/glossary_entry_editor.dart:254` · source feat-data-misc

**Problème** : GlossaryDataGrid swaps its data source to glossarySearchResultsProvider whenever filterState.searchText is non-empty (glossary_datagrid.dart:50-61). After a successful save, the editor dialog invalidates only glossaryEntriesProvider and glossaryStatisticsProvider; no code in the repository ever invalidates glossarySearchResultsProvider (grep-confirmed). Trigger: type a search term, double-click/edit a matching entry, save — the success toast appears but the grid keeps showing the old sourceTerm/targetTerm from the cached search provider until the search text is changed. The TM feature explicitly handles this exact case (tm_providers.dart TmUpdateState: 'the grid swaps between [tmEntriesProvider] and [tmSearchResultsProvider] ... so both must be invalidated'); the glossary side misses it.

```
ref.invalidate(glossaryEntriesProvider);
      ref.invalidate(glossaryStatisticsProvider);
```

### TMX export dialog's scope and format options are never passed to the export — 'Frequently used' silently exports all entries

fichier `lib/features/translation_memory/widgets/tmx_export_dialog.dart:338` · source feat-data-misc

**Problème** : The dialog renders a 'What to export' radio group bound to _exportScope (all / frequentlyUsed) plus _includeMetadata and _includeStats toggles, but _startExport forwards only outputPath and targetLanguageCode to TmExportState.exportToTmx (whose service call ITranslationMemoryService.exportToTmx likewise accepts only those two parameters). _exportScope, _includeMetadata and _includeStats are read nowhere else in the file. Trigger: user selects 'Frequently used' (or unticks include-metadata/stats) and clicks Export — the produced TMX silently contains every entry regardless of the selection, with no warning. The user-visible result file does not match the chosen options.

```
await ref.read(tmExportStateProvider.notifier).exportToTmx(
          outputPath: _outputPath!,
          targetLanguageCode: _targetLanguage,
        );
```

### downloadInstaller leaks the IOSink (open file handle) when the HTTP download stream fails

fichier `lib/services/updates/app_update_service.dart:156` · source xcut-resources

**Problème** : downloadInstaller opens `file.openWrite()` and only reaches `await sink.close()` (line 170) on the fully-successful path. If the `await for (final chunk in response.stream)` loop throws mid-transfer (network drop, server reset, disk-full), control jumps to the catch at line 173 which returns Err without closing the sink: the OS file handle on the partially-written installer in %TEMP%\TWMT is leaked for the rest of the app session and buffered bytes are never flushed. There is no try/finally around the sink, unlike exportToTmxStreaming in lib/services/translation_memory/tmx_service.dart which closes its sink in `finally { await sink.close(); }` — the asymmetry shows the intended pattern. A retried update download then writes to the same path while the stale handle is still open.

```
final sink = file.openWrite();
...
await for (final chunk in response.stream) {
  sink.add(chunk);
  ...
}
await sink.close();   // skipped on exception
} catch (e) {
  return Err(ServiceException('Download failed: $e'));
}
```

### searchFts5 column scope filter applies only to the first OR term, so scoped TM searches leak matches from the other column

fichier `lib/repositories/mixins/translation_memory_fts_mixin.dart:139` · source xcut-data-integrity

**Problème** : _buildFts5SearchQuery returns a multi-term query like '"foo"* OR "bar"*'. searchFts5 then prefixes it with a column filter via string concatenation: 'source_text:"foo"* OR "bar"*'. In FTS5 query syntax the 'col:' specifier binds only to the immediately following phrase, not to the whole OR expression, so every term after the first is matched against ALL indexed columns. Trigger: user searches the TM with scope 'source' (or 'target') using two or more words. Consequence: rows whose translated_text (resp. source_text) contains the later words are returned even though they don't match the requested scope — wrong search results in the TM browser. The correct form is to parenthesize: 'source_text:("foo"* OR "bar"*)' or repeat the column filter per term.

```
case 'source':
          ftsMatchClause = 'source_text:$ftsQuery';
          break;
```

## Annexe — candidats réfutés par la vérification adversariale

- cancel()/stop() on an inactive batch leaves stale flags that instantly kill the next run of that batchId (`lib/services/translation/handlers/batch_progress_manager.dart:305`)
- SSE streaming decodes each chunk with utf8.decode — multi-byte characters split across chunk boundaries throw and kill the stream (`lib/services/llm/providers/anthropic_provider.dart:191`)
- getProviderStats crashes on zero matching rows: SQLite SUM() returns NULL, cast `as int` throws (`lib/services/llm/llm_service_impl.dart:591`)
- GlossaryMatcher maps match indices from a lowercased copy back onto the original text, which can misalign or throw RangeError when toLowerCase changes string length (`lib/services/glossary/utils/glossary_matcher.dart:114`)
- VDF temp filenames use millisecond timestamps - batch publish can collide and publish the wrong mod (`lib/services/steam/vdf_generator.dart:26`)
- Double-space auto-fix collapses ALL whitespace (newlines, tabs) into single spaces, corrupting multi-line translations (`lib/services/validation/translation_validation_service.dart:276`)
- BatchProgressEvent listener refreshes on every project's batch — missing projectLanguageId comparison (`lib/features/translation_editor/widgets/editor_datagrid.dart:148`)
- Create-project wizard pops with success even when pack extraction/import fails (`lib/features/projects/widgets/create_project/create_project_dialog.dart:293`)
- pack-add loops never drain process stdout and await exitCode with no timeout — possible permanent hang of pack export (`lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:219`)


