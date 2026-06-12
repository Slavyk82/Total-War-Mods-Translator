import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/concurrency/conflict_resolver.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';
import 'package:twmt/services/concurrency/models/conflict_resolution.dart';

import '../../../helpers/test_database.dart';

/// Unit tests for [ConflictResolver].
///
/// The resolver persists into a `conflict_resolutions` table that is NOT part
/// of schema.sql or any migration. It is reverse-engineered here from the
/// service's `_storeResolution` INSERT plus the SELECT/GROUP BY queries in
/// `getConflictHistory` / `getConflictStatistics`. Columns and their inferred
/// origin:
///   id                     -> _uuid.v4()
///   conflict_type          -> ConflictType.name        (GROUP BY in stats)
///   translation_unit_id    -> ConflictInfo.translationUnitId (history filter)
///   language_code          -> ConflictInfo.languageCode
///   translation_version_id -> metadata['translation_version_id'] (nullable)
///   current_value          -> ConflictInfo.currentValue
///   current_version        -> ConflictInfo.currentVersion
///   incoming_value         -> ConflictInfo.incomingValue
///   incoming_version       -> ConflictInfo.incomingVersion
///   resolved_value         -> ConflictResolution.resolvedValue
///   resolved_version       -> ConflictResolution.resolvedVersion
///   resolution_strategy    -> ResolutionStrategy.name  (GROUP BY in stats)
///   similarity_score       -> ConflictInfo.similarityScore (REAL)
///   is_auto_resolved       -> 0/1                       (WHERE = 1 in stats)
///   resolved_by            -> ConflictResolution.resolvedBy
///   detected_at            -> currentTimestamp.msSinceEpoch (ORDER BY in history)
///   resolved_at            -> resolvedAt.msSinceEpoch
///   metadata               -> metadata?.toString()
void main() {
  late Database db;
  late ConflictResolver resolver;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    resolver = ConflictResolver();

    // `conflict_resolutions` is not in schema/migrations; create it here,
    // reverse-engineered from _storeResolution's INSERT and the read queries.
    await db.execute('''
      CREATE TABLE conflict_resolutions (
        id TEXT PRIMARY KEY,
        conflict_type TEXT NOT NULL,
        translation_unit_id TEXT,
        language_code TEXT,
        translation_version_id TEXT,
        current_value TEXT,
        current_version INTEGER,
        incoming_value TEXT,
        incoming_version INTEGER,
        resolved_value TEXT,
        resolved_version INTEGER,
        resolution_strategy TEXT,
        similarity_score REAL,
        is_auto_resolved INTEGER,
        resolved_by TEXT,
        detected_at INTEGER,
        resolved_at INTEGER,
        metadata TEXT
      )
    ''');
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  // Helper to build a ConflictInfo directly (bypassing detection) for the
  // resolution / persistence tests.
  ConflictInfo buildConflict({
    String id = 'conflict-1',
    String translationUnitId = 'unit-1',
    String languageCode = 'fr',
    ConflictType conflictType = ConflictType.manualVsLlm,
    String currentValue = 'current text',
    int currentVersion = 1,
    String currentSource = 'user',
    DateTime? currentTimestamp,
    String incomingValue = 'incoming text',
    int incomingVersion = 1,
    String incomingSource = 'llm',
    DateTime? incomingTimestamp,
    double similarityScore = 0.5,
    bool canAutoResolve = false,
    ResolutionStrategy? suggestedStrategy,
    Map<String, dynamic>? metadata,
  }) {
    final base = DateTime(2024, 1, 1, 12);
    return ConflictInfo(
      id: id,
      translationUnitId: translationUnitId,
      languageCode: languageCode,
      conflictType: conflictType,
      currentValue: currentValue,
      currentVersion: currentVersion,
      currentSource: currentSource,
      currentTimestamp: currentTimestamp ?? base,
      incomingValue: incomingValue,
      incomingVersion: incomingVersion,
      incomingSource: incomingSource,
      // Default: incoming is NEWER than current.
      incomingTimestamp: incomingTimestamp ?? base.add(const Duration(hours: 1)),
      similarityScore: similarityScore,
      canAutoResolve: canAutoResolve,
      suggestedStrategy: suggestedStrategy,
      metadata: metadata,
    );
  }

  group('detectConflict', () {
    test('identical values give similarity 1.0 and can auto-resolve', () async {
      final ts = DateTime(2024, 1, 1, 12);
      final result = await resolver.detectConflict(
        translationUnitId: 'unit-1',
        languageCode: 'fr',
        currentValue: 'Bonjour le monde',
        currentVersion: 2,
        currentSource: 'user',
        currentTimestamp: ts,
        incomingValue: 'Bonjour le monde',
        incomingVersion: 2,
        incomingSource: 'llm',
        incomingTimestamp: ts,
        conflictType: ConflictType.manualVsLlm,
      );

      expect(result.isOk, isTrue);
      final conflict = result.value;
      expect(conflict.similarityScore, 1.0);
      // >= defaultAutoMergeThreshold (0.95) -> auto-resolvable.
      expect(conflict.canAutoResolve, isTrue);
      // Very high similarity always suggests merge.
      expect(conflict.suggestedStrategy, ResolutionStrategy.merge);
      expect(conflict.areNearlyIdentical, isTrue);
    });

    test('totally different values give low similarity, no auto-resolve',
        () async {
      final ts = DateTime(2024, 1, 1, 12);
      final result = await resolver.detectConflict(
        translationUnitId: 'unit-1',
        languageCode: 'fr',
        currentValue: 'aaaaaaaaaa',
        currentVersion: 1,
        currentSource: 'user',
        currentTimestamp: ts,
        incomingValue: 'zzzzzzzzzz',
        incomingVersion: 1,
        incomingSource: 'llm',
        incomingTimestamp: ts,
        conflictType: ConflictType.manualVsLlm,
      );

      expect(result.isOk, isTrue);
      final conflict = result.value;
      // 10 substitutions / 10 chars = similarity 0.0.
      expect(conflict.similarityScore, 0.0);
      expect(conflict.canAutoResolve, isFalse);
      // manualVsLlm below merge threshold -> keepUser.
      expect(conflict.suggestedStrategy, ResolutionStrategy.keepUser);
    });

    test('llmVsLlm with similarity >= 0.90 (but < 0.95) can auto-resolve',
        () async {
      final ts = DateTime(2024, 1, 1, 12);
      // 20 chars, 1 substitution -> distance 1 / 20 = similarity 0.95? craft
      // a 0.90-0.95 band string instead: 10 chars, 1 diff -> 0.90.
      final result = await resolver.detectConflict(
        translationUnitId: 'unit-1',
        languageCode: 'fr',
        currentValue: 'abcdefghij',
        currentVersion: 1,
        currentSource: 'batch_1',
        currentTimestamp: ts,
        incomingValue: 'abcdefghiX',
        incomingVersion: 2,
        incomingSource: 'batch_2',
        incomingTimestamp: ts.add(const Duration(minutes: 1)),
        conflictType: ConflictType.llmVsLlm,
      );

      expect(result.isOk, isTrue);
      final conflict = result.value;
      // 1 edit over length 10 -> 0.90 similarity.
      expect(conflict.similarityScore, closeTo(0.90, 1e-9));
      // llmVsLlm special-cases >= 0.90.
      expect(conflict.canAutoResolve, isTrue);
      // Below 0.95 merge threshold; llmVsLlm -> keepNewer.
      expect(conflict.suggestedStrategy, ResolutionStrategy.keepNewer);
    });

    test('manualVsManual below merge threshold suggests manualResolve',
        () async {
      final ts = DateTime(2024, 1, 1, 12);
      final result = await resolver.detectConflict(
        translationUnitId: 'unit-1',
        languageCode: 'fr',
        currentValue: 'hello there friend',
        currentVersion: 1,
        currentSource: 'user-a',
        currentTimestamp: ts,
        incomingValue: 'goodbye there enemy',
        incomingVersion: 1,
        incomingSource: 'user-b',
        incomingTimestamp: ts,
        conflictType: ConflictType.manualVsManual,
      );

      expect(result.isOk, isTrue);
      final conflict = result.value;
      expect(conflict.canAutoResolve, isFalse);
      expect(conflict.suggestedStrategy, ResolutionStrategy.manualResolve);
    });

    test('versionMismatch below merge threshold suggests manualResolve',
        () async {
      final ts = DateTime(2024, 1, 1, 12);
      final result = await resolver.detectConflict(
        translationUnitId: 'unit-1',
        languageCode: 'fr',
        currentValue: 'completely different one',
        currentVersion: 3,
        currentSource: 'user',
        currentTimestamp: ts,
        incomingValue: 'totally other thing here',
        incomingVersion: 2,
        incomingSource: 'user',
        incomingTimestamp: ts,
        conflictType: ConflictType.versionMismatch,
      );

      expect(result.isOk, isTrue);
      expect(result.value.suggestedStrategy, ResolutionStrategy.manualResolve);
    });
  });

  group('resolveConflict - strategy application', () {
    test('keepUser keeps incoming when incoming source is user', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsLlm,
        currentValue: 'llm value',
        currentSource: 'llm',
        incomingValue: 'user value',
        incomingSource: 'user',
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepUser,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'user value');
      expect(result.value.strategy, ResolutionStrategy.keepUser);
    });

    test('keepUser keeps current when incoming source is not user', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsLlm,
        currentValue: 'user value',
        currentSource: 'user',
        incomingValue: 'llm value',
        incomingSource: 'llm',
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepUser,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'user value');
    });

    test('keepLlm keeps incoming when incoming source is llm', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsLlm,
        currentValue: 'user value',
        currentSource: 'user',
        incomingValue: 'llm value',
        incomingSource: 'llm',
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepLlm,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'llm value');
    });

    test('keepLlm keeps incoming when incoming source starts with batch_',
        () async {
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsLlm,
        currentValue: 'user value',
        currentSource: 'user',
        incomingValue: 'batch value',
        incomingSource: 'batch_42',
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepLlm,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'batch value');
    });

    test('keepNewer keeps incoming when incoming timestamp is newer', () async {
      final base = DateTime(2024, 1, 1, 12);
      final conflict = buildConflict(
        conflictType: ConflictType.llmVsLlm,
        currentValue: 'older',
        currentSource: 'batch_1',
        currentTimestamp: base,
        incomingValue: 'newer',
        incomingSource: 'batch_2',
        incomingTimestamp: base.add(const Duration(hours: 1)),
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepNewer,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'newer');
    });

    test('keepOlder keeps current when incoming timestamp is newer', () async {
      final base = DateTime(2024, 1, 1, 12);
      final conflict = buildConflict(
        conflictType: ConflictType.llmVsLlm,
        currentValue: 'older',
        currentSource: 'batch_1',
        currentTimestamp: base,
        incomingValue: 'newer',
        incomingSource: 'batch_2',
        incomingTimestamp: base.add(const Duration(hours: 1)),
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepOlder,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'older');
    });

    test('keepCurrent keeps current value (versionMismatch)', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.versionMismatch,
        currentValue: 'db value',
        incomingValue: 'proposed value',
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepCurrent,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'db value');
    });

    test('discard keeps current value (lockTimeout)', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.lockTimeout,
        currentValue: 'db value',
        incomingValue: 'discarded value',
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.discard,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'db value');
    });

    test('merge with high similarity uses newer side', () async {
      final base = DateTime(2024, 1, 1, 12);
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsManual,
        currentValue: 'older value',
        currentTimestamp: base,
        incomingValue: 'newer value',
        incomingTimestamp: base.add(const Duration(hours: 1)),
        // >= default config threshold 0.95.
        similarityScore: 0.99,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.merge,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      // High similarity -> newer side (incoming is newer here).
      expect(result.value.resolvedValue, 'newer value');
    });

    test('merge with low similarity falls back to incoming value', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsManual,
        currentValue: 'current value',
        incomingValue: 'incoming value',
        // Below default config threshold 0.95.
        similarityScore: 0.50,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.merge,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'incoming value');
    });

    test('resolvedVersion is max(current, incoming) + 1', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.versionMismatch,
        currentVersion: 5,
        incomingVersion: 3,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepCurrent,
        resolvedBy: 'tester',
      );

      expect(result.isOk, isTrue);
      // max(5, 3) + 1 = 6.
      expect(result.value.resolvedVersion, 6);
    });

    test('wasAutomatic true when strategy matches suggested and canAutoResolve',
        () async {
      final conflict = buildConflict(
        conflictType: ConflictType.versionMismatch,
        canAutoResolve: true,
        suggestedStrategy: ResolutionStrategy.keepCurrent,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepCurrent,
        resolvedBy: 'system',
      );

      expect(result.isOk, isTrue);
      expect(result.value.wasAutomatic, isTrue);
    });

    test('invalid strategy for conflict type returns Err', () async {
      // keepLlm is invalid for versionMismatch.
      final conflict = buildConflict(
        conflictType: ConflictType.versionMismatch,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepLlm,
        resolvedBy: 'tester',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConflictResolutionException>());
      expect(result.error.code, 'CONFLICT_RESOLUTION_FAILED');
    });

    test('manualResolve strategy throws internally -> Err', () async {
      // manualResolve is "always valid" per _isStrategyValid, but _applyStrategy
      // throws ConflictResolutionException for it.
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsManual,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.manualResolve,
        resolvedBy: 'tester',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConflictResolutionException>());
    });
  });

  group('resolveConflict - persistence', () {
    test('stores a row in conflict_resolutions with mapped columns', () async {
      final base = DateTime(2024, 6, 1, 9);
      final conflict = buildConflict(
        id: 'persist-conflict',
        translationUnitId: 'unit-persist',
        languageCode: 'de',
        conflictType: ConflictType.manualVsLlm,
        currentValue: 'aktuell',
        currentVersion: 2,
        currentSource: 'user',
        currentTimestamp: base,
        incomingValue: 'eingehend',
        incomingVersion: 2,
        incomingSource: 'user',
        incomingTimestamp: base.add(const Duration(hours: 1)),
        similarityScore: 0.42,
        metadata: {'translation_version_id': 'tv-99'},
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepUser,
        resolvedBy: 'reviewer-7',
      );
      expect(result.isOk, isTrue);

      final rows = await db.query('conflict_resolutions');
      expect(rows.length, 1);
      final row = rows.first;
      expect(row['conflict_type'], 'manualVsLlm');
      expect(row['translation_unit_id'], 'unit-persist');
      expect(row['language_code'], 'de');
      expect(row['translation_version_id'], 'tv-99');
      expect(row['current_value'], 'aktuell');
      expect(row['current_version'], 2);
      expect(row['incoming_value'], 'eingehend');
      // keepUser with incoming source 'user' -> incoming value resolved.
      expect(row['resolved_value'], 'eingehend');
      expect(row['resolution_strategy'], 'keepUser');
      expect(row['similarity_score'], closeTo(0.42, 1e-9));
      expect(row['is_auto_resolved'], 0);
      expect(row['resolved_by'], 'reviewer-7');
      expect(row['detected_at'], base.millisecondsSinceEpoch);
    });

    test('translation_version_id is null when metadata absent', () async {
      final conflict = buildConflict(
        conflictType: ConflictType.manualVsManual,
        metadata: null,
      );

      final result = await resolver.resolveConflict(
        conflict: conflict,
        strategy: ResolutionStrategy.keepNewer,
        resolvedBy: 'tester',
      );
      expect(result.isOk, isTrue);

      final rows = await db.query('conflict_resolutions');
      expect(rows.first['translation_version_id'], isNull);
    });
  });

  group('autoResolve', () {
    test('errors when conflict cannot be auto-resolved', () async {
      final conflict = buildConflict(canAutoResolve: false);

      final result = await resolver.autoResolve(conflict: conflict);

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConflictResolutionException>());
      expect(result.error.code, 'CONFLICT_RESOLUTION_FAILED');
    });

    test('auto-resolves using suggested strategy when possible', () async {
      final base = DateTime(2024, 1, 1, 12);
      final conflict = buildConflict(
        conflictType: ConflictType.llmVsLlm,
        currentValue: 'older',
        currentSource: 'batch_1',
        currentTimestamp: base,
        incomingValue: 'newer',
        incomingSource: 'batch_2',
        incomingTimestamp: base.add(const Duration(hours: 1)),
        canAutoResolve: true,
        suggestedStrategy: ResolutionStrategy.keepNewer,
      );

      final result = await resolver.autoResolve(conflict: conflict);

      expect(result.isOk, isTrue);
      expect(result.value.resolvedValue, 'newer');
      expect(result.value.resolvedBy, 'system');
      expect(result.value.wasAutomatic, isTrue);
    });
  });

  group('mergeValues', () {
    test('identical values merge to the same value', () async {
      final result = await resolver.mergeValues(
        currentValue: 'same text',
        incomingValue: 'same text',
      );

      expect(result.isOk, isTrue);
      expect(result.value, 'same text');
    });

    test('highly similar values merge to incoming (prefer newer)', () async {
      // similarity >= 0.90, same word count -> returns incoming.
      final result = await resolver.mergeValues(
        currentValue: 'the quick brown fox jumps',
        incomingValue: 'the quick brown fox jumpz',
      );

      expect(result.isOk, isTrue);
      expect(result.value, 'the quick brown fox jumpz');
    });

    test('large word-count difference cannot auto-merge', () async {
      final result = await resolver.mergeValues(
        currentValue: 'one',
        incomingValue: 'one two three four five six seven',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConflictResolutionException>());
      expect(result.error.message, contains('word count difference too large'));
    });

    test('too-different values (similar word counts) cannot merge', () async {
      // Same word count (5), but characters too different -> similarity < 0.90.
      final result = await resolver.mergeValues(
        currentValue: 'alpha bravo charlie delta echo',
        incomingValue: 'xxxxx yyyyy zzzzz wwwww vvvvv',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConflictResolutionException>());
      expect(result.error.message, contains('too different'));
    });
  });

  group('getConflictHistory', () {
    test('returns empty list when no resolutions for the unit', () async {
      final result = await resolver.getConflictHistory(
        translationUnitId: 'no-such-unit',
      );

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('returns stored resolutions filtered by translation_unit_id ordered '
        'by detected_at DESC', () async {
      final base = DateTime(2024, 1, 1, 12);

      // Two conflicts for unit-A with different detected_at, one for unit-B.
      final older = buildConflict(
        id: 'c-old',
        translationUnitId: 'unit-A',
        conflictType: ConflictType.manualVsManual,
        currentTimestamp: base,
        incomingTimestamp: base.add(const Duration(minutes: 5)),
      );
      final newer = buildConflict(
        id: 'c-new',
        translationUnitId: 'unit-A',
        conflictType: ConflictType.manualVsManual,
        currentTimestamp: base.add(const Duration(hours: 2)),
        incomingTimestamp: base.add(const Duration(hours: 3)),
      );
      final other = buildConflict(
        id: 'c-other',
        translationUnitId: 'unit-B',
        conflictType: ConflictType.manualVsManual,
        currentTimestamp: base,
        incomingTimestamp: base.add(const Duration(minutes: 5)),
      );

      for (final c in [older, newer, other]) {
        final r = await resolver.resolveConflict(
          conflict: c,
          strategy: ResolutionStrategy.keepNewer,
          resolvedBy: 'tester',
        );
        expect(r.isOk, isTrue);
      }

      final result = await resolver.getConflictHistory(
        translationUnitId: 'unit-A',
      );

      expect(result.isOk, isTrue);
      expect(result.value.length, 2);
      // detected_at = currentTimestamp; newer first (DESC).
      expect(
        result.value.first['detected_at'],
        base.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
    });

    test('respects the limit parameter', () async {
      final base = DateTime(2024, 1, 1, 12);
      for (var i = 0; i < 5; i++) {
        final c = buildConflict(
          id: 'c-$i',
          translationUnitId: 'unit-limit',
          conflictType: ConflictType.manualVsManual,
          currentTimestamp: base.add(Duration(minutes: i)),
          incomingTimestamp: base.add(Duration(minutes: i + 10)),
        );
        await resolver.resolveConflict(
          conflict: c,
          strategy: ResolutionStrategy.keepNewer,
          resolvedBy: 'tester',
        );
      }

      final result = await resolver.getConflictHistory(
        translationUnitId: 'unit-limit',
        limit: 2,
      );

      expect(result.isOk, isTrue);
      expect(result.value.length, 2);
    });

    test('returns Err when conflict_resolutions table is missing', () async {
      await db.execute('DROP TABLE conflict_resolutions');

      final result = await resolver.getConflictHistory(
        translationUnitId: 'unit-A',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, 'CONFLICT_HISTORY_FAILED');
    });
  });

  group('getConflictStatistics', () {
    test('aggregates counts by type, strategy and auto-resolved', () async {
      final base = DateTime(2024, 1, 1, 12);

      // Two manualVsManual (keepNewer), one llmVsLlm auto-resolved keepNewer.
      final c1 = buildConflict(
        id: 's1',
        conflictType: ConflictType.manualVsManual,
        currentTimestamp: base,
        incomingTimestamp: base.add(const Duration(minutes: 1)),
      );
      final c2 = buildConflict(
        id: 's2',
        conflictType: ConflictType.manualVsManual,
        currentTimestamp: base,
        incomingTimestamp: base.add(const Duration(minutes: 1)),
      );
      final c3 = buildConflict(
        id: 's3',
        conflictType: ConflictType.llmVsLlm,
        currentSource: 'batch_1',
        incomingSource: 'batch_2',
        currentTimestamp: base,
        incomingTimestamp: base.add(const Duration(minutes: 1)),
        canAutoResolve: true,
        suggestedStrategy: ResolutionStrategy.keepNewer,
      );

      await resolver.resolveConflict(
        conflict: c1,
        strategy: ResolutionStrategy.keepNewer,
        resolvedBy: 'tester',
      );
      await resolver.resolveConflict(
        conflict: c2,
        strategy: ResolutionStrategy.keepNewer,
        resolvedBy: 'tester',
      );
      // c3 auto-resolved -> wasAutomatic true -> is_auto_resolved = 1.
      await resolver.autoResolve(conflict: c3);

      final result = await resolver.getConflictStatistics();

      expect(result.isOk, isTrue);
      final stats = result.value;
      expect(stats['auto_resolved'], 1);

      final byType = stats['by_type'] as List;
      final manualCount = byType.firstWhere(
        (e) => e['conflict_type'] == 'manualVsManual',
      )['count'];
      expect(manualCount, 2);

      final byStrategy = stats['by_strategy'] as List;
      final keepNewerCount = byStrategy.firstWhere(
        (e) => e['resolution_strategy'] == 'keepNewer',
      )['count'];
      expect(keepNewerCount, 3);
    });

    test('returns Err when conflict_resolutions table is missing', () async {
      await db.execute('DROP TABLE conflict_resolutions');

      final result = await resolver.getConflictStatistics();

      expect(result.isErr, isTrue);
      expect(result.error.code, 'CONFLICT_STATS_FAILED');
    });
  });

  group('checkForConflicts', () {
    test('returns Err CONFLICT_CHECK_FAILED due to schema column mismatch',
        () async {
      // The service selects columns 'version' and 'updated_by' from
      // translation_versions, but the migrated schema has neither (it has
      // unit_id/project_language_id/translated_text/... with no version or
      // updated_by). The query therefore raises a DatabaseException which the
      // service maps to a CONFLICT_CHECK_FAILED ConcurrencyException.
      final result = await resolver.checkForConflicts(
        translationVersionId: 'tv-1',
        currentVersion: 1,
        proposedText: 'new text',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<ConcurrencyException>());
      expect(result.error.code, 'CONFLICT_CHECK_FAILED');
    });
  });
}
