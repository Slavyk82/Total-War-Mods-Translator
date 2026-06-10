import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/search/search_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression test: the regex/literal-substring search joins
/// translation_versions with no DISTINCT/GROUP BY, so a unit with N versions
/// surfaced N duplicate result rows (and, with no ORDER BY, paginated
/// unstably). A source-text match must return exactly one row per unit.
void main() {
  late Database db;
  late SearchServiceImpl service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    service = SearchServiceImpl();

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('projects', {
      'id': 'p1',
      'name': 'P',
      'game_installation_id': 'g',
      'created_at': now,
      'updated_at': now,
    });
    for (final pair in [
      ['lf', 'fr'],
      ['ld', 'de'],
    ]) {
      await db.insert('languages', {
        'id': pair[0],
        'code': pair[1],
        'name': pair[1],
        'native_name': pair[1],
        'is_active': 1,
      });
      await db.insert('project_languages', {
        'id': 'pl-${pair[1]}',
        'project_id': 'p1',
        'language_id': pair[0],
        'status': 'pending',
        'progress_percent': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.insert('translation_units', {
      'id': 'u1',
      'project_id': 'p1',
      'key': 'k1',
      'source_text': 'cavalry charge',
      'is_obsolete': 0,
      'created_at': now,
      'updated_at': now,
    });
    // Two versions (fr + de) for the SAME unit.
    await db.insert('translation_versions', {
      'id': 'v-fr',
      'unit_id': 'u1',
      'project_language_id': 'pl-fr',
      'translated_text': 'charge de cavalerie',
      'is_manually_edited': 0,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('translation_versions', {
      'id': 'v-de',
      'unit_id': 'u1',
      'project_language_id': 'pl-de',
      'translated_text': 'Kavallerieangriff',
      'is_manually_edited': 0,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  test('source-text regex search returns one row per unit despite multiple '
      'translation versions', () async {
    final result = await service.searchWithRegex('cavalry', searchIn: 'source');

    expect(result.isOk, isTrue, reason: result.toString());
    final ids = result.value.map((r) => r.id).toList();
    expect(ids, ['u1'],
        reason: 'the LEFT JOIN to translation_versions must not multiply the '
            'unit into one row per version');
  });
}
