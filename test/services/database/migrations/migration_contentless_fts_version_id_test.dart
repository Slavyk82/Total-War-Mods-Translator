import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_contentless_fts_version_id.dart';
import '../../../helpers/test_bootstrap.dart';

/// Tests for [ContentlessFtsVersionIdMigration] against a database built
/// with the LEGACY broken table definition (plain `content=''`), the state
/// every existing installation is in.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseService.setTestDatabase(db);

    // Minimal translation_versions table + the LEGACY broken FTS table and
    // its triggers, exactly as old schema.sql created them.
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        unit_id TEXT NOT NULL,
        project_language_id TEXT NOT NULL,
        translated_text TEXT,
        validation_issues TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE VIRTUAL TABLE translation_versions_fts USING fts5(
          translated_text,
          validation_issues,
          version_id UNINDEXED,
          content=''
      )
    ''');
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_insert
      AFTER INSERT ON translation_versions
      WHEN new.translated_text IS NOT NULL
      BEGIN
          INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
          VALUES (new.translated_text, new.validation_issues, new.id);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_update
      AFTER UPDATE OF translated_text, validation_issues ON translation_versions
      BEGIN
          DELETE FROM translation_versions_fts WHERE version_id = old.id;
          INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
          SELECT new.translated_text, new.validation_issues, new.id
          WHERE new.translated_text IS NOT NULL;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_delete
      AFTER DELETE ON translation_versions
      BEGIN
          DELETE FROM translation_versions_fts WHERE version_id = old.id;
      END
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  Future<void> insertVersion(String id, String? text) async {
    await db.insert('translation_versions', {
      'id': id,
      'unit_id': 'unit-$id',
      'project_language_id': 'pl-1',
      'translated_text': text,
      'created_at': 1,
      'updated_at': 1,
    });
  }

  Future<List<Map<String, Object?>>> matchVersionIds(String token) {
    return db.rawQuery(
      "SELECT version_id FROM translation_versions_fts "
      "WHERE translation_versions_fts MATCH '{translated_text} : $token'",
    );
  }

  group('ContentlessFtsVersionIdMigration', () {
    test('rebuilds the table with the new options and repopulates it',
        () async {
      // Rows indexed through the LEGACY triggers (version_id lost), plus a
      // NULL-text row that must NOT be indexed.
      await insertVersion('v1', 'charge de cavalerie zarbluk');
      await insertVersion('v2', 'mur de lances grimbluk');
      await insertVersion('v3', null);

      // Sanity: the legacy table really is broken (version_id reads NULL).
      final before = await matchVersionIds('zarbluk');
      expect(before.single['version_id'], isNull,
          reason: 'precondition: legacy contentless table stores nothing');

      final migration = ContentlessFtsVersionIdMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);
      expect(await migration.isApplied(), isTrue);

      // New options present in the persisted DDL.
      final ddl = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name = 'translation_versions_fts'",
      );
      expect(ddl.single['sql'], contains('contentless_delete=1'));
      expect(ddl.single['sql'], contains('contentless_unindexed=1'));

      // Fully repopulated with readable version ids.
      expect((await matchVersionIds('zarbluk')).single['version_id'], 'v1');
      expect((await matchVersionIds('grimbluk')).single['version_id'], 'v2');
      final count = await db
          .rawQuery('SELECT COUNT(*) AS c FROM translation_versions_fts');
      expect(count.single['c'], 2,
          reason: 'NULL translated_text rows must not be indexed');
    });

    test('search-by-join works after migration', () async {
      await insertVersion('v1', 'texte distinctif kwizatz');
      await ContentlessFtsVersionIdMigration().execute();

      final rows = await db.rawQuery('''
        SELECT tv.id, tv.translated_text
        FROM translation_versions_fts fts
        INNER JOIN translation_versions tv ON fts.version_id = tv.id
        WHERE translation_versions_fts MATCH '{translated_text} : kwizatz'
      ''');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'v1');
    });

    test('recreated triggers maintain the index correctly', () async {
      await ContentlessFtsVersionIdMigration().execute();

      // INSERT trigger.
      await insertVersion('v1', 'premier oldbluk');
      expect((await matchVersionIds('oldbluk')).single['version_id'], 'v1');

      // UPDATE trigger: old token gone, new token found.
      await db.update(
        'translation_versions',
        {'translated_text': 'second newbluk'},
        where: 'id = ?',
        whereArgs: ['v1'],
      );
      expect(await matchVersionIds('oldbluk'), isEmpty);
      expect((await matchVersionIds('newbluk')).single['version_id'], 'v1');

      // DELETE trigger.
      await db.delete('translation_versions',
          where: 'id = ?', whereArgs: ['v1']);
      expect(await matchVersionIds('newbluk'), isEmpty);
    });

    test('is idempotent — second execute is a skip and loses no data',
        () async {
      await insertVersion('v1', 'texte stable fixbluk');

      expect(await ContentlessFtsVersionIdMigration().execute(), isTrue);
      expect(await ContentlessFtsVersionIdMigration().execute(), isFalse);

      expect((await matchVersionIds('fixbluk')).single['version_id'], 'v1');
    });

    test('recreates the table even if it was missing entirely', () async {
      await db.execute('DROP TRIGGER trg_translation_versions_fts_insert');
      await db.execute('DROP TRIGGER trg_translation_versions_fts_update');
      await db.execute('DROP TRIGGER trg_translation_versions_fts_delete');
      await db.execute('DROP TABLE translation_versions_fts');
      await insertVersion('v1', 'texte orphelin lostbluk');

      final migration = ContentlessFtsVersionIdMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      expect((await matchVersionIds('lostbluk')).single['version_id'], 'v1');
    });
  });
}
