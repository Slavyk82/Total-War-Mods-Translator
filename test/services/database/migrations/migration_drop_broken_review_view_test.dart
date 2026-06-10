import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_drop_broken_review_view.dart';
import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<bool> viewExists() async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'view' "
      "AND name = 'v_translations_needing_review'",
    );
    return rows.isNotEmpty;
  }

  /// Recreates the broken view exactly as legacy schema.sql shipped it.
  /// `tv.confidence_score` does not exist on translation_versions; SQLite
  /// accepts the CREATE VIEW (view bodies are not validated at creation
  /// time) but every full schema re-parse afterwards fails.
  Future<void> stageBrokenLegacyView() async {
    await db.execute('''
      CREATE VIEW v_translations_needing_review AS
      SELECT
          tv.id AS version_id,
          tu.project_id,
          l.code AS language_code,
          tu.key,
          tu.source_text,
          tv.translated_text,
          tv.status,
          tv.confidence_score,
          tv.validation_issues,
          tv.updated_at
      FROM translation_versions tv
      INNER JOIN translation_units tu ON tv.unit_id = tu.id
      INNER JOIN project_languages pl ON tv.project_language_id = pl.id
      INNER JOIN languages l ON pl.language_id = l.id
      WHERE tv.status IN ('needs_review', 'translated')
          AND tu.is_obsolete = 0
          AND (tv.confidence_score < 0.8 OR tv.validation_issues IS NOT NULL)
    ''');
    expect(await viewExists(), isTrue);
  }

  group('DropBrokenReviewViewMigration', () {
    test('fresh schema + migrations do not contain the broken view', () async {
      expect(await viewExists(), isFalse,
          reason: 'schema.sql must no longer create the broken view, and the '
              'registry migration must drop it from upgraded databases.');
    });

    test('isApplied returns true when the view is absent and execute is a '
        'no-op', () async {
      final migration = DropBrokenReviewViewMigration();
      expect(await migration.isApplied(), isTrue);
      expect(await migration.execute(), isFalse);
    });

    test('isApplied returns false while the legacy view exists', () async {
      await stageBrokenLegacyView();

      final migration = DropBrokenReviewViewMigration();
      expect(await migration.isApplied(), isFalse);
    });

    test('the legacy view breaks ALTER TABLE DROP COLUMN on an unrelated '
        'table, and the migration repairs it', () async {
      // A DROP COLUMN forces SQLite to re-parse every view in the schema.
      // With the broken view present it must fail — this is exactly how the
      // defect manifested in production code paths.
      await db.execute('ALTER TABLE settings ADD COLUMN probe_tmp TEXT');

      await stageBrokenLegacyView();
      await expectLater(
        db.execute('ALTER TABLE settings DROP COLUMN probe_tmp'),
        throwsA(isA<DatabaseException>()),
        reason: 'Reproduction: the broken view must make schema re-parse '
            'fail before the migration runs.',
      );

      final migration = DropBrokenReviewViewMigration();
      expect(await migration.execute(), isTrue);
      expect(await viewExists(), isFalse);
      expect(await migration.isApplied(), isTrue);

      // The real proof: schema re-parse operations work again.
      await db.execute('ALTER TABLE settings DROP COLUMN probe_tmp');
      final columns = await db.rawQuery('PRAGMA table_info(settings)');
      expect(
        columns.map((c) => c['name']),
        isNot(contains('probe_tmp')),
      );
    });
  });
}
