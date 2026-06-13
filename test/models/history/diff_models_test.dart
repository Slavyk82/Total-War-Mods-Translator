import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/domain/translation_version_history.dart';
import 'package:twmt/models/history/diff_models.dart';

TranslationVersionHistory buildHistory({
  String id = 'h1',
  String versionId = 'v1',
  String translatedText = 'hello',
  TranslationVersionStatus status = TranslationVersionStatus.translated,
  String changedBy = 'user_1',
  String? changeReason = 'manual_edit',
  int createdAt = 1000,
}) {
  return TranslationVersionHistory(
    id: id,
    versionId: versionId,
    translatedText: translatedText,
    status: status,
    changedBy: changedBy,
    changeReason: changeReason,
    createdAt: createdAt,
  );
}

void main() {
  group('DiffType', () {
    test('has three values', () {
      expect(DiffType.values, hasLength(3));
      expect(
        DiffType.values,
        containsAll(<DiffType>[
          DiffType.unchanged,
          DiffType.added,
          DiffType.removed,
        ]),
      );
    });
  });

  group('DiffSegment', () {
    const segment = DiffSegment(text: 'abc', type: DiffType.added);

    test('constructor stores fields', () {
      expect(segment.text, 'abc');
      expect(segment.type, DiffType.added);
    });

    test('copyWith no args returns equal instance', () {
      final copy = segment.copyWith();
      expect(copy, segment);
      expect(copy.text, 'abc');
      expect(copy.type, DiffType.added);
    });

    test('copyWith each field', () {
      expect(segment.copyWith(text: 'xyz').text, 'xyz');
      expect(segment.copyWith(text: 'xyz').type, DiffType.added);
      expect(
        segment.copyWith(type: DiffType.removed).type,
        DiffType.removed,
      );
      expect(segment.copyWith(type: DiffType.removed).text, 'abc');
    });

    test('toJson / fromJson round-trip', () {
      final json = segment.toJson();
      expect(json['text'], 'abc');
      expect(json['type'], 'added');
      final restored = DiffSegment.fromJson(json);
      expect(restored, segment);
    });

    test('fromJson handles all enum types', () {
      expect(
        DiffSegment.fromJson(<String, dynamic>{
          'text': 'a',
          'type': 'unchanged',
        }).type,
        DiffType.unchanged,
      );
      expect(
        DiffSegment.fromJson(<String, dynamic>{
          'text': 'a',
          'type': 'removed',
        }).type,
        DiffType.removed,
      );
    });

    test('equality and hashCode', () {
      const same = DiffSegment(text: 'abc', type: DiffType.added);
      const differentText = DiffSegment(text: 'zzz', type: DiffType.added);
      const differentType = DiffSegment(text: 'abc', type: DiffType.removed);

      expect(segment, same);
      expect(segment.hashCode, same.hashCode);
      expect(segment == differentText, isFalse);
      expect(segment == differentType, isFalse);
      // identical short-circuit
      expect(segment == segment, isTrue);
      // ignore: unrelated_type_equality_checks
      expect(segment == 'abc', isFalse);
    });

    test('toString', () {
      expect(segment.toString(), 'DiffSegment(text: abc, type: DiffType.added)');
    });
  });

  group('DiffStats', () {
    test('default constructor zeroes', () {
      const stats = DiffStats();
      expect(stats.charsAdded, 0);
      expect(stats.charsRemoved, 0);
      expect(stats.wordsAdded, 0);
      expect(stats.wordsRemoved, 0);
      expect(stats.charsChanged, 0);
      expect(stats.wordsChanged, 0);
    });

    test('explicit constructor', () {
      const stats = DiffStats(
        charsAdded: 1,
        charsRemoved: 2,
        wordsAdded: 3,
        wordsRemoved: 4,
        charsChanged: 5,
        wordsChanged: 6,
      );
      expect(stats.charsAdded, 1);
      expect(stats.charsRemoved, 2);
      expect(stats.wordsAdded, 3);
      expect(stats.wordsRemoved, 4);
      expect(stats.charsChanged, 5);
      expect(stats.wordsChanged, 6);
    });

    test('fromSegments computes char and word counts', () {
      final stats = DiffStats.fromSegments(const <DiffSegment>[
        DiffSegment(text: 'keep this', type: DiffType.unchanged),
        DiffSegment(text: 'new words here', type: DiffType.added),
        DiffSegment(text: 'gone now', type: DiffType.removed),
      ]);

      expect(stats.charsAdded, 'new words here'.length);
      expect(stats.charsRemoved, 'gone now'.length);
      expect(stats.wordsAdded, 3);
      expect(stats.wordsRemoved, 2);
      expect(stats.charsChanged, 'new words here'.length + 'gone now'.length);
      expect(stats.wordsChanged, 5);
    });

    test('fromSegments empty list yields zeros', () {
      final stats = DiffStats.fromSegments(const <DiffSegment>[]);
      expect(stats, const DiffStats());
    });

    test('fromSegments with whitespace-only added text counts zero words', () {
      final stats = DiffStats.fromSegments(const <DiffSegment>[
        DiffSegment(text: '   ', type: DiffType.added),
      ]);
      expect(stats.charsAdded, 3);
      expect(stats.wordsAdded, 0);
    });

    test('copyWith no args returns equal instance', () {
      const stats = DiffStats(charsAdded: 9, wordsRemoved: 4);
      final copy = stats.copyWith();
      expect(copy, stats);
    });

    test('copyWith each field', () {
      const stats = DiffStats();
      expect(stats.copyWith(charsAdded: 1).charsAdded, 1);
      expect(stats.copyWith(charsRemoved: 2).charsRemoved, 2);
      expect(stats.copyWith(wordsAdded: 3).wordsAdded, 3);
      expect(stats.copyWith(wordsRemoved: 4).wordsRemoved, 4);
      expect(stats.copyWith(charsChanged: 5).charsChanged, 5);
      expect(stats.copyWith(wordsChanged: 6).wordsChanged, 6);
    });

    test('toJson / fromJson round-trip', () {
      const stats = DiffStats(
        charsAdded: 1,
        charsRemoved: 2,
        wordsAdded: 3,
        wordsRemoved: 4,
        charsChanged: 6,
        wordsChanged: 7,
      );
      final restored = DiffStats.fromJson(stats.toJson());
      expect(restored, stats);
    });

    test('equality, hashCode, and inequality on each field', () {
      const base = DiffStats(
        charsAdded: 1,
        charsRemoved: 2,
        wordsAdded: 3,
        wordsRemoved: 4,
        charsChanged: 6,
        wordsChanged: 7,
      );
      const same = DiffStats(
        charsAdded: 1,
        charsRemoved: 2,
        wordsAdded: 3,
        wordsRemoved: 4,
        charsChanged: 6,
        wordsChanged: 7,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect(base == base, isTrue);
      // ignore: unrelated_type_equality_checks
      expect(base == 1, isFalse);
      expect(base == base.copyWith(charsAdded: 99), isFalse);
      expect(base == base.copyWith(charsRemoved: 99), isFalse);
      expect(base == base.copyWith(wordsAdded: 99), isFalse);
      expect(base == base.copyWith(wordsRemoved: 99), isFalse);
      expect(base == base.copyWith(charsChanged: 99), isFalse);
      expect(base == base.copyWith(wordsChanged: 99), isFalse);
    });

    test('toString', () {
      const stats = DiffStats(
        charsAdded: 1,
        charsRemoved: 2,
        wordsAdded: 3,
        wordsRemoved: 4,
      );
      expect(
        stats.toString(),
        'DiffStats(charsAdded: 1, charsRemoved: 2, wordsAdded: 3, wordsRemoved: 4)',
      );
    });
  });

  group('VersionComparison', () {
    final v1 = buildHistory(id: 'a', createdAt: 100);
    final v2 = buildHistory(id: 'b', createdAt: 200);
    const segments = <DiffSegment>[
      DiffSegment(text: 'x', type: DiffType.added),
    ];
    const stats = DiffStats(charsAdded: 1, charsChanged: 1);

    VersionComparison build() => VersionComparison(
          version1: v1,
          version2: v2,
          diff: segments,
          stats: stats,
        );

    test('constructor stores fields', () {
      final comparison = build();
      expect(comparison.version1, v1);
      expect(comparison.version2, v2);
      expect(comparison.diff, segments);
      expect(comparison.stats, stats);
    });

    test('copyWith no args returns equal instance', () {
      final comparison = build();
      final copy = comparison.copyWith();
      expect(copy, comparison);
    });

    test('copyWith each field', () {
      final comparison = build();
      final otherVersion = buildHistory(id: 'c');
      expect(comparison.copyWith(version1: otherVersion).version1, otherVersion);
      expect(comparison.copyWith(version2: otherVersion).version2, otherVersion);
      const otherDiff = <DiffSegment>[
        DiffSegment(text: 'y', type: DiffType.removed),
      ];
      expect(comparison.copyWith(diff: otherDiff).diff, otherDiff);
      const otherStats = DiffStats(charsRemoved: 5);
      expect(comparison.copyWith(stats: otherStats).stats, otherStats);
    });

    test('toJson exposes nested fields', () {
      final comparison = build();
      final json = comparison.toJson();
      expect(json.containsKey('version1'), isTrue);
      expect(json.containsKey('version2'), isTrue);
      expect(json['diff'], isA<List<DiffSegment>>());
      expect(json['stats'], isA<DiffStats>());
    });

    test('toJson / fromJson round-trip via jsonEncode', () {
      final comparison = build();
      final restored = VersionComparison.fromJson(
        jsonDecode(jsonEncode(comparison)) as Map<String, dynamic>,
      );
      expect(restored, comparison);
    });

    test('equality and hashCode', () {
      final comparison = build();
      final same = build();
      expect(comparison, same);
      expect(comparison.hashCode, same.hashCode);
      expect(comparison == comparison, isTrue);
      // ignore: unrelated_type_equality_checks
      expect(comparison == 'no', isFalse);
    });

    test('inequality on each field', () {
      final comparison = build();
      expect(comparison == comparison.copyWith(version1: buildHistory(id: 'z')),
          isFalse);
      expect(comparison == comparison.copyWith(version2: buildHistory(id: 'z')),
          isFalse);
      expect(
        comparison ==
            comparison.copyWith(
              diff: const <DiffSegment>[
                DiffSegment(text: 'q', type: DiffType.added),
              ],
            ),
        isFalse,
      );
      expect(
        comparison == comparison.copyWith(stats: const DiffStats(charsAdded: 9)),
        isFalse,
      );
    });

    test('listEquals detects different length and different elements', () {
      final comparison = build();
      // Different length
      expect(
        comparison ==
            comparison.copyWith(diff: const <DiffSegment>[
              DiffSegment(text: 'x', type: DiffType.added),
              DiffSegment(text: 'extra', type: DiffType.added),
            ]),
        isFalse,
      );
      // Same length, different element
      expect(
        comparison ==
            comparison.copyWith(diff: const <DiffSegment>[
              DiffSegment(text: 'different', type: DiffType.added),
            ]),
        isFalse,
      );
      // Same length, same element -> equal
      expect(
        comparison ==
            comparison.copyWith(diff: const <DiffSegment>[
              DiffSegment(text: 'x', type: DiffType.added),
            ]),
        isTrue,
      );
    });

    test('toString', () {
      final comparison = build();
      expect(
        comparison.toString(),
        'VersionComparison(version1: a, version2: b, diffSegments: 1)',
      );
    });
  });

  group('HistoryStats', () {
    test('default constructor', () {
      const stats = HistoryStats();
      expect(stats.totalEntries, 0);
      expect(stats.manualEdits, 0);
      expect(stats.llmTranslations, 0);
      expect(stats.reverts, 0);
      expect(stats.systemChanges, 0);
      expect(stats.changesByUser, isEmpty);
      expect(stats.changesByLlm, isEmpty);
      expect(stats.mostRecentChange, isNull);
      expect(stats.oldestChange, isNull);
    });

    HistoryStats buildStats() => const HistoryStats(
          totalEntries: 10,
          manualEdits: 4,
          llmTranslations: 3,
          reverts: 2,
          systemChanges: 1,
          changesByUser: <String, int>{'user_1': 4},
          changesByLlm: <String, int>{'openai': 3},
          mostRecentChange: 2000,
          oldestChange: 100,
        );

    test('explicit constructor', () {
      final stats = buildStats();
      expect(stats.totalEntries, 10);
      expect(stats.manualEdits, 4);
      expect(stats.llmTranslations, 3);
      expect(stats.reverts, 2);
      expect(stats.systemChanges, 1);
      expect(stats.changesByUser, <String, int>{'user_1': 4});
      expect(stats.changesByLlm, <String, int>{'openai': 3});
      expect(stats.mostRecentChange, 2000);
      expect(stats.oldestChange, 100);
    });

    test('copyWith no args returns equal instance', () {
      final stats = buildStats();
      expect(stats.copyWith(), stats);
    });

    test('copyWith each field', () {
      final stats = buildStats();
      expect(stats.copyWith(totalEntries: 99).totalEntries, 99);
      expect(stats.copyWith(manualEdits: 99).manualEdits, 99);
      expect(stats.copyWith(llmTranslations: 99).llmTranslations, 99);
      expect(stats.copyWith(reverts: 99).reverts, 99);
      expect(stats.copyWith(systemChanges: 99).systemChanges, 99);
      expect(
        stats.copyWith(changesByUser: <String, int>{'u': 1}).changesByUser,
        <String, int>{'u': 1},
      );
      expect(
        stats.copyWith(changesByLlm: <String, int>{'l': 1}).changesByLlm,
        <String, int>{'l': 1},
      );
      expect(stats.copyWith(mostRecentChange: 5).mostRecentChange, 5);
      expect(stats.copyWith(oldestChange: 5).oldestChange, 5);
    });

    test('copyWith leaves nullable fields when not provided', () {
      final stats = buildStats();
      final copy = stats.copyWith(totalEntries: 11);
      expect(copy.mostRecentChange, 2000);
      expect(copy.oldestChange, 100);
    });

    test('toJson / fromJson round-trip with values', () {
      final stats = buildStats();
      final restored = HistoryStats.fromJson(stats.toJson());
      expect(restored, stats);
    });

    test('toJson / fromJson round-trip with null timestamps', () {
      const stats = HistoryStats(totalEntries: 1);
      final restored = HistoryStats.fromJson(stats.toJson());
      expect(restored, stats);
      expect(restored.mostRecentChange, isNull);
      expect(restored.oldestChange, isNull);
    });

    test('equality and hashCode', () {
      final stats = buildStats();
      final same = buildStats();
      expect(stats, same);
      expect(stats.hashCode, same.hashCode);
      expect(stats == stats, isTrue);
      // ignore: unrelated_type_equality_checks
      expect(stats == 'no', isFalse);
    });

    test('inequality on each scalar field', () {
      final stats = buildStats();
      expect(stats == stats.copyWith(totalEntries: 0), isFalse);
      expect(stats == stats.copyWith(manualEdits: 0), isFalse);
      expect(stats == stats.copyWith(llmTranslations: 0), isFalse);
      expect(stats == stats.copyWith(reverts: 0), isFalse);
      expect(stats == stats.copyWith(systemChanges: 0), isFalse);
      expect(stats == stats.copyWith(mostRecentChange: 0), isFalse);
      expect(stats == stats.copyWith(oldestChange: 0), isFalse);
    });

    test('mapEquals: different length, missing key, different value, equal',
        () {
      final stats = buildStats();
      // Different length
      expect(
        stats ==
            stats.copyWith(
              changesByUser: <String, int>{'user_1': 4, 'user_2': 1},
            ),
        isFalse,
      );
      // Same length, different key (missing key branch)
      expect(
        stats == stats.copyWith(changesByUser: <String, int>{'other': 4}),
        isFalse,
      );
      // Same length, same key, different value
      expect(
        stats == stats.copyWith(changesByUser: <String, int>{'user_1': 99}),
        isFalse,
      );
      // Same map -> equal
      expect(
        stats == stats.copyWith(changesByUser: <String, int>{'user_1': 4}),
        isTrue,
      );
      // Differing llm map exercises second _mapEquals call
      expect(
        stats == stats.copyWith(changesByLlm: <String, int>{'openai': 99}),
        isFalse,
      );
    });

    test('toString', () {
      final stats = buildStats();
      expect(
        stats.toString(),
        'HistoryStats(totalEntries: 10, manualEdits: 4, llmTranslations: 3)',
      );
    });
  });
}
