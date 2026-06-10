import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_fix_escaped_newlines.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';

/// Characterization tests for [FixEscapedNewlinesMigration] against the LEGACY
/// contentless FTS table (plain `content=''`) that existing installs have.
///
/// The migration converts stored `\n` sequences to real newlines. It used to
/// call `INSERT INTO ..._fts(..._fts) VALUES('rebuild')`, which is invalid on a
/// contentless FTS5 table and always threw (caught + logged). That call was
/// removed because the per-row UPDATE fires trg_translation_versions_fts_update,
/// which keeps the index in sync. These tests pin both outcomes: the text is
/// fixed AND the FTS index still reflects the corrected text.
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
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  Future<void> insertVersion(String id, String text) async {
    await db.insert('translation_versions', {
      'id': id,
      'unit_id': 'u-$id',
      'project_language_id': 'pl',
      'translated_text': text,
      'created_at': 0,
      'updated_at': 0,
    });
  }

  test('converts escaped newlines and leaves the FTS index searchable, '
      'without attempting an invalid contentless rebuild', () async {
    // Literal backslash-n between two tokens.
    await insertVersion('v1', r'alpha\nbeta');

    final migration = FixEscapedNewlinesMigration(logger: FakeLogger());
    final changed = await migration.execute();

    expect(changed, isTrue);

    // Stored text now contains a real newline, not a backslash-n.
    final rows = await db.query('translation_versions',
        columns: ['translated_text'], where: 'id = ?', whereArgs: ['v1']);
    expect(rows.single['translated_text'], 'alpha\nbeta');
    expect((rows.single['translated_text'] as String).contains(r'\n'), isFalse);

    // The FTS index reflects the corrected text (kept in sync by the update
    // trigger — no 'rebuild' needed). 'beta' becomes a standalone token ONLY
    // after the newline fix: before, the text `alpha\nbeta` tokenizes to
    // 'alpha' + 'nbeta', so a 'beta' match proves the index sees the fix.
    // (Contentless FTS5 stores no column values, so we probe by MATCH presence,
    // not by selecting version_id.)
    final hitBeta = await db.rawQuery(
      "SELECT rowid FROM translation_versions_fts WHERE translation_versions_fts MATCH 'beta'",
    );
    expect(hitBeta, isNotEmpty,
        reason: 'the corrected text must be searchable in the FTS index');
  });

  test('is a no-op (returns false) when there are no escaped newlines',
      () async {
    await insertVersion('v2', 'clean text');

    final migration = FixEscapedNewlinesMigration(logger: FakeLogger());
    final changed = await migration.execute();

    expect(changed, isFalse);
  });
}
