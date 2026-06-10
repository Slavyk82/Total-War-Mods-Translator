import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/search/search_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression tests for the contentless translation_versions_fts table.
///
/// schema.sql historically declared the table as plain `content=''`
/// (contentless). A plain contentless FTS5 table does NOT store any column
/// values — every read of `version_id` returns NULL — so:
///   1. The search query's `JOIN ... ON fts.version_id = tv.id` matched
///      nothing: in-app search of translated text silently returned 0 rows.
///   2. Every `DELETE FROM translation_versions_fts WHERE version_id = ...`
///      (triggers + repository maintenance) was a no-op, so stale index
///      entries accumulated forever.
///
/// The fix declares the table with `contentless_delete=1,
/// contentless_unindexed=1` (SQLite >= 3.47): UNINDEXED columns are then
/// stored and readable, and DELETE works.
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

  Future<void> seedGraph() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('projects', {
      'id': 'project-1',
      'name': 'Test Project',
      'game_installation_id': 'game-1',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('languages', {
      'id': 'lang-fr',
      'code': 'fr',
      'name': 'French',
      'native_name': 'Français',
    });
    await db.insert('project_languages', {
      'id': 'pl-1',
      'project_id': 'project-1',
      'language_id': 'lang-fr',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> insertUnit(String id, String sourceText) async {
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

  Future<void> insertVersion({
    required String id,
    required String unitId,
    required String translatedText,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('translation_versions', {
      'id': id,
      'unit_id': unitId,
      'project_language_id': 'pl-1',
      'translated_text': translatedText,
      'status': 'translated',
      'created_at': now,
      'updated_at': now,
    });
  }

  test('runtime SQLite supports contentless_delete (>= 3.47)', () async {
    final rows = await db.rawQuery('SELECT sqlite_version() AS v');
    final version = rows.single['v'] as String;
    final parts = version.split('.').map(int.parse).toList();
    // contentless_delete=1 / contentless_unindexed=1 require SQLite >= 3.47.
    expect(
      parts[0] > 3 || (parts[0] == 3 && parts[1] >= 47),
      isTrue,
      reason: 'bundled SQLite $version must be >= 3.47 for the FTS5 fix',
    );
  });

  test('FTS index stores version_id (contentless_unindexed)', () async {
    await seedGraph();
    await insertUnit('unit-1', 'cavalry charge');
    await insertVersion(
      id: 'version-1',
      unitId: 'unit-1',
      translatedText: 'charge de cavalerie zarbluk',
    );

    // RED on the old schema: version_id reads back NULL on every row
    // because plain contentless FTS5 stores nothing.
    final rows = await db.rawQuery(
      "SELECT version_id FROM translation_versions_fts "
      "WHERE translation_versions_fts MATCH '{translated_text} : zarbluk'",
    );
    expect(rows, hasLength(1));
    expect(rows.single['version_id'], 'version-1');
  });

  test('searchTranslationVersions finds rows via the version_id join',
      () async {
    await seedGraph();
    await insertUnit('unit-1', 'cavalry charge');
    await insertUnit('unit-2', 'spear wall');
    await insertVersion(
      id: 'version-1',
      unitId: 'unit-1',
      translatedText: 'charge de cavalerie zarbluk',
    );
    await insertVersion(
      id: 'version-2',
      unitId: 'unit-2',
      translatedText: 'mur de lances',
    );

    final result = await service.searchTranslationVersions('zarbluk');

    expect(result.isOk, isTrue,
        reason: 'search failed: ${result.isErr ? result.error : ''}');
    final results = result.value;
    // RED on the old schema: 0 rows despite a matching version, because
    // fts.version_id is NULL and the INNER JOIN eliminates everything.
    expect(results, hasLength(1));
    expect(results.single.id, 'version-1');
    expect(results.single.translatedText, 'charge de cavalerie zarbluk');
    expect(results.single.languageCode, 'fr');
  });

  test(
      'updating translated_text re-indexes: new token matches, old token '
      'no longer matches (contentless_delete)', () async {
    await seedGraph();
    await insertUnit('unit-1', 'cavalry charge');
    await insertVersion(
      id: 'version-1',
      unitId: 'unit-1',
      translatedText: 'ancien texte oldtokenxyz',
    );

    // Pass updated_at explicitly: trg_translation_versions_updated_at would
    // otherwise rewrite it with strftime('%s') (seconds), violating the
    // created_at <= updated_at CHECK against our millisecond timestamps.
    await db.update(
      'translation_versions',
      {
        'translated_text': 'nouveau texte newtokenxyz',
        'updated_at': DateTime.now().millisecondsSinceEpoch + 1,
      },
      where: 'id = ?',
      whereArgs: ['version-1'],
    );

    // New text must be searchable end-to-end.
    final newResult = await service.searchTranslationVersions('newtokenxyz');
    expect(newResult.isOk, isTrue,
        reason: 'search failed: ${newResult.isErr ? newResult.error : ''}');
    expect(newResult.value, hasLength(1));
    expect(newResult.value.single.id, 'version-1');

    // The OLD token must be gone from the index. RED on the old schema:
    // the trigger's DELETE ... WHERE version_id matched nothing, so the
    // stale entry survived forever.
    final stale = await db.rawQuery(
      "SELECT rowid FROM translation_versions_fts "
      "WHERE translation_versions_fts MATCH '{translated_text} : oldtokenxyz'",
    );
    expect(stale, isEmpty,
        reason: 'stale FTS entry for the old text must be deleted');
  });

  test('deleting a version removes its FTS entry', () async {
    await seedGraph();
    await insertUnit('unit-1', 'cavalry charge');
    await insertVersion(
      id: 'version-1',
      unitId: 'unit-1',
      translatedText: 'texte supprimable deltokenxyz',
    );

    await db.delete(
      'translation_versions',
      where: 'id = ?',
      whereArgs: ['version-1'],
    );

    final stale = await db.rawQuery(
      "SELECT rowid FROM translation_versions_fts "
      "WHERE translation_versions_fts MATCH '{translated_text} : deltokenxyz'",
    );
    expect(stale, isEmpty,
        reason: 'FTS entry must be deleted with its version row');
  });
}
