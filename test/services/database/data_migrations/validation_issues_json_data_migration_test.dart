import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/data_migrations/validation_issues_json_data_migration.dart';
import '../../../helpers/test_bootstrap.dart';

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
    // Minimal table — the service uses only these columns.
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        translated_text TEXT,
        validation_issues TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ValidationIssuesJsonDataMigration.isApplied', () {
    test('returns true on empty DB (nothing to migrate, marker written)',
        () async {
      final migration = ValidationIssuesJsonDataMigration();
      expect(await migration.isApplied(), isTrue);
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });

    test('returns true if marker is already present', () async {
      await db.execute('''
        CREATE TABLE _migration_markers (
          id TEXT PRIMARY KEY,
          applied_at INTEGER NOT NULL
        )
      ''');
      await db.insert('_migration_markers',
          {'id': 'validation_issues_json', 'applied_at': 1});
      expect(await ValidationIssuesJsonDataMigration().isApplied(), isTrue);
    });

    test('returns false when a legacy-shaped row exists', () async {
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy message]',
        'updated_at': 0,
      });
      expect(await ValidationIssuesJsonDataMigration().isApplied(), isFalse);
    });

    test('returns true (and writes marker) when all rows are already JSON',
        () async {
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '["msg1"]',
        'updated_at': 0,
      });
      final migration = ValidationIssuesJsonDataMigration();
      expect(await migration.isApplied(), isTrue);
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });
  });

  group('ValidationIssuesJsonDataMigration.execute — rewrite semantics', () {
    // Minimal schema that triggers reference. We create the 3 cascading
    // triggers before calling execute so we can assert they are restored.
    Future<void> createCascadingContext() async {
      await db.execute('''
        CREATE TABLE translation_view_cache (
          unit_id TEXT,
          project_language_id TEXT,
          translated_text TEXT,
          status TEXT,
          confidence_score REAL,
          is_manually_edited INTEGER,
          version_id TEXT,
          version_updated_at INTEGER
        )
      ''');
      // Columns the triggers reference (copied from schema.sql).
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN unit_id TEXT');
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN project_language_id TEXT');
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN status TEXT');
      await db.execute(
          'ALTER TABLE translation_versions ADD COLUMN is_manually_edited INTEGER');
      // FTS virtual table (contentless, matches schema.sql:624-629).
      await db.execute('''
        CREATE VIRTUAL TABLE translation_versions_fts USING fts5(
          translated_text, validation_issues, version_id UNINDEXED, content=''
        )
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
        CREATE TRIGGER trg_update_cache_on_version_change
        AFTER UPDATE ON translation_versions
        BEGIN
          UPDATE translation_view_cache
          SET translated_text = new.translated_text,
              status = new.status,
              confidence_score = NULL,
              is_manually_edited = new.is_manually_edited,
              version_id = new.id,
              version_updated_at = new.updated_at
          WHERE unit_id = new.unit_id
            AND project_language_id = new.project_language_id;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER trg_translation_versions_updated_at
        AFTER UPDATE ON translation_versions
        WHEN NEW.updated_at = OLD.updated_at
        BEGIN
          UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
        END
      ''');
    }

    test('rewrites legacy List.toString shape to JSON array', () async {
      await createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[msg A, msg B]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, _) {},
      );

      final row = (await db.rawQuery(
              'SELECT validation_issues FROM translation_versions WHERE id = ?',
              ['v1']))
          .single;
      expect(jsonDecode(row['validation_issues'] as String), ['msg A', 'msg B']);
    });

    test('leaves already-JSON rows untouched', () async {
      await createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '["already"]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, _) {},
      );

      final row = (await db.rawQuery(
              'SELECT validation_issues FROM translation_versions WHERE id = ?',
              ['v1']))
          .single;
      expect(row['validation_issues'], '["already"]');
    });

    test('emits monotonic progress with stable total', () async {
      await createCascadingContext();
      for (var i = 0; i < 5; i++) {
        await db.insert('translation_versions', {
          'id': 'v$i',
          'translated_text': 'hello',
          'validation_issues': '[legacy $i]',
          'updated_at': 0,
        });
      }

      final samples = <List<int>>[];
      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (p, t) => samples.add([p, t]),
      );

      expect(samples, isNotEmpty);
      expect(samples.last[0], 5);
      expect(samples.every((s) => s[1] == 5), isTrue);
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i][0], greaterThanOrEqualTo(samples[i - 1][0]));
      }
    });

    test('triggers are restored after successful run', () async {
      await createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, _) {},
      );

      final triggers = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name");
      final names = triggers.map((r) => r['name']).toList();
      expect(
          names,
          containsAll([
            'trg_translation_versions_fts_update',
            'trg_update_cache_on_version_change',
            'trg_translation_versions_updated_at',
          ]));
    });

    test('rewrites Map.toString payload (real-world legacy shape)', () async {
      // Observed in production logs: older code called `.toString()` on a
      // List<Map>, producing this exact unparseable shape. The heuristic
      // split on ", " fragments the message; we accept that for idempotence
      // and data preservation. Assertion is that the result is valid JSON.
      await createCascadingContext();
      const legacy =
          '[{type: ValidationIssueType.lengthDifference, severity: ValidationSeverity.warning, autoFixable: false, autoFixValue: null}]';
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': legacy,
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, _) {},
      );

      final raw = (await db.rawQuery(
                  'SELECT validation_issues FROM translation_versions WHERE id = ?',
                  ['v1']))
              .single['validation_issues']
          as String;
      final parsed = jsonDecode(raw);
      expect(parsed, isA<List>());
      expect((parsed as List).every((e) => e is String), isTrue);
    });

    test('second execute is a no-op on already-migrated data', () async {
      await createCascadingContext();
      await db.insert('translation_versions', {
        'id': 'v1',
        'translated_text': 'hello',
        'validation_issues': '[legacy]',
        'updated_at': 0,
      });

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, _) {},
      );
      final afterFirst = (await db.rawQuery(
              'SELECT validation_issues FROM translation_versions WHERE id = ?',
              ['v1']))
          .single['validation_issues'];

      await ValidationIssuesJsonDataMigration().execute(
        onProgress: (_, _) {},
      );
      final afterSecond = (await db.rawQuery(
              'SELECT validation_issues FROM translation_versions WHERE id = ?',
              ['v1']))
          .single['validation_issues'];

      expect(afterSecond, afterFirst);
      // Already-JSON rows take the skip branch — no rewriting happens.
    });
  });

  group('ValidationIssuesJsonDataMigration.run — end-to-end', () {
    test('marker is written after successful run', () async {
      await ValidationIssuesJsonDataMigration().run(
        onProgress: (_, _) {},
      );
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });

    test('marker still written when FTS rebuild fails', () async {
      // No FTS table exists — the rebuild command raises. Assert run
      // completes and writes the marker anyway.
      await ValidationIssuesJsonDataMigration().run(
        onProgress: (_, _) {},
      );
      final markers = await db.rawQuery(
          "SELECT 1 FROM _migration_markers WHERE id = 'validation_issues_json'");
      expect(markers, isNotEmpty);
    });
  });
}
