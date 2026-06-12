import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/concurrency/models/conflict_resolution.dart';

ConflictInfo _info({
  double similarity = 0.5,
  DateTime? current,
  DateTime? incoming,
}) =>
    ConflictInfo(
      id: 'c1',
      translationUnitId: 'tu',
      languageCode: 'fr',
      conflictType: ConflictType.manualVsLlm,
      currentValue: 'A',
      currentVersion: 1,
      currentSource: 'user',
      currentTimestamp: current ?? DateTime(2026, 1, 1),
      incomingValue: 'B',
      incomingVersion: 2,
      incomingSource: 'llm',
      incomingTimestamp: incoming ?? DateTime(2026, 1, 2),
      similarityScore: similarity,
      canAutoResolve: false,
      suggestedStrategy: ResolutionStrategy.keepUser,
    );

void main() {
  group('ConflictInfo', () {
    test('areNearlyIdentical is true at/above 95% similarity', () {
      expect(_info(similarity: 0.96).areNearlyIdentical, isTrue);
      expect(_info(similarity: 0.94).areNearlyIdentical, isFalse);
    });

    test('incomingIsNewer compares timestamps', () {
      expect(_info().incomingIsNewer, isTrue);
      expect(
        _info(current: DateTime(2026, 2), incoming: DateTime(2026, 1))
            .incomingIsNewer,
        isFalse,
      );
    });

    test('copyWith + equality + json round-trip', () {
      final a = _info();
      expect(a.copyWith(similarityScore: 0.99).similarityScore, 0.99);
      expect(a, equals(_info()));
      final restored = ConflictInfo.fromJson(a.toJson());
      expect(restored.id, 'c1');
      expect(restored.conflictType, ConflictType.manualVsLlm);
      expect(restored.suggestedStrategy, ResolutionStrategy.keepUser);
    });
  });

  group('ConflictResolution', () {
    ConflictResolution res() => ConflictResolution(
          conflictId: 'c1',
          strategy: ResolutionStrategy.keepNewer,
          resolvedValue: 'B',
          resolvedVersion: 3,
          resolvedSource: 'llm',
          resolvedAt: DateTime(2026, 1, 3),
          resolvedBy: 'system',
          wasAutomatic: true,
        );

    test('equality + json round-trip', () {
      final a = res();
      expect(a, equals(res()));
      expect(a.hashCode, res().hashCode);
      final restored = ConflictResolution.fromJson(a.toJson());
      expect(restored.strategy, ResolutionStrategy.keepNewer);
      expect(restored.wasAutomatic, isTrue);
    });
  });

  group('ConflictResolutionConfig', () {
    test('default config exposes the documented thresholds', () {
      const c = ConflictResolutionConfig.defaultConfig;
      expect(c.autoResolveSimilarityThreshold, 0.95);
      expect(c.preferUserEdits, isTrue);
      expect(c.enableAutoMerge, isFalse);
    });

    test('json round-trip preserves overrides', () {
      const c = ConflictResolutionConfig(
        autoResolveSimilarityThreshold: 0.8,
        enableAutoMerge: true,
        concurrentEditWindowMinutes: 10,
      );
      final restored = ConflictResolutionConfig.fromJson(c.toJson());
      expect(restored.autoResolveSimilarityThreshold, 0.8);
      expect(restored.enableAutoMerge, isTrue);
      expect(restored.concurrentEditWindowMinutes, 10);
    });
  });
}
