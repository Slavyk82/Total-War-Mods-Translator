import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/glossary/glossary_migration_service.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late GlossaryMigrationService service;

  setUp(() async {
    db = await TestDatabase.openMigrated(clearSeeds: true);
    service = GlossaryMigrationService();

    // Seed language + game_installation shared by tests.
    await DatabaseService.database.execute(
      "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_fr', 'fr', 'French', 'Français', 1)",
    );
    await DatabaseService.database.execute(
      "INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at) VALUES ('gi1', 'wh3', 'WH3', 0, 0)",
    );
  });
  tearDown(() async => TestDatabase.close(db));

  group('detectPendingMigration', () {
    test('returns null when nothing pending', () async {
      final result = await service.detectPendingMigration();
      expect(result, isNull);
    });

    test('detects universal glossary (game_code IS NULL)', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('gu', 'Old universal', 1, 'lang_fr', 0, 0)",
      );
      final result = await service.detectPendingMigration();
      expect(result, isNotNull);
      expect(result!.universals, hasLength(1));
      expect(result.universals.first.id, 'gu');
      expect(result.universals.first.targetLanguageCode, 'fr');
      expect(result.duplicates, isEmpty);
    });

    test('detects duplicates of (game_code, target_language_id)', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('a', 'A', 0, 'gi1', 'wh3', 'lang_fr', 0, 0)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('b', 'B', 0, 'gi1', 'wh3', 'lang_fr', 1, 1)",
      );
      final result = await service.detectPendingMigration();
      expect(result, isNotNull);
      expect(result!.universals, isEmpty);
      expect(result.duplicates, hasLength(1));
      expect(result.duplicates.first.gameCode, 'wh3');
      expect(result.duplicates.first.members.map((m) => m.id),
          containsAll(['a', 'b']));
    });

    test('reports entry counts accurately', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('gu', 'U', 1, 'lang_fr', 0, 0)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('e1', 'gu', 'fr', 'apple', 'pomme', 0, 0)",
      );
      final result = await service.detectPendingMigration();
      expect(result!.universals.first.entryCount, 1);
    });
  });

  group('applyMigration — conversion', () {
    test('converts universal to non-colliding (game, language) by setting game_code', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('gu', 'U', 1, 'lang_fr', 0, 0)",
      );
      await service.applyMigration(const MigrationPlan(conversions: {'gu': 'wh3'}));
      // After finalize, the legacy column 'is_global' is gone. Query only game_code.
      final rows = await DatabaseService.database
          .rawQuery('SELECT game_code FROM glossaries WHERE id = ?', ['gu']);
      expect(rows.first['game_code'], 'wh3');
    });

    test('merges universal into existing (game, language) with dedup', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('gu', 'Universal', 1, NULL, NULL, 'lang_fr', 0, 0)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('gg', 'Game', 0, 'gi1', 'wh3', 'lang_fr', 1, 1)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('e1', 'gu', 'fr', 'Apple', 'Pomme Universal', 10, 10)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('e2', 'gg', 'fr', 'apple', 'Pomme Game', 5, 5)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('e3', 'gu', 'fr', 'Banana', 'Banane', 10, 10)",
      );

      await service.applyMigration(const MigrationPlan(conversions: {'gu': 'wh3'}));

      final remaining = await DatabaseService.database.rawQuery('SELECT id FROM glossaries');
      expect(remaining.map((r) => r['id']), ['gg']);
      final entries = await DatabaseService.database.rawQuery(
          'SELECT source_term, target_term FROM glossary_entries WHERE glossary_id = ?', ['gg']);
      expect(entries.map((e) => e['target_term']),
          containsAll(['Pomme Universal', 'Banane']));
      expect(entries.where((e) => (e['target_term'] as String).contains('Game')), isEmpty);
    });

    test('deletes universal when conversion target is null', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('gu', 'Doomed', 1, 'lang_fr', 0, 0)",
      );
      await service.applyMigration(const MigrationPlan(conversions: {'gu': null}));
      final rows = await DatabaseService.database.rawQuery('SELECT id FROM glossaries');
      expect(rows, isEmpty);
    });

    test('deletes universals not mentioned in the plan', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, target_language_id, created_at, updated_at) VALUES ('gu', 'Unmentioned', 1, 'lang_fr', 0, 0)",
      );
      await service.applyMigration(const MigrationPlan(conversions: {}));
      final rows = await DatabaseService.database.rawQuery('SELECT id FROM glossaries');
      expect(rows, isEmpty);
    });
  });

  group('applyMigration — duplicate merge', () {
    test('merges duplicates into oldest, dedups case-insensitively', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('old', 'Old', 0, 'gi1', 'wh3', 'lang_fr', 0, 0)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('new', 'New', 0, 'gi1', 'wh3', 'lang_fr', 5, 5)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('a', 'old', 'fr', ' Apple ', 'Pomme v1', 0, 0)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('b', 'new', 'fr', 'apple', 'Pomme v2', 10, 10)",
      );
      await DatabaseService.database.execute(
        "INSERT INTO glossary_entries (id, glossary_id, target_language_code, source_term, target_term, created_at, updated_at) VALUES ('c', 'new', 'fr', 'Pear', 'Poire', 5, 5)",
      );

      await service.applyMigration(const MigrationPlan(conversions: {}));

      final glossaries = await DatabaseService.database.rawQuery('SELECT id FROM glossaries');
      expect(glossaries.map((g) => g['id']), ['old']);
      final entries = await DatabaseService.database.rawQuery(
          'SELECT source_term, target_term FROM glossary_entries WHERE glossary_id = ?', ['old']);
      expect(entries.length, 2);
      expect(
        entries.firstWhere((e) => (e['source_term'] as String).trim().toLowerCase() == 'apple')['target_term'],
        'Pomme v2',
      );
    });
  });

  group('finalizeSchema', () {
    test('adds UNIQUE(game_code, target_language_id) and makes game_code NOT NULL', () async {
      await DatabaseService.database.execute(
        "INSERT INTO glossaries (id, name, is_global, game_installation_id, game_code, target_language_id, created_at, updated_at) VALUES ('a', 'A', 0, 'gi1', 'wh3', 'lang_fr', 0, 0)",
      );
      await service.finalizeSchema();

      // Inserting a duplicate (game_code, target_language_id) must fail.
      expect(
        () => DatabaseService.database.execute(
          "INSERT INTO glossaries (id, name, game_code, target_language_id, created_at, updated_at) VALUES ('b', 'B', 'wh3', 'lang_fr', 0, 0)",
        ),
        throwsA(anything),
      );
    });

    test('is idempotent', () async {
      await service.finalizeSchema();
      await service.finalizeSchema();
    });
  });
}
