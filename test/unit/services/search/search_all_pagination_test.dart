import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/search/search_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression tests for searchAll pagination (audit findings F4 / F12).
///
/// F12: `searchAll` used to give each of its 3 sub-searches only
/// `limit ~/ 3` rows, so a query whose matches are concentrated in ONE
/// source (here: 60 hits in translation_units) could never return more
/// than `limit ~/ 3` results (16 for the default page size of 50).
///
/// F4: `searchAll` accepted no offset, so page 2 of the default
/// 'All Fields' scope could only ever duplicate page 1. Pagination also
/// requires a DETERMINISTIC total order: equal relevance scores must be
/// broken by a stable tiebreaker so consecutive pages do not shuffle.
///
/// Note: matches are seeded in translation_units (content-backed FTS).
/// translation_versions_fts is contentless without `contentless_unindexed`,
/// so its `version_id` reads back NULL and its JOIN returns no rows — a
/// separate pre-existing defect outside the scope of these tests.
void main() {
  late Database db;
  late SearchServiceImpl service;

  const totalUnits = 60;

  String unitId(int i) => 'u-${i.toString().padLeft(2, '0')}';

  setUp(() async {
    db = await TestDatabase.openMigrated();
    service = SearchServiceImpl();

    final now = DateTime.now().millisecondsSinceEpoch;

    // 60 units all matching 'alpha', concentrated in a single source.
    // Texts have identical token counts so bm25 ranks tie — ordering must
    // fall back to a stable tiebreaker for pagination to be deterministic.
    for (var i = 0; i < totalUnits; i++) {
      await db.insert('translation_units', {
        'id': unitId(i),
        'project_id': 'project-1',
        'key': 'unit.row.k$i',
        'source_text': 'alpha translation row number $i',
        'is_obsolete': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  test(
      'searchAll returns a full page when matches are concentrated in a '
      'single source (F12: limit ~/ 3 starved concentrated results)',
      () async {
    final result = await service.searchAll('alpha', limit: 50);

    expect(result.isOk, isTrue,
        reason: 'search failed: ${result.isErr ? result.error : ''}');
    expect(
      result.value,
      hasLength(50),
      reason: '60 rows match in translation_units; a limit of 50 must '
          'return 50 results, not limit ~/ 3',
    );
  });

  test(
      'searchAll ordering is a deterministic global prefix: a smaller limit '
      'returns exactly the first N of a larger limit (required for paging)',
      () async {
    final small = await service.searchAll('alpha', limit: 30);
    final large = await service.searchAll('alpha', limit: 60);

    expect(small.isOk, isTrue,
        reason: 'search failed: ${small.isErr ? small.error : ''}');
    expect(large.isOk, isTrue,
        reason: 'search failed: ${large.isErr ? large.error : ''}');

    expect(large.value, hasLength(totalUnits));

    final smallIds = small.value.map((r) => r.id).toList();
    final largePrefixIds = large.value.take(30).map((r) => r.id).toList();
    expect(
      smallIds,
      largePrefixIds,
      reason: 'limit=30 must be a stable prefix of limit=60, otherwise '
          'page boundaries shuffle between requests',
    );
  });

  test(
      'searchAll with offset returns the next distinct slice: pages are '
      'disjoint and together cover every match (F4: no offset support)',
      () async {
    final page1 = await service.searchAll('alpha', limit: 30);
    final page2 = await service.searchAll('alpha', limit: 30, offset: 30);
    final page3 = await service.searchAll('alpha', limit: 30, offset: 60);

    expect(page1.isOk, isTrue,
        reason: 'search failed: ${page1.isErr ? page1.error : ''}');
    expect(page2.isOk, isTrue,
        reason: 'search failed: ${page2.isErr ? page2.error : ''}');
    expect(page3.isOk, isTrue,
        reason: 'search failed: ${page3.isErr ? page3.error : ''}');

    expect(page1.value, hasLength(30));
    expect(page2.value, hasLength(30));
    expect(page3.value, isEmpty,
        reason: 'offset past the last match must return an empty page');

    final page1Ids = page1.value.map((r) => r.id).toSet();
    final page2Ids = page2.value.map((r) => r.id).toSet();

    expect(page1Ids.intersection(page2Ids), isEmpty,
        reason: 'page 2 must not duplicate page 1');

    final expectedIds = {for (var i = 0; i < totalUnits; i++) unitId(i)};
    expect(page1Ids.union(page2Ids), expectedIds,
        reason: 'pages 1+2 must cover all 60 matches with no gaps');
  });
}
