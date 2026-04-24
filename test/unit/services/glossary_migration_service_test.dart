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
}
