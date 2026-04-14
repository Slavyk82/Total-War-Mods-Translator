import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/handlers/tm_lookup_handler.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';

// Characterisation tests for TmLookupHandler.performLookup. Pinned behaviours:
// - Exact-match phase: every unit with an exact TM hit is persisted via the
//   batched transaction and excluded from the fuzzy phase (no fuzzy lookup
//   performed on already-matched units).
// - Fuzzy-match phase: only fires for units without exact matches and not
//   already translated.
// - Auto-accept: matches at or above autoAcceptTmThreshold (currently 0.85)
//   are persisted; matches below threshold are NOT persisted and NOT
//   reported in matchedIds.
// - History recording: every persisted match (exact OR fuzzy-auto) emits a
//   recordChange call tagged 'tm_exact' or 'tm_fuzzy'.
// - Cancellation: a throwing checkPauseOrCancel propagates out of
//   performLookup and aborts subsequent processing.

class _MockTmService extends Mock implements ITranslationMemoryService {}

class _MockHistoryService extends Mock implements IHistoryService {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockTransactionManager extends Mock implements TransactionManager {}

// Silent logger fake — TmLookupHandler logs heavily and we do not want
// noisy stubs for every info/debug call.
class _FakeLogger extends Fake implements ILoggingService {
  @override
  void debug(String message, [dynamic data]) {}
  @override
  void info(String message, [dynamic data]) {}
  @override
  void warning(String message, [dynamic data]) {}
  @override
  void error(String message, [dynamic error, StackTrace? stackTrace]) {}
}

// Stand-in for sqflite Transaction; the handler never actually inspects the
// object — it merely passes it through to upsertWithTransaction(), which we
// also mock. A Fake is enough to satisfy any() matchers and registerFallbackValue.
class _FakeTransaction extends Fake implements Transaction {}

class _FakeTranslationContext extends Fake implements TranslationContext {}

class _FakeTranslationUnit extends Fake implements TranslationUnit {}

class _FakeTranslationVersion extends Fake implements TranslationVersion {}

// Sentinel exception used to simulate the orchestrator-supplied
// checkPauseOrCancel callback aborting the lookup.
class _CancelledException implements Exception {
  const _CancelledException();
}

// --- Fixture helpers ---------------------------------------------------

const String _projectId = 'project-1';
const String _projectLanguageId = 'plang-1';
const String _batchId = 'batch-tm';

TranslationUnit _fakeUnit(String key, String source) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return TranslationUnit(
    id: 'unit-$key',
    projectId: _projectId,
    key: key,
    sourceText: source,
    createdAt: now,
    updatedAt: now,
  );
}

TranslationContext _fakeContext() {
  final now = DateTime.now();
  return TranslationContext(
    id: 'ctx-1',
    projectId: _projectId,
    projectLanguageId: _projectLanguageId,
    targetLanguage: 'fr',
    sourceLanguage: 'en',
    createdAt: now,
    updatedAt: now,
  );
}

TranslationProgress _initialProgress({int total = 0}) {
  return TranslationProgress(
    batchId: _batchId,
    status: TranslationProgressStatus.inProgress,
    totalUnits: total,
    processedUnits: 0,
    successfulUnits: 0,
    failedUnits: 0,
    skippedUnits: 0,
    currentPhase: TranslationPhase.initializing,
    tokensUsed: 0,
    tmReuseRate: 0.0,
    timestamp: DateTime.now(),
  );
}

TmMatch _fakeTmMatch({
  required String sourceText,
  required String targetText,
  required double similarity,
  required TmMatchType matchType,
  String? entryId,
}) {
  return TmMatch(
    entryId: entryId ?? 'entry-${sourceText.hashCode}',
    sourceText: sourceText,
    targetText: targetText,
    targetLanguageCode: 'fr',
    similarityScore: similarity,
    matchType: matchType,
    breakdown: const SimilarityBreakdown(
      levenshteinScore: 1.0,
      jaroWinklerScore: 1.0,
      tokenScore: 1.0,
      contextBoost: 0.0,
      weights: ScoreWeights.defaultWeights,
    ),
    usageCount: 1,
    lastUsedAt: DateTime.now(),
  );
}

// --- Test setup --------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTranslationContext());
    registerFallbackValue(_FakeTranslationUnit());
    registerFallbackValue(_FakeTranslationVersion());
    registerFallbackValue(_FakeTransaction());
    registerFallbackValue(<String, int>{});
    registerFallbackValue(<String>[]);
    registerFallbackValue(StackTrace.empty);
  });

  late _MockTmService tmService;
  late _MockHistoryService historyService;
  late _MockVersionRepository versionRepository;
  late _MockTransactionManager transactionManager;
  late _FakeLogger logger;
  late TmLookupHandler handler;

  // Captures every TranslationVersion the handler tries to persist via the
  // mocked transaction. Lets each test assert what was actually written to
  // the repository (translatedText, translationSource, unitId).
  late List<TranslationVersion> persistedVersions;

  setUp(() {
    tmService = _MockTmService();
    historyService = _MockHistoryService();
    versionRepository = _MockVersionRepository();
    transactionManager = _MockTransactionManager();
    logger = _FakeLogger();
    persistedVersions = [];

    // Default TM stubs: nothing matches anywhere. Individual tests override.
    when(() => tmService.findExactMatch(
          sourceText: any(named: 'sourceText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => Ok(null));
    when(() => tmService.findFuzzyMatchesIsolate(
          sourceText: any(named: 'sourceText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          minSimilarity: any(named: 'minSimilarity'),
          maxResults: any(named: 'maxResults'),
          category: any(named: 'category'),
        )).thenAnswer((_) async => Ok(const <TmMatch>[]));
    when(() => tmService.incrementUsageCountBatch(any()))
        .thenAnswer((_) async => Ok(0));

    when(() => versionRepository.getTranslatedUnitIds(
          unitIds: any(named: 'unitIds'),
          projectLanguageId: any(named: 'projectLanguageId'),
        )).thenAnswer((_) async => Ok(<String>{}));

    // Capture every persisted version. The handler ignores the return value
    // beyond awaiting; Future<void> is sufficient.
    when(() => versionRepository.upsertWithTransaction(any(), any()))
        .thenAnswer((inv) async {
      persistedVersions.add(inv.positionalArguments[1] as TranslationVersion);
    });

    // Stub executeTransaction to invoke the callback with a fake Transaction
    // and wrap its result in Ok. This drives the handler's WRITE path so
    // upsertWithTransaction is actually exercised.
    when(() => transactionManager.executeTransaction<bool>(any()))
        .thenAnswer((inv) async {
      final action =
          inv.positionalArguments[0] as Future<bool> Function(Transaction);
      final result = await action(_FakeTransaction());
      return Ok(result);
    });

    when(() => historyService.recordChange(
          versionId: any(named: 'versionId'),
          translatedText: any(named: 'translatedText'),
          status: any(named: 'status'),
          changedBy: any(named: 'changedBy'),
          changeReason: any(named: 'changeReason'),
        )).thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

    handler = TmLookupHandler(
      tmService: tmService,
      historyService: historyService,
      versionRepository: versionRepository,
      transactionManager: transactionManager,
      logger: logger,
    );
  });

  Future<void> noopCheckPauseOrCancel(String batchId) async {}
  void noopProgressUpdate(String batchId, TranslationProgress progress) {}

  group('TmLookupHandler.performLookup', () {
    test('persists every unit with an exact TM match and reports them all in '
        'matchedIds; fuzzy lookup is NOT invoked for matched units',
        () async {
      final units = [
        _fakeUnit('a', 'Hello'),
        _fakeUnit('b', 'World'),
      ];
      // Each source returns its own exact match.
      when(() => tmService.findExactMatch(
            sourceText: 'Hello',
            targetLanguageCode: 'fr',
          )).thenAnswer((_) async => Ok(_fakeTmMatch(
            sourceText: 'Hello',
            targetText: 'Bonjour',
            similarity: 1.0,
            matchType: TmMatchType.exact,
            entryId: 'entry-hello',
          )));
      when(() => tmService.findExactMatch(
            sourceText: 'World',
            targetLanguageCode: 'fr',
          )).thenAnswer((_) async => Ok(_fakeTmMatch(
            sourceText: 'World',
            targetText: 'Monde',
            similarity: 1.0,
            matchType: TmMatchType.exact,
            entryId: 'entry-world',
          )));

      final (progress, matchedIds) = await handler.performLookup(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      // Both unit IDs reported.
      expect(matchedIds, equals({'unit-a', 'unit-b'}));
      // Both versions persisted with exact-source flag.
      expect(persistedVersions, hasLength(2));
      expect(
        persistedVersions.map((v) => v.unitId).toSet(),
        equals({'unit-a', 'unit-b'}),
      );
      expect(
        persistedVersions.map((v) => v.translationSource).toSet(),
        equals({TranslationSource.tmExact}),
      );
      expect(
        persistedVersions.map((v) => v.translatedText).toSet(),
        equals({'Bonjour', 'Monde'}),
      );
      // Fuzzy lookup must not have been called: every unit was handled by
      // the exact phase and filtered out before the fuzzy phase.
      verifyNever(() => tmService.findFuzzyMatchesIsolate(
            sourceText: any(named: 'sourceText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          ));
      // Progress reflects 100% TM reuse.
      expect(progress.tmReuseRate, closeTo(1.0, 1e-9));
      expect(progress.skippedUnits, 2);
    });

    test('returns empty matchedIds when neither exact nor fuzzy lookup '
        'returns a hit; fuzzy lookup IS attempted for every unit', () async {
      final units = [
        _fakeUnit('a', 'Foo'),
        _fakeUnit('b', 'Bar'),
      ];
      // Exact + fuzzy both empty (defaults already cover this).

      final (progress, matchedIds) = await handler.performLookup(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      expect(matchedIds, isEmpty);
      expect(persistedVersions, isEmpty);
      // Fuzzy lookup attempted exactly once per unit.
      verify(() => tmService.findFuzzyMatchesIsolate(
            sourceText: 'Foo',
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          )).called(1);
      verify(() => tmService.findFuzzyMatchesIsolate(
            sourceText: 'Bar',
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          )).called(1);
      // No persistence => no usage-count batch increment.
      verifyNever(() => tmService.incrementUsageCountBatch(any()));
      expect(progress.tmReuseRate, 0.0);
      expect(progress.skippedUnits, 0);
    });

    test('auto-accepts a fuzzy match at 0.97 (well above autoAcceptTmThreshold) '
        'and persists it as tmFuzzy; tmExact is NOT used', () async {
      final units = [_fakeUnit('a', 'Hello there')];
      // No exact match (default Ok(null)).
      when(() => tmService.findFuzzyMatchesIsolate(
            sourceText: 'Hello there',
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          )).thenAnswer((_) async => Ok([
            _fakeTmMatch(
              sourceText: 'Hello there!',
              targetText: 'Bonjour ici',
              similarity: 0.97,
              matchType: TmMatchType.fuzzy,
              entryId: 'entry-fuzzy',
            ),
          ]));

      final (_, matchedIds) = await handler.performLookup(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      expect(matchedIds, equals({'unit-a'}));
      expect(persistedVersions, hasLength(1));
      final version = persistedVersions.single;
      expect(version.unitId, 'unit-a');
      // The fuzzy target text is what got persisted (proves the lookup
      // result was used, not some LLM result).
      expect(version.translatedText, 'Bonjour ici');
      // Source is tmFuzzy, never tmExact for fuzzy matches.
      expect(version.translationSource, TranslationSource.tmFuzzy);
    });

    test('does NOT persist a fuzzy match below autoAcceptTmThreshold and '
        'does NOT include the unit in matchedIds', () async {
      // The handler asks the TM service for matches at minTmSimilarity (0.85)
      // and only auto-applies those at autoAcceptTmThreshold or above.
      // Both constants currently equal 0.85, so a returned match below 0.85
      // is the only way to exercise the "no auto-accept" path. We use 0.80
      // and intentionally bypass the service's own minSimilarity filter
      // (the mock does not enforce it).
      final units = [_fakeUnit('a', 'Some source text')];
      when(() => tmService.findFuzzyMatchesIsolate(
            sourceText: any(named: 'sourceText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          )).thenAnswer((_) async => Ok([
            _fakeTmMatch(
              sourceText: 'Some other text',
              targetText: 'Quelque chose',
              similarity: 0.80,
              matchType: TmMatchType.fuzzy,
              entryId: 'entry-low',
            ),
          ]));

      final (_, matchedIds) = await handler.performLookup(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      expect(matchedIds, isEmpty);
      expect(persistedVersions, isEmpty);
      // No write transaction means no history entry either.
      verifyNever(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: any(named: 'translatedText'),
            status: any(named: 'status'),
            changedBy: any(named: 'changedBy'),
            changeReason: any(named: 'changeReason'),
          ));
    });

    test('records history with changedBy=tm_exact for an exact match and '
        'changedBy=tm_fuzzy for an auto-accepted fuzzy match', () async {
      final units = [
        _fakeUnit('exact', 'Exact source'),
        _fakeUnit('fuzzy', 'Fuzzy source'),
      ];
      when(() => tmService.findExactMatch(
            sourceText: 'Exact source',
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => Ok(_fakeTmMatch(
            sourceText: 'Exact source',
            targetText: 'Source exacte',
            similarity: 1.0,
            matchType: TmMatchType.exact,
          )));
      // 'fuzzy' unit: no exact (default Ok(null)) but a high-quality fuzzy.
      when(() => tmService.findFuzzyMatchesIsolate(
            sourceText: 'Fuzzy source',
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          )).thenAnswer((_) async => Ok([
            _fakeTmMatch(
              sourceText: 'Fuzzy source!',
              targetText: 'Source floue',
              similarity: 0.96,
              matchType: TmMatchType.fuzzy,
            ),
          ]));

      await handler.performLookup(
        batchId: _batchId,
        units: units,
        context: _fakeContext(),
        currentProgress: _initialProgress(total: units.length),
        checkPauseOrCancel: noopCheckPauseOrCancel,
        onProgressUpdate: noopProgressUpdate,
      );

      // One history entry per accepted match, tagged with the right source.
      verify(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: 'Source exacte',
            status: any(named: 'status'),
            changedBy: 'tm_exact',
            changeReason: any(named: 'changeReason'),
          )).called(1);
      verify(() => historyService.recordChange(
            versionId: any(named: 'versionId'),
            translatedText: 'Source floue',
            status: any(named: 'status'),
            changedBy: 'tm_fuzzy',
            changeReason: any(named: 'changeReason'),
          )).called(1);
    });

    test('cancellation: a throwing checkPauseOrCancel propagates out of '
        'performLookup; fuzzy phase is never reached after the abort',
        () async {
      // Two units; cancellation fires on the SECOND invocation of the
      // pause/cancel callback. The handler calls it once at the top of the
      // exact-phase loop and again at the top of the fuzzy-phase loop.
      // With a single chunk of size 2 (well under _maxConcurrentLookups=15),
      // the exact phase calls it once, then the fuzzy phase calls it again
      // — that second call is where we cancel.
      final units = [
        _fakeUnit('a', 'Hello'),
        _fakeUnit('b', 'World'),
      ];
      // Give 'a' an exact match so the exact phase actually persists
      // something before the fuzzy phase is cancelled. This lets us assert
      // partial-but-clean state.
      when(() => tmService.findExactMatch(
            sourceText: 'Hello',
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => Ok(_fakeTmMatch(
            sourceText: 'Hello',
            targetText: 'Bonjour',
            similarity: 1.0,
            matchType: TmMatchType.exact,
          )));

      var callIndex = 0;
      Future<void> cancellingCheck(String batchId) async {
        callIndex++;
        if (callIndex >= 2) {
          throw const _CancelledException();
        }
      }

      await expectLater(
        handler.performLookup(
          batchId: _batchId,
          units: units,
          context: _fakeContext(),
          currentProgress: _initialProgress(total: units.length),
          checkPauseOrCancel: cancellingCheck,
          onProgressUpdate: noopProgressUpdate,
        ),
        throwsA(isA<_CancelledException>()),
      );

      // Exact-phase work for unit 'a' completed before the cancellation.
      expect(persistedVersions, hasLength(1));
      expect(persistedVersions.single.unitId, 'unit-a');
      // Fuzzy lookup must NOT have run for any unit — the throw happened
      // at the top of the fuzzy loop, before any findFuzzyMatchesIsolate
      // call could be issued.
      verifyNever(() => tmService.findFuzzyMatchesIsolate(
            sourceText: any(named: 'sourceText'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            minSimilarity: any(named: 'minSimilarity'),
            maxResults: any(named: 'maxResults'),
            category: any(named: 'category'),
          ));
      // The TM usage-count batch increment is the FINAL step of
      // performLookup; if cancellation aborted mid-flight, it must not
      // have run (no half-committed accounting).
      verifyNever(() => tmService.incrementUsageCountBatch(any()));
    });
  });
}
