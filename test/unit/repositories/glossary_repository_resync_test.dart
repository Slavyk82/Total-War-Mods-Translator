import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/glossary_repository.dart';

import '../../helpers/fakes/fake_logger.dart';
import '../../helpers/test_database.dart';

// Regression tests for GlossaryRepository.doesMappingNeedResync.
//
// The resync detector only compared MAX(updated_at) of the entries against
// mapping.synced_at. Deleting an entry touches no sibling's updated_at, so
// after a delete the DeepL-side glossary silently kept the removed terms
// forever (no automatic resync ever fired). The mapping stores entry_count at
// sync time precisely so deletions can be detected: a count mismatch must
// also trigger a resync.
void main() {
  late Database db;
  late GlossaryRepository repo;

  // Glossary module convention: millisecond timestamps, internally coherent.
  const entryTimestamp = 1000000;
  const syncedAt = 2000000; // after all entry updates

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = GlossaryRepository(logger: FakeLogger());

    await db.insert('glossaries', {
      'id': 'g-1',
      'name': 'Test glossary',
      'game_code': 'wh3',
      'target_language_id': 'lang-fr',
      'created_at': entryTimestamp,
      'updated_at': entryTimestamp,
    });
    for (var i = 0; i < 2; i++) {
      await db.insert('glossary_entries', {
        'id': 'entry-$i',
        'glossary_id': 'g-1',
        'target_language_code': 'fr',
        'source_term': 'term $i',
        'target_term': 'terme $i',
        'is_forbidden': 0,
        'case_sensitive': 0,
        'usage_count': 0,
        'created_at': entryTimestamp,
        'updated_at': entryTimestamp,
      });
    }
    await db.insert('deepl_glossary_mappings', {
      'id': 'mapping-1',
      'twmt_glossary_id': 'g-1',
      'source_language_code': 'en',
      'target_language_code': 'fr',
      'deepl_glossary_id': 'deepl-1',
      'deepl_glossary_name': 'Test_en_fr',
      'entry_count': 2,
      'sync_status': 'synced',
      'synced_at': syncedAt,
      'created_at': syncedAt,
      'updated_at': syncedAt,
    });
  });

  tearDown(() => TestDatabase.close(db));

  Future<bool> needsResync() => repo.doesMappingNeedResync(
        twmtGlossaryId: 'g-1',
        sourceLanguageCode: 'en',
        targetLanguageCode: 'fr',
      );

  group('GlossaryRepository.doesMappingNeedResync', () {
    test('returns false when nothing changed since the sync', () async {
      expect(await needsResync(), isFalse);
    });

    test('returns true when an entry was edited after the sync', () async {
      await db.rawUpdate(
        'UPDATE glossary_entries SET updated_at = ? WHERE id = ?',
        [syncedAt + 1, 'entry-0'],
      );
      expect(await needsResync(), isTrue);
    });

    test('returns true when an entry was DELETED after the sync '
        '(count differs from mapping.entry_count)', () async {
      await db.delete('glossary_entries', where: 'id = ?', whereArgs: ['entry-0']);

      expect(
        await needsResync(),
        isTrue,
        reason: 'a deletion leaves MAX(updated_at) untouched; the persisted '
            'entry_count must be compared so DeepL stops applying removed terms',
      );
    });

    test('returns true when ALL entries for the pair were deleted', () async {
      await db.delete('glossary_entries', where: 'glossary_id = ?', whereArgs: ['g-1']);

      expect(
        await needsResync(),
        isTrue,
        reason: 'an emptied glossary must resync (mapping.entry_count is 2)',
      );
    });
  });

  group('GlossaryRepository.incrementUsageCount', () {
    test('bumping usage statistics does NOT trigger a DeepL resync', () async {
      // Sanity: in sync before the usage bump.
      expect(await needsResync(), isFalse);

      await repo.incrementUsageCount(['entry-0']);

      final rows = await db.query(
        'glossary_entries',
        columns: ['usage_count', 'updated_at'],
        where: 'id = ?',
        whereArgs: ['entry-0'],
      );
      expect(rows.single['usage_count'], 1, reason: 'usage must still increment');
      expect(
        rows.single['updated_at'],
        entryTimestamp,
        reason: 'incrementUsageCount must not touch updated_at — that column '
            'tracks content edits and drives DeepL resync',
      );
      expect(
        await needsResync(),
        isFalse,
        reason: 'a glossary match on the hot translation path must not be '
            'treated as a content edit and force a needless DeepL resync',
      );
    });
  });
}
