import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/language_repository.dart';

import '../../helpers/test_database.dart';

// Regression tests for deleting a custom language together with its
// translation-memory entries.
//
// The old flow ran `tmRepository.deleteByLanguageId` and
// `languageRepository.delete` as two separate autocommit statements. The
// `glossaries` table also holds a RESTRICT FK to languages
// (target_language_id) that nothing pre-checked: a glossary provisioned when
// the language was attached to a project SURVIVES the language being removed
// from every project. Sequence: TM wiped first, language delete then fails on
// the glossary FK → the user has irreversibly lost their TM while the
// language is still there. The combined delete must be atomic so a blocked
// delete is a true no-op.
void main() {
  late Database db;
  late LanguageRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    // This scenario IS about FK enforcement (PRAGMA foreign_keys = ON in
    // production); re-enable it after TestDatabase turned it off.
    await db.execute('PRAGMA foreign_keys = ON');
    repo = LanguageRepository();

    await db.insert('languages', {
      'id': 'lang-en',
      'code': 'en',
      'name': 'English',
      'native_name': 'English',
      'is_active': 1,
      'is_custom': 0,
    });
    await db.insert('languages', {
      'id': 'lang-x',
      'code': 'xx',
      'name': 'Custom',
      'native_name': 'Custom',
      'is_active': 1,
      'is_custom': 1,
    });
    for (var i = 0; i < 2; i++) {
      await db.insert('translation_memory', {
        'id': 'tm-$i',
        'source_text': 'Source $i',
        'source_hash': 'hash-$i',
        'source_language_id': 'lang-en',
        'target_language_id': 'lang-x',
        'translated_text': 'Cible $i',
        'usage_count': 0,
        'created_at': 1000,
        'last_used_at': 1000,
        'updated_at': 1000,
      });
    }
  });

  tearDown(() => TestDatabase.close(db));

  Future<int> tmCount() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM translation_memory');
    return rows.first['c'] as int;
  }

  Future<int> languageCount(String id) async {
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM languages WHERE id = ?', [id]);
    return rows.first['c'] as int;
  }

  group('LanguageRepository.deleteWithTranslationMemoryCleanup', () {
    test('deletes the language AND its TM entries when nothing blocks',
        () async {
      final result = await repo.deleteWithTranslationMemoryCleanup('lang-x');

      expect(result.isOk, isTrue, reason: result.toString());
      expect(await tmCount(), 0);
      expect(await languageCount('lang-x'), 0);
    });

    test(
        'is a true no-op when a glossary still references the language: '
        'the FK failure must roll back the TM cleanup', () async {
      // Glossary provisioned for this language (survives project detachment).
      await db.insert('glossaries', {
        'id': 'g-1',
        'name': 'Orphan glossary',
        'game_code': 'wh3',
        'target_language_id': 'lang-x',
        'created_at': 1000,
        'updated_at': 1000,
      });

      final result = await repo.deleteWithTranslationMemoryCleanup('lang-x');

      expect(result.isErr, isTrue,
          reason: 'the glossary FK (ON DELETE RESTRICT) must block the delete');
      expect(await languageCount('lang-x'), 1,
          reason: 'language must still exist');
      expect(await tmCount(), 2,
          reason: 'TM entries must be preserved — a blocked delete is a no-op');
    });
  });
}
