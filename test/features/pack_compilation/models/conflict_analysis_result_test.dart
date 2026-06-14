import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/models/compilation_conflict.dart';
import 'package:twmt/features/pack_compilation/models/conflict_analysis_result.dart';

ConflictEntry _entry({
  String projectId = 'p1',
  String projectName = 'Project One',
  String unitId = 'u1',
  String sourceText = 'Hello',
  String? translatedText,
}) {
  return ConflictEntry(
    projectId: projectId,
    projectName: projectName,
    unitId: unitId,
    sourceText: sourceText,
    translatedText: translatedText,
  );
}

CompilationConflict _conflict({
  String id = 'c1',
  String key = 'KEY',
  CompilationConflictType type =
      CompilationConflictType.keyCollisionDifferentSource,
  CompilationConflictResolution? resolution,
  String? resolvedWithProjectId,
  String firstProjectId = 'p1',
  String secondProjectId = 'p2',
}) {
  return CompilationConflict(
    id: id,
    key: key,
    conflictType: type,
    firstEntry: _entry(projectId: firstProjectId),
    secondEntry: _entry(projectId: secondProjectId, unitId: 'u2'),
    resolution: resolution,
    resolvedWithProjectId: resolvedWithProjectId,
  );
}

void main() {
  group('ConflictAnalysisResult', () {
    test('default constructor and basic getters with no conflicts', () {
      const result = ConflictAnalysisResult(
        conflicts: [],
        summary: ConflictSummary(
          totalCount: 0,
          keyCollisionCount: 0,
          translationConflictCount: 0,
          duplicateCount: 0,
        ),
        analyzedAt: 100,
        analyzedProjectIds: ['p1', 'p2'],
        languageId: 'fr',
      );

      expect(result.hasConflicts, isFalse);
      expect(result.hasUnresolvedConflicts, isFalse);
      expect(result.unresolvedCount, 0);
      expect(result.unresolvedConflicts, isEmpty);
      expect(result.manualResolutionRequired, isEmpty);
      expect(result.analyzedAt, 100);
      expect(result.analyzedProjectIds, ['p1', 'p2']);
      expect(result.languageId, 'fr');
    });

    test('getters with a mix of conflicts', () {
      final keyCollision = _conflict(id: 'c1');
      final duplicate = _conflict(
        id: 'c2',
        type: CompilationConflictType.duplicate,
      );
      final resolved = _conflict(
        id: 'c3',
        type: CompilationConflictType.translationConflict,
        resolution: CompilationConflictResolution.useFirst,
      );

      final result = ConflictAnalysisResult(
        conflicts: [keyCollision, duplicate, resolved],
        summary: const ConflictSummary(
          totalCount: 3,
          keyCollisionCount: 1,
          translationConflictCount: 1,
          duplicateCount: 1,
          resolvedCount: 1,
        ),
        analyzedAt: 200,
        analyzedProjectIds: const ['p1', 'p2'],
        languageId: 'de',
      );

      expect(result.hasConflicts, isTrue);
      // keyCollision: unresolved + not auto-resolvable => counts
      expect(result.hasUnresolvedConflicts, isTrue);
      expect(result.unresolvedCount, 1);
      expect(result.unresolvedConflicts, [keyCollision]);
      // manualResolutionRequired excludes auto-resolvable (duplicate)
      expect(result.manualResolutionRequired, [keyCollision, resolved]);
    });

    test('hasUnresolvedConflicts false when only duplicates unresolved', () {
      final duplicate = _conflict(
        id: 'c1',
        type: CompilationConflictType.duplicate,
      );
      final result = ConflictAnalysisResult(
        conflicts: [duplicate],
        summary: const ConflictSummary(
          totalCount: 1,
          keyCollisionCount: 0,
          translationConflictCount: 0,
          duplicateCount: 1,
        ),
        analyzedAt: 1,
        analyzedProjectIds: const ['p1'],
        languageId: 'fr',
      );

      expect(result.hasUnresolvedConflicts, isFalse);
      expect(result.unresolvedCount, 0);
    });

    test('getByType filters conflicts by type', () {
      final a = _conflict(id: 'a');
      final b = _conflict(
        id: 'b',
        type: CompilationConflictType.translationConflict,
      );
      final c = _conflict(id: 'c', type: CompilationConflictType.duplicate);

      final result = ConflictAnalysisResult(
        conflicts: [a, b, c],
        summary: const ConflictSummary(
          totalCount: 3,
          keyCollisionCount: 1,
          translationConflictCount: 1,
          duplicateCount: 1,
        ),
        analyzedAt: 0,
        analyzedProjectIds: const [],
        languageId: 'fr',
      );

      expect(
        result.getByType(CompilationConflictType.keyCollisionDifferentSource),
        [a],
      );
      expect(
        result.getByType(CompilationConflictType.translationConflict),
        [b],
      );
      expect(result.getByType(CompilationConflictType.duplicate), [c]);
    });

    test('empty factory produces no conflicts', () {
      final result = ConflictAnalysisResult.empty(
        projectIds: const ['p1', 'p2'],
        languageId: 'es',
      );

      expect(result.conflicts, isEmpty);
      expect(result.hasConflicts, isFalse);
      expect(result.summary.totalCount, 0);
      expect(result.analyzedProjectIds, ['p1', 'p2']);
      expect(result.languageId, 'es');
      expect(result.analyzedAt, greaterThan(0));
    });

    test('toJson exposes mapped fields', () {
      final result = ConflictAnalysisResult(
        conflicts: [_conflict(id: 'c1')],
        summary: const ConflictSummary(
          totalCount: 1,
          keyCollisionCount: 1,
          translationConflictCount: 0,
          duplicateCount: 0,
          resolvedCount: 0,
        ),
        analyzedAt: 555,
        analyzedProjectIds: const ['p1', 'p2'],
        languageId: 'fr',
      );

      final json = result.toJson();
      expect(json['analyzed_at'], 555);
      expect(json['analyzed_project_ids'], ['p1', 'p2']);
      expect(json['language_id'], 'fr');
      expect(json['conflicts'], hasLength(1));
      expect(json['summary'], isA<ConflictSummary>());
    });

    test('toJson/fromJson round trips through encoded JSON', () {
      final result = ConflictAnalysisResult(
        conflicts: [_conflict(id: 'c1')],
        summary: const ConflictSummary(
          totalCount: 1,
          keyCollisionCount: 1,
          translationConflictCount: 0,
          duplicateCount: 0,
          resolvedCount: 0,
        ),
        analyzedAt: 555,
        analyzedProjectIds: const ['p1', 'p2'],
        languageId: 'fr',
      );

      // Encode/decode forces nested toJson on conflicts and summary.
      final decoded =
          jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>;
      final restored = ConflictAnalysisResult.fromJson(decoded);

      expect(restored.analyzedAt, 555);
      expect(restored.analyzedProjectIds, ['p1', 'p2']);
      expect(restored.languageId, 'fr');
      expect(restored.conflicts.single.id, 'c1');
      expect(
        restored.conflicts.single.conflictType,
        CompilationConflictType.keyCollisionDifferentSource,
      );
      expect(restored.summary.totalCount, 1);
    });

    group('withResolvedConflicts', () {
      test('keeps already-resolved conflicts untouched', () {
        final alreadyResolved = _conflict(
          id: 'c1',
          resolution: CompilationConflictResolution.useSecond,
        );
        final result = ConflictAnalysisResult(
          conflicts: [alreadyResolved],
          summary: const ConflictSummary(
            totalCount: 1,
            keyCollisionCount: 1,
            translationConflictCount: 0,
            duplicateCount: 0,
            resolvedCount: 1,
          ),
          analyzedAt: 10,
          analyzedProjectIds: const ['p1', 'p2'],
          languageId: 'fr',
        );

        final updated = result.withResolvedConflicts(
          const CompilationConflictResolutions(),
        );

        final conflict = updated.conflicts.single;
        expect(conflict.resolution, CompilationConflictResolution.useSecond);
        expect(conflict.isResolved, isTrue);
        // Summary recomputed
        expect(updated.summary.totalCount, 1);
        expect(updated.summary.resolvedCount, 1);
        expect(updated.summary.keyCollisionCount, 1);
        // Other fields carried over
        expect(updated.analyzedAt, 10);
        expect(updated.analyzedProjectIds, ['p1', 'p2']);
        expect(updated.languageId, 'fr');
      });

      test('applies explicit resolution with project id', () {
        final conflict = _conflict(id: 'c1');
        final result = ConflictAnalysisResult(
          conflicts: [conflict],
          summary: const ConflictSummary(
            totalCount: 1,
            keyCollisionCount: 1,
            translationConflictCount: 0,
            duplicateCount: 0,
          ),
          analyzedAt: 10,
          analyzedProjectIds: const ['p1', 'p2'],
          languageId: 'fr',
        );

        final resolutions = const CompilationConflictResolutions()
            .setResolution(
          'c1',
          CompilationConflictResolution.useSecond,
          'p2',
        );

        final updated = result.withResolvedConflicts(resolutions);
        final resolved = updated.conflicts.single;
        expect(resolved.resolution, CompilationConflictResolution.useSecond);
        expect(resolved.resolvedWithProjectId, 'p2');
        expect(updated.summary.resolvedCount, 1);
      });

      test('auto-resolves duplicates when no explicit resolution', () {
        final duplicate = _conflict(
          id: 'c1',
          type: CompilationConflictType.duplicate,
          firstProjectId: 'pFirst',
        );
        final result = ConflictAnalysisResult(
          conflicts: [duplicate],
          summary: const ConflictSummary(
            totalCount: 1,
            keyCollisionCount: 0,
            translationConflictCount: 0,
            duplicateCount: 1,
          ),
          analyzedAt: 10,
          analyzedProjectIds: const ['pFirst', 'p2'],
          languageId: 'fr',
        );

        final updated = result.withResolvedConflicts(
          const CompilationConflictResolutions(),
        );

        final resolved = updated.conflicts.single;
        expect(resolved.resolution, CompilationConflictResolution.useFirst);
        expect(resolved.resolvedWithProjectId, 'pFirst');
        expect(updated.summary.duplicateCount, 1);
        expect(updated.summary.resolvedCount, 1);
      });

      test('leaves non-duplicate unresolved when no resolution provided', () {
        final conflict = _conflict(
          id: 'c1',
          type: CompilationConflictType.translationConflict,
        );
        final result = ConflictAnalysisResult(
          conflicts: [conflict],
          summary: const ConflictSummary(
            totalCount: 1,
            keyCollisionCount: 0,
            translationConflictCount: 1,
            duplicateCount: 0,
          ),
          analyzedAt: 10,
          analyzedProjectIds: const ['p1', 'p2'],
          languageId: 'fr',
        );

        final updated = result.withResolvedConflicts(
          const CompilationConflictResolutions(),
        );

        final unchanged = updated.conflicts.single;
        expect(unchanged.resolution, isNull);
        expect(unchanged.isResolved, isFalse);
        expect(updated.summary.translationConflictCount, 1);
        expect(updated.summary.resolvedCount, 0);
      });
    });
  });

  group('ConflictSummary', () {
    const summary = ConflictSummary(
      totalCount: 10,
      keyCollisionCount: 3,
      translationConflictCount: 2,
      duplicateCount: 5,
      resolvedCount: 4,
    );

    test('computed getters', () {
      expect(summary.manualResolutionRequired, 5); // 3 + 2
      expect(summary.unresolvedCount, 6); // 10 - 4
      expect(summary.allResolved, isFalse); // 4 < 10
      expect(summary.needsUserAttention, isTrue); // 5 > 4
    });

    test('allResolved true when resolved meets total', () {
      const s = ConflictSummary(
        totalCount: 2,
        keyCollisionCount: 1,
        translationConflictCount: 1,
        duplicateCount: 0,
        resolvedCount: 2,
      );
      expect(s.allResolved, isTrue);
    });

    test('needsUserAttention false when resolved >= manual required', () {
      const s = ConflictSummary(
        totalCount: 5,
        keyCollisionCount: 1,
        translationConflictCount: 1,
        duplicateCount: 3,
        resolvedCount: 2,
      );
      // manualResolutionRequired = 2, resolved = 2 => not greater
      expect(s.needsUserAttention, isFalse);
    });

    test('default resolvedCount is 0', () {
      const s = ConflictSummary(
        totalCount: 1,
        keyCollisionCount: 1,
        translationConflictCount: 0,
        duplicateCount: 0,
      );
      expect(s.resolvedCount, 0);
      expect(s.unresolvedCount, 1);
    });

    test('copyWith overrides selected fields', () {
      final copy = summary.copyWith(
        totalCount: 20,
        resolvedCount: 7,
      );
      expect(copy.totalCount, 20);
      expect(copy.resolvedCount, 7);
      // unchanged
      expect(copy.keyCollisionCount, 3);
      expect(copy.translationConflictCount, 2);
      expect(copy.duplicateCount, 5);
    });

    test('copyWith with no args returns equal copy', () {
      final copy = summary.copyWith();
      expect(copy, summary);
      expect(copy.hashCode, summary.hashCode);
    });

    test('copyWith overrides each remaining field', () {
      final copy = summary.copyWith(
        keyCollisionCount: 9,
        translationConflictCount: 8,
        duplicateCount: 7,
      );
      expect(copy.keyCollisionCount, 9);
      expect(copy.translationConflictCount, 8);
      expect(copy.duplicateCount, 7);
      expect(copy.totalCount, 10);
    });

    test('equality and hashCode', () {
      const same = ConflictSummary(
        totalCount: 10,
        keyCollisionCount: 3,
        translationConflictCount: 2,
        duplicateCount: 5,
        resolvedCount: 4,
      );
      const different = ConflictSummary(
        totalCount: 11,
        keyCollisionCount: 3,
        translationConflictCount: 2,
        duplicateCount: 5,
        resolvedCount: 4,
      );

      expect(summary, same);
      expect(summary.hashCode, same.hashCode);
      expect(summary == different, isFalse);
      // identical short-circuit
      expect(summary == summary, isTrue);
      // different type
      expect(summary == Object(), isFalse);
    });

    test('toJson/fromJson round trips', () {
      final json = summary.toJson();
      expect(json['total_count'], 10);
      expect(json['key_collision_count'], 3);
      expect(json['translation_conflict_count'], 2);
      expect(json['duplicate_count'], 5);
      expect(json['resolved_count'], 4);

      final restored = ConflictSummary.fromJson(json);
      expect(restored, summary);
    });
  });
}
