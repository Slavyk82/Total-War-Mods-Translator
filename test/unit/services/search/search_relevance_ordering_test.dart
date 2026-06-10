import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/search/search_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression tests for FTS5 relevance ordering.
///
/// SQLite FTS5 `rank` = bm25(), which is NEGATIVE with more-negative =
/// better match. The query layer must order ascending (`ORDER BY rank`)
/// so that when LIMIT truncates inside SQLite, the BEST matches survive.
/// The service layer then negates the raw rank so that
/// `SearchResult.relevanceScore` is positive with higher = more relevant.
void main() {
  late Database db;
  late SearchServiceImpl service;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    service = SearchServiceImpl();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<void> insertUnit({
    required String id,
    required String sourceText,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('translation_units', {
      'id': id,
      'project_id': 'project-1',
      'key': 'unit.key.$id',
      'source_text': sourceText,
      'is_obsolete': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  // A short text saturated with the search term: by bm25 this is by far
  // the most relevant document (highest term frequency, shortest field).
  const bestText = 'cavalry cavalry cavalry';

  // Long texts mentioning the term exactly once: weak bm25 matches.
  const weakText =
      'the heavy cavalry charged across the long muddy field toward the '
      'distant enemy lines while archers and spearmen watched anxiously '
      'from the wooded hills above the river crossing near the old fort';

  test(
      'searchTranslationUnits returns best bm25 match first even when '
      'LIMIT is smaller than the number of matching rows', () async {
    // 5 weak matches + 1 strong match, searched with limit 3. With the
    // broken descending order, the strong match was truncated away inside
    // SQLite and could never be recovered downstream.
    for (var i = 0; i < 5; i++) {
      await insertUnit(id: 'weak-$i', sourceText: '$weakText $i');
    }
    await insertUnit(id: 'best', sourceText: bestText);

    final result = await service.searchTranslationUnits('cavalry', limit: 3);

    expect(result.isOk, isTrue,
        reason: 'search failed: ${result.isErr ? result.error : ''}');
    final results = result.value;
    expect(results, hasLength(3));
    expect(
      results.first.id,
      'best',
      reason: 'the most relevant bm25 match must come first',
    );
  });

  test(
      'relevanceScore is positive (negated bm25) and sorted descending '
      'so higher = more relevant holds for consumers', () async {
    await insertUnit(id: 'weak-a', sourceText: '$weakText a');
    await insertUnit(id: 'best', sourceText: bestText);
    await insertUnit(id: 'weak-b', sourceText: '$weakText b');

    final result = await service.searchTranslationUnits('cavalry', limit: 10);

    expect(result.isOk, isTrue,
        reason: 'search failed: ${result.isErr ? result.error : ''}');
    final results = result.value;
    expect(results, hasLength(3));

    for (final r in results) {
      expect(
        r.relevanceScore,
        greaterThan(0),
        reason: 'relevanceScore must be the negated (positive) bm25 rank',
      );
    }

    final scores = results.map((r) => r.relevanceScore).toList();
    final sorted = [...scores]..sort((a, b) => b.compareTo(a));
    expect(scores, sorted, reason: 'results must be ordered best-first');
    expect(results.first.id, 'best');
  });
}
