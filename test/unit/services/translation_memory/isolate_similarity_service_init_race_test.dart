import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/isolate_similarity_service.dart';

// Regression tests for the IsolateSimilarityService initialization race.
//
// Production bug: initialize() guarded re-entry with 'if (_isolate != null)
// return;' but _isolate was assigned only after 'await Isolate.spawn' and
// _sendPort only after the cross-isolate handshake. Two interleavings broke:
//
// 1. A second caller entering while the first was still awaiting
//    Isolate.spawn saw _isolate == null and spawned a DUPLICATE isolate;
//    the loser was overwritten and never killed (leak).
// 2. A caller entering between the _isolate assignment and the handshake
//    early-returned from initialize() and hit '_sendPort!.send' with
//    _sendPort still null (null-assertion error, lookup failed spuriously).
//
// Reachable: tm_lookup_handler runs up to 50 concurrent _findFuzzyMatch
// calls, each lazily calling initialize() on the cold singleton.
//
// The fix stores a single in-flight init future assigned synchronously
// before any await, so all concurrent callers await the SAME initialization
// and initialize() only completes once the handshake has finished.
void main() {
  IsolateSimilarityService? service;

  tearDown(() {
    service?.dispose();
    service = null;
  });

  List<CandidateData> candidates() => const [
        CandidateData(
          id: 'cand-1',
          sourceText: 'shield wall formation',
          translatedText: 'formation mur de boucliers',
          usageCount: 1,
          lastUsedAt: 1700000000,
        ),
      ];

  group('IsolateSimilarityService initialization race', () {
    test('concurrent initialize() calls spawn exactly one isolate', () async {
      var spawnCount = 0;
      service = IsolateSimilarityService.forTesting(
        spawn: (entryPoint, message) async {
          spawnCount++;
          // Widen the race window: keep the first caller parked in the
          // spawn await while the other callers enter initialize().
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Isolate.spawn(entryPoint, message);
        },
      );

      await Future.wait(
        List.generate(50, (_) => service!.initialize()),
      );

      expect(spawnCount, 1,
          reason: 'all concurrent callers must await the same in-flight '
              'initialization instead of spawning duplicate isolates');
    });

    test(
        'concurrent cold calculateBatchSimilarity calls all succeed '
        '(no _sendPort null assertion) with a single spawn', () async {
      var spawnCount = 0;
      service = IsolateSimilarityService.forTesting(
        spawn: (entryPoint, message) async {
          spawnCount++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Isolate.spawn(entryPoint, message);
        },
      );

      // Mirrors tm_lookup_handler's Future.wait over concurrent fuzzy
      // lookups on the cold service: every call lazily initializes.
      final results = await Future.wait(
        List.generate(
          50,
          (_) => service!.calculateBatchSimilarity(
            sourceText: 'shield wall formation',
            candidates: candidates(),
            minSimilarity: 0.5,
          ),
        ),
      );

      expect(spawnCount, 1);
      for (final result in results) {
        expect(result, hasLength(1),
            reason: 'every concurrent lookup must complete against the '
                'single shared isolate');
        expect(result.single.candidateId, 'cand-1');
      }
    });

    test('failed initialization resets state so a retry can re-init',
        () async {
      var spawnCount = 0;
      service = IsolateSimilarityService.forTesting(
        spawn: (entryPoint, message) async {
          spawnCount++;
          if (spawnCount == 1) {
            throw StateError('simulated spawn failure');
          }
          return Isolate.spawn(entryPoint, message);
        },
      );

      // All concurrent callers of the failing init get the error...
      final attempts = await Future.wait(
        List.generate(
          3,
          (_) => service!.initialize().then<Object?>(
                (_) => null,
                onError: (Object e) => e,
              ),
        ),
      );
      expect(attempts.whereType<StateError>(), hasLength(3),
          reason: 'concurrent callers share the failing init future');
      expect(spawnCount, 1);

      // ...and a later call retries from scratch and succeeds.
      await service!.initialize();
      expect(spawnCount, 2);

      final result = await service!.calculateBatchSimilarity(
        sourceText: 'shield wall formation',
        candidates: candidates(),
        minSimilarity: 0.5,
      );
      expect(result, hasLength(1));
    });

    test('initialize() after dispose() re-initializes the service', () async {
      var spawnCount = 0;
      service = IsolateSimilarityService.forTesting(
        spawn: (entryPoint, message) {
          spawnCount++;
          return Isolate.spawn(entryPoint, message);
        },
      );

      await service!.initialize();
      service!.dispose();

      final result = await service!.calculateBatchSimilarity(
        sourceText: 'shield wall formation',
        candidates: candidates(),
        minSimilarity: 0.5,
      );
      expect(spawnCount, 2);
      expect(result, hasLength(1));
    });
  });
}
