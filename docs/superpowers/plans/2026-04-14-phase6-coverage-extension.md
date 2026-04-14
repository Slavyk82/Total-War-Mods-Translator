# Phase 6 — Extension Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise `lib/services/` test coverage from 14.68% to ≥20% by testing the translation-handler layer and closing high-value branches deferred by Phase 5 reviewers.

**Architecture:** Five focused tasks executed subagent-driven. Each task targets a concrete testable unit — either a standalone handler class or a deferred branch on an already-tested service. Each task produces a standalone mergeable commit, preserves baseline (1059 passing / 30 failing), and raises coverage incrementally. Checkpoint at end: `flutter test --coverage` must show ≥20% on `lib/services/` (excluding `.g.dart` and `.freezed.dart`).

**Tech Stack:** Flutter Desktop Windows (SDK 3.10), Dart 3.x, `mocktail` 1.x, `Fake implements X` for rich types (precedent: `_FakeProcess`, `_FakeTokenCalculator`), real `Directory.systemTemp.createTempSync` for file I/O tests, `Stream<T>.toList()` for stream assertions.

---

## Baseline (end of Phase 5, commit `f0384ec`)

- Tests: **1059 passing / 30 failing**. The 30 failures are pre-existing in `translation_unit_repository_test.dart` and sibling repository tests; they must stay at 30.
- `flutter analyze lib/`: 0 errors.
- `lib/services/` coverage: **14.68%** (2360/16075 covered lines, excl. generated).

## Coverage math

- Current: 2360/16075 lines covered.
- Target: ≥3215 lines covered (20.0%).
- Delta needed: **~855 more covered lines**.
- Each task below estimates expected contribution. Task 6.5 is the swing task — if coverage still below 20% after 6.1–6.4, 6.5's scope expands.

## File inventory (handler sizes, for task sizing)

From `wc -l lib/services/translation/handlers/*.dart`:

| File | LOC | Task |
|------|-----|------|
| `llm_retry_handler.dart` | 91 | 6.1 |
| `translation_skip_filter.dart` (`lib/services/translation/utils/`) | 132 | 6.4 |
| `validation_persistence_handler.dart` | 274 | 6.3 |
| `llm_translation_handler.dart` | 301 | 6.2 |
| `tm_lookup_handler.dart` | 495 | 6.2 |
| `batch_progress_manager.dart` | 477 | 6.3 |
| `llm_provider_factory.dart` (`lib/services/llm/`) | 89 | 6.4 |
| `token_calculator.dart` (`lib/services/llm/utils/`) | 266 | 6.4 |

Phase 6 explicitly does NOT cover: `parallel_batch_processor.dart` (374 l.), `parallel_batch_handler.dart` (189 l.), `batch_estimation_handler.dart` (356 l.), `translation_error_recovery.dart` (437 l.), `translation_splitter.dart` (320 l.), `single_batch_processor.dart` (164 l.), `llm_cache_manager.dart` (293 l.), `llm_token_estimator.dart` (150 l.). Flagged as Phase 7 if needed.

---

## Task 6.1: `LlmRetryHandler` tests

**Files:**
- Create: `test/unit/services/translation/handlers/llm_retry_handler_test.dart`

**Source under test:** `lib/services/translation/handlers/llm_retry_handler.dart` (91 l.) — the retry/backoff orchestrator that wraps LLM provider calls, catching `LlmRateLimitException` and retrying after the header-provided `retryAfterSeconds`.

**Estimated coverage contribution:** ~70 lines (~0.4 pt).

- [ ] **Step 1: Read the source to enumerate code paths**

Read `lib/services/translation/handlers/llm_retry_handler.dart` fully. Identify:
- The public method(s) used by `LlmTranslationHandler` (grep `LlmRetryHandler` in `lib/` to find call sites).
- The retry loop structure (max attempts, backoff calculation).
- Exception types caught vs passed through.
- Any logger use (for assertion hooks).

- [ ] **Step 2: Write the test file skeleton**

Mirror the `test/unit/services/llm/openai_provider_test.dart` pattern. Include:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/handlers/llm_retry_handler.dart';

class _MockLlmService extends Mock implements ILlmService {}
class _FakeLogger extends Fake implements ILoggingService {
  @override void info(String message, [dynamic data]) {}
  @override void warning(String message, [dynamic data]) {}
  @override void error(String message, [dynamic error, StackTrace? stackTrace]) {}
  @override void debug(String message, [dynamic data]) {}
}

void main() {
  setUpAll(() {
    // registerFallbackValue(...) for any non-primitive types passed via any()
  });

  // groups go here
}
```

- [ ] **Step 3: Write tests for the core retry contract**

Cover at minimum:
1. **Success on first attempt** — LLM returns `Ok(response)`. Handler returns `Ok`, the LLM was called exactly once.
2. **Rate-limit then success** — first call throws `LlmRateLimitException(retryAfterSeconds: 1)`, second call returns `Ok`. Handler returns `Ok` after a delay. Use a fake clock or `fakeAsync` from `package:fake_async/fake_async.dart` to avoid real wall-clock waits.
3. **Rate-limit max retries exceeded** — every call throws `LlmRateLimitException`. Handler returns `Err(LlmRateLimitException)` (or wrapped) after max attempts. Assert the call count matches the configured max.
4. **Non-retryable exception** — `LlmAuthenticationException` thrown on first call. Handler returns `Err` immediately, LLM called exactly once.
5. **Retryable server error if the handler retries on 5xx** — `LlmServerException` with retryable status. Adapt based on what the source shows.

**DO NOT use real `Future.delayed` with >0 duration in tests.** Use `fakeAsync` or inject a clock, or override the handler's backoff duration to `Duration.zero` if a constructor param allows it.

- [ ] **Step 4: Run standalone to verify all green**

Run: `C:/src/flutter/bin/flutter test test/unit/services/translation/handlers/llm_retry_handler_test.dart`
Expected: all green, zero `[E]` markers.

- [ ] **Step 5: Run full suite**

Run: `C:/src/flutter/bin/flutter test`
Expected: 1059 + N passing, 30 failing (same).

- [ ] **Step 6: Run analyze**

Run: `C:/src/flutter/bin/flutter analyze test/unit/services/translation/handlers/`
Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add test/unit/services/translation/handlers/llm_retry_handler_test.dart
git commit -m "test: add retry and backoff coverage for LlmRetryHandler"
```

- [ ] **Step 8: Dispatch code review**

Use `superpowers:code-reviewer` agent (opus). If verdict is `APPROVED_WITH_NITS` or `APPROVED`, proceed to Task 6.2. If `CHANGES_REQUESTED`, dispatch a fix subagent first.

---

## Task 6.2: Translation handlers — batch A (`TmLookupHandler` + `LlmTranslationHandler`)

**Files:**
- Create: `test/unit/services/translation/handlers/tm_lookup_handler_test.dart`
- Create: `test/unit/services/translation/handlers/llm_translation_handler_test.dart`

**Sources under test:**
- `lib/services/translation/handlers/tm_lookup_handler.dart` (495 l.) — performs TM exact and fuzzy matching, auto-accepting ≥95% fuzzy, saving matched translations.
- `lib/services/translation/handlers/llm_translation_handler.dart` (301 l.) — builds the prompt, calls the LLM via `LlmRetryHandler`, parses the response, manages progress events.

**Estimated coverage contribution:** ~300 lines (~1.9 pt).

- [ ] **Step 1: Read both handler sources**

Note for each:
- Public method signatures called by the orchestrator.
- Collaborators injected (services, repositories, handlers).
- Event emission points (for `EventBus` assertions).
- Error-wrap points (where exceptions are caught and transformed).

- [ ] **Step 2: `tm_lookup_handler_test.dart` — 5-6 tests**

Cases:
1. **All units have exact match** — every unit resolves via `tmService.findExactMatch`. Handler returns progress with all units matched. No fuzzy call made. Each matched unit's translation is persisted via `versionRepository`.
2. **No TM match** — all units return `Err(NotFound)`. Handler returns progress with zero matched. Fuzzy lookup was attempted for each unit.
3. **Fuzzy auto-accept** — one unit returns a fuzzy match ≥95%. That match is auto-accepted and persisted.
4. **Fuzzy below threshold** — one unit returns a fuzzy match <95% (e.g. 90%). NOT auto-accepted; unit remains unmatched (but suggestion may be stored — verify against source).
5. **History service invocation** — on any match, `historyService.record` is called with the right action type.
6. **Cancellation mid-lookup** — the `checkPauseOrCancel` callback throws `CancelledException`. Handler propagates without corrupting state.

Pattern for test skeleton (adapt to actual method signature):
```dart
test('all units have exact match -> no fuzzy lookup', () async {
  final units = [_fakeUnit('k1', 'Hello'), _fakeUnit('k2', 'World')];
  when(() => tmService.findExactMatch(any(), any())).thenAnswer((inv) async =>
      Ok(TranslationMemoryEntry(id: 'tm1', sourceText: inv.positionalArguments[0]!, targetText: 'FR', ...)));

  final (progress, matchedIds) = await handler.performLookup(
    batchId: 'b1',
    units: units,
    context: _fakeContext(),
    currentProgress: _initialProgress(total: 2),
    checkPauseOrCancel: (_) async {},
    onProgressUpdate: (_, __) {},
  );

  expect(matchedIds, {'k1', 'k2'});
  verifyNever(() => tmService.findFuzzyMatch(any(), any()));
});
```

- [ ] **Step 3: `llm_translation_handler_test.dart` — 5-6 tests**

Cases:
1. **Happy path** — units with no TM match are sent to LLM. Response is parsed, translations returned, progress updated.
2. **Prompt builder invocation** — verify `promptBuilder.buildPrompt` is called with the right context (language pair, system prompt, TM examples).
3. **LLM failure wrapped** — `llmService.translate` returns `Err(LlmAuthenticationException)`. Handler returns the error wrapped in `Err`, NOT an uncaught throw. Progress state reflects failure.
4. **Partial batch success** — response parses translations for some units but not others (provider dropped some). Missing ones are flagged, present ones returned.
5. **TM-matched units skipped** — `tmMatchedUnitIds` param excludes those units from the LLM call. Verify via `verify(llmService.translate(req))` capturing `req.texts` — matched unit IDs must NOT appear.
6. **Cancellation token** — `getCancellationToken` returns a token flagged `isCancelled`. Handler short-circuits; `llmService.translate` not called or called with the cancellation token.

- [ ] **Step 4: Run both files standalone**

```bash
C:/src/flutter/bin/flutter test test/unit/services/translation/handlers/tm_lookup_handler_test.dart
C:/src/flutter/bin/flutter test test/unit/services/translation/handlers/llm_translation_handler_test.dart
```
Both: all green, zero `[E]`.

- [ ] **Step 5: Run full suite + analyze**

Run: `C:/src/flutter/bin/flutter test`
Expected: 1059 + N_6.1 + N_6.2 passing / 30 failing.

Run: `C:/src/flutter/bin/flutter analyze test/unit/services/translation/handlers/`
Expected: 0 errors.

- [ ] **Step 6: Commit (one commit for both files)**

```bash
git add test/unit/services/translation/handlers/tm_lookup_handler_test.dart test/unit/services/translation/handlers/llm_translation_handler_test.dart
git commit -m "test: add coverage for TmLookupHandler and LlmTranslationHandler"
```

- [ ] **Step 7: Dispatch code review**

---

## Task 6.3: Translation handlers — batch B (`ValidationPersistenceHandler` + `BatchProgressManager`)

**Files:**
- Create: `test/unit/services/translation/handlers/validation_persistence_handler_test.dart`
- Create: `test/unit/services/translation/handlers/batch_progress_manager_test.dart`

**Sources under test:**
- `lib/services/translation/handlers/validation_persistence_handler.dart` (274 l.) — validates LLM outputs, persists via `versionRepository`, updates TM via `tmService`, records history.
- `lib/services/translation/handlers/batch_progress_manager.dart` (477 l.) — broadcast `StreamController<Result<Progress, Exception>>` manager per batch, cancellation tokens, pause/resume state, `cleanup()`.

**Estimated coverage contribution:** ~300 lines (~1.9 pt).

- [ ] **Step 1: Read both sources**

- [ ] **Step 2: `validation_persistence_handler_test.dart` — 4-5 tests**

Cases:
1. **Happy validate + persist** — `validation.validateTranslation` returns no issues. Handler persists via `versionRepository.upsert`, records in history, updates TM.
2. **Validation issues present** — validator returns issues. Handler persists translation with status `validation_issues` (or equivalent). Issues are written to storage.
3. **Persist failure wrapped** — `versionRepository.upsert` returns `Err`. Handler returns wrapped error. History is NOT recorded (contract: no orphan history entries).
4. **TM update failure non-fatal** — `tmService.add` fails. Handler logs warning but still returns `Ok` (business rule: translation is saved even if TM update fails — verify against source; reframe if source behaves differently).

- [ ] **Step 3: `batch_progress_manager_test.dart` — 5-6 tests**

Cases:
1. **`getOrCreateController` returns same instance on second call for same batchId.**
2. **`updateAndEmitProgress` adds `Ok(progress)` to the stream and persists to `batchRepository.updateProgress`.**
3. **`checkPauseOrCancel` throws `CancelledException` when cancellation token is flagged.**
4. **`checkPauseOrCancel` awaits resume when paused.** Use `fakeAsync` — flip `setPaused(true)`, kick off the check, verify it hasn't completed, flip back, verify it completes.
5. **`cleanup(batchId)` closes the controller and removes it from internal maps.** Subsequent `getOrCreateController` returns a NEW controller.
6. **Event bus publishes `BatchProgressEvent` on each `updateAndEmitProgress` (if source emits it).**

- [ ] **Step 4-6: Run, analyze, commit**

```bash
git add test/unit/services/translation/handlers/validation_persistence_handler_test.dart test/unit/services/translation/handlers/batch_progress_manager_test.dart
git commit -m "test: add coverage for ValidationPersistenceHandler and BatchProgressManager"
```

- [ ] **Step 7: Dispatch code review**

---

## Task 6.4: Small-surface utility coverage

**Files:**
- Create: `test/unit/services/llm/llm_provider_factory_test.dart`
- Create: `test/unit/services/translation/utils/translation_skip_filter_test.dart`
- Create: `test/unit/services/llm/utils/token_calculator_test.dart`

**Sources:**
- `lib/services/llm/llm_provider_factory.dart` (89 l.) — registry that returns the right `ILlmProvider` for a provider code.
- `lib/services/translation/utils/translation_skip_filter.dart` (132 l.) — static `shouldSkip(String sourceText)` method matching placeholders, markup, XML tags, pure-numeric strings, etc.
- `lib/services/llm/utils/token_calculator.dart` (266 l.) — tiktoken wrapper, request/response token estimation. Must deal with the tiktoken asset-load fragility (same issue Phase 5 Task 5.4 fix addressed via DI widening in providers).

**Estimated coverage contribution:** ~250 lines (~1.6 pt).

- [ ] **Step 1: `llm_provider_factory_test.dart` — 5 tests**

1. **`getProvider('openai')` returns `OpenAiProvider`.**
2. **`getProvider('anthropic')` returns `AnthropicProvider`.**
3. **`getProvider('gemini')` returns `GeminiProvider`.**
4. **`getProvider('deepseek')` returns `DeepSeekProvider`.**
5. **`getProvider('deepl')` returns `DeepLProvider`.**
6. **`getProvider('unknown')` throws or returns null — verify actual behaviour first.**

This is the cheapest coverage per LOC in the plan. The factory touches all 5 provider constructors, so these tests alone cover most of each provider's constructor.

- [ ] **Step 2: `translation_skip_filter_test.dart` — 8-10 tests**

Read the source first. Likely patterns matched:
- Empty / whitespace-only.
- Pure numbers / decimals.
- XML tags (`<color>`, `<br/>`).
- Placeholders (`[PLACEHOLDER]`, `{0}`, `%s`).
- Markup tags (Total War–specific? check source).
- URLs / email addresses.
- Short source (<N chars).

Write one test per pattern, with a positive case (skip) and a negative case (don't skip). Pattern:
```dart
test('skip pure numeric', () {
  expect(TranslationSkipFilter.shouldSkip('42'), true);
  expect(TranslationSkipFilter.shouldSkip('Hello 42'), false);
});
```

- [ ] **Step 3: `token_calculator_test.dart` — 4-6 tests**

**Tiktoken constraint:** the `TokenCalculator` constructor loads tiktoken assets. To test it standalone without hitting the `'type List<dynamic> is not a subtype of String'` error from Phase 5 Task 5.4:
- Option A: `TestWidgetsFlutterBinding.ensureInitialized()` in `setUpAll`, accept that tests depend on asset loading at runtime.
- Option B: test only the PUBLIC behaviour via the `instance` singleton, with one test that awaits initialization explicitly.
- Option C: split `TokenCalculator` into an abstract interface + impl, inject a fake for most tests, use one integration-style test with the real impl. This is a PRODUCTION CHANGE — only do it if Options A and B both fail.

Start with Option A.

Cases:
1. **`calculateTokens("hello world")` returns a reasonable integer** (e.g. 2 for most tokenizers).
2. **`estimateRequestTokens(request)` sums system prompt + all texts.**
3. **Empty string returns 0.**
4. **Unicode / emoji strings don't crash.**

- [ ] **Step 4-6: Run, analyze, commit (one commit for all 3 files)**

```bash
git add test/unit/services/llm/llm_provider_factory_test.dart test/unit/services/translation/utils/translation_skip_filter_test.dart test/unit/services/llm/utils/token_calculator_test.dart
git commit -m "test: add coverage for LlmProviderFactory, TranslationSkipFilter, TokenCalculator"
```

- [ ] **Step 7: Dispatch code review**

---

## Task 6.5: Deferred branches on existing services (swing task)

**Decision checkpoint:** Run coverage immediately after Task 6.4.

```bash
C:/src/flutter/bin/flutter test --coverage
awk '/^SF:/{f=$0; in_svc = (f ~ /SF:lib.services./ && f !~ /\.g\.dart$/ && f !~ /\.freezed\.dart$/) ? 1 : 0} in_svc && /^DA:/{split($0, parts, ":"); split(parts[2], a, ","); total++; if (a[2]+0 > 0) hit++} END{printf "lib/services/ (excl generated): %d / %d lines (%.2f%%)\n", hit, total, (hit/total)*100}' coverage/lcov.info
```

**If coverage ≥20%:** SKIP Task 6.5 entirely. Phase 6 ✅. Go to the final checkpoint step.

**If coverage 18.0%–19.9%:** execute Task 6.5 subset A only (orchestrator deferred branches). Should close the gap.

**If coverage <18.0%:** execute Task 6.5 full (subsets A + B + C). If still <20% after, re-plan.

**Files (all extend existing test files — no new files):**
- Modify: `test/unit/services/translation/translation_orchestrator_impl_test.dart`
- Modify: `test/unit/services/steam/workshop_publish_service_test.dart`
- Modify: `test/unit/services/translation_memory/tm_search_service_test.dart`

**Estimated coverage contribution:** ~150 lines (~0.9 pt) if full subset.

### Subset A — Orchestrator deferred branches

Add to `test/unit/services/translation/translation_orchestrator_impl_test.dart`:

1. **`context.skipTranslationMemory: true`** — TM lookup is skipped entirely. `tmService.findExactMatch` is NEVER called. LLM is called for all units.
2. **Fuzzy TM match ≥95% auto-accept** — a unit returns a fuzzy match at 0.97. The unit is persisted with TM source, LLM is NOT called for that unit.
3. **`_batchRepository.getById` returns `Err`** — orchestrator logs warning, `batch` is null, event emissions use `batchNumber: 0` fallback. Workflow still proceeds for the units.
4. **Batch-validation failure (pre-workflow)** — `batchEstimationHandler.validateBatch` returns non-empty errors. Terminal event is `Err(TranslationOrchestrationException)`. Matches the memory-recorded asymmetry (pre-workflow `Err` vs mid-workflow `Ok(progress.failed)`).

### Subset B — Workshop deferred branches

Add to `test/unit/services/steam/workshop_publish_service_test.dart`:

1. **`_manager.getSteamCmdPath()` returns `Err`** — publish aborts with that error, `_processLauncher.start` never called, VDF never generated.
2. **`_vdfGenerator.generateVdf()` returns `Err`** — publish aborts after generateVdf, `_processLauncher.start` never called.
3. **Exit codes 6 and 7 → success** — two sub-tests, each asserting `Ok(result)` with the right `workshopId` despite non-zero exit.
4. **Timeout → `SteamCmdTimeoutException`** — the `_FakeProcess` `exitCode` future completes with `-1` (or the sentinel the service uses). Assert the exception type.

### Subset C — TmSearch `getEntries` coverage

Add to `test/unit/services/translation_memory/tm_search_service_test.dart`:

1. **Happy `getEntries` with language code** — `targetLanguageCode: 'fr'` → `targetLanguageId: 'lang_fr'` threaded to `repository.getWithFilters`. Returns `Ok(entries)`.
2. **`getEntries` with no language filter** — `targetLanguageCode: null` → `targetLanguageId: null`. Returns `Ok`.
3. **`getEntries` repo error → wrapped `TmServiceException`.**
4. **`getEntries` unexpected throw → wrapped `TmServiceException` with stack trace.**

- [ ] **Step 1: Determine which subsets to execute (per checkpoint above)**

- [ ] **Step 2: Add tests per chosen subsets**

- [ ] **Step 3: Run each modified file standalone**

- [ ] **Step 4: Full suite + analyze**

- [ ] **Step 5: Commit**

```bash
# Commit message depends on subsets executed. Use:
git add test/unit/services/
git commit -m "test: close deferred branches to hit Phase 6 coverage target"
```

- [ ] **Step 6: Dispatch code review on combined changes**

---

## Final checkpoint

- [ ] **Step 1: Run coverage**

```bash
C:/src/flutter/bin/flutter test --coverage
awk '/^SF:/{f=$0; in_svc = (f ~ /SF:lib.services./ && f !~ /\.g\.dart$/ && f !~ /\.freezed\.dart$/) ? 1 : 0} in_svc && /^DA:/{split($0, parts, ":"); split(parts[2], a, ","); total++; if (a[2]+0 > 0) hit++} END{printf "lib/services/ (excl generated): %d / %d lines (%.2f%%)\n", hit, total, (hit/total)*100}' coverage/lcov.info
```

- [ ] **Step 2: Verify suite integrity**

Run: `C:/src/flutter/bin/flutter test`
Expected: 1059 + total new passing / 30 failing. Failures must still be 30.

- [ ] **Step 3: Verify analyze clean**

Run: `C:/src/flutter/bin/flutter analyze lib/`
Expected: 0 errors. Info/warnings count ≤ 8 (no new ones).

- [ ] **Step 4: Update memory**

Overwrite `C:\Users\jmp\.claude\projects\E--Total-War-Mods-Translator\memory\project_refactoring_progress.md` — mark Phase 6 ✅, record final coverage number, update baseline pass count, move retired deferred debt entries.

- [ ] **Step 5: Decision**

If coverage ≥20%: Phase 6 ✅. Propose to user: merge branch, start Phase 7, or stop here.

If coverage <20% after Task 6.5 full subset: re-plan. Possible tactics: add tests for more handlers (`parallel_batch_processor`, `translation_error_recovery`), or test `llm_service_impl.dart` (the orchestration layer on top of providers).

---

## Autonomy rules (inherited from Phase 5)

Per the session-level autonomy policy:

**Auto-decide:**
- Reframe plan↔code drift when the plan doesn't match actual source.
- DI pattern = optional constructor params + `?? default` fallback.
- Mock strategy = `Fake implements X` for rich types, `Mock implements X` for interface-like classes.
- Scope = stated cases + 1-2 cheap adjacents, stop before padding.
- Commits: English, no Claude/AI mention.
- Ignore `nit` code-review concerns, flag in deferred debt.

**Escalate:**
- Production refactor >100 LOC beyond established DI-widening pattern.
- Service requires public-API widening to be testable (except TokenCalculator-style which is now precedent).
- Verdict `CHANGES_REQUESTED` from reviewer.
- Test-suite baseline regression (passing count drops).
- Coverage <18% after Task 6.5 full execution.

## Conventions (inherited from Phase 5)

- All subagents use `model: "opus"`.
- Subagent-driven: implementer → reviewer → fix-if-major.
- Test-only commits never touch production (DI-widening is a separate refactor commit).
- Parallel dispatch when tasks touch disjoint files.
- Real temp dirs with `setUp`/`tearDown` for file I/O tests.
- `fakeAsync` for anything involving `Duration` > 0.
- Stream assertions via `.toList()` after the controller closes.

## Self-review summary

Spec coverage: all 8 candidate test targets identified in the memory's "Deferred technical debt" section are addressed across tasks 6.1–6.5. Handler layer covered by 6.1–6.3. Utilities by 6.4. Deferred branches on already-tested services by 6.5.

Placeholder scan: no TBDs or "add appropriate error handling" — each case has concrete cases listed.

Type consistency: the test method signatures use `TranslationMemoryEntry`, `TranslationUnit`, `TranslationContext`, `TranslationProgress`, `LlmRequest` — all matching types already used in the existing Phase 5 test files.

Execution handoff: subagent-driven, opus, per-task dispatch.
