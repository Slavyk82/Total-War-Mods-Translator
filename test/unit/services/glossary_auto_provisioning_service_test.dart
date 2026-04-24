import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/glossary/glossary_auto_provisioning_service.dart';
import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late GlossaryAutoProvisioningService service;

  setUp(() async {
    db = await TestDatabase.openMigrated(clearSeeds: true);
    service = GlossaryAutoProvisioningService();

    await DatabaseService.database.execute(
      "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_fr', 'fr', 'French', 'Français', 1)",
    );
    await DatabaseService.database.execute(
      "INSERT INTO languages (id, code, name, native_name, is_active) VALUES ('lang_de', 'de', 'German', 'Deutsch', 1)",
    );
    await DatabaseService.database.execute(
      "INSERT INTO game_installations (id, game_code, game_name, created_at, updated_at) VALUES ('gi1', 'wh3', 'WH3', 0, 0)",
    );
    await DatabaseService.database.execute(
      "INSERT INTO projects (id, name, game_installation_id, batch_size, parallel_batches, created_at, updated_at) VALUES ('p1', 'P', 'gi1', 25, 5, 0, 0)",
    );
    await DatabaseService.database.execute(
      "INSERT INTO project_languages (id, project_id, language_id, created_at, updated_at) VALUES ('pl1', 'p1', 'lang_fr', 0, 0)",
    );
    await DatabaseService.database.execute(
      "INSERT INTO project_languages (id, project_id, language_id, created_at, updated_at) VALUES ('pl2', 'p1', 'lang_de', 0, 0)",
    );
  });
  tearDown(() async => TestDatabase.close(db));

  test('provisionForGame creates one glossary per distinct project language', () async {
    await service.provisionForGame('wh3');
    final rows = await DatabaseService.database.rawQuery(
        'SELECT game_code, target_language_id FROM glossaries ORDER BY target_language_id');
    expect(rows, hasLength(2));
    expect(rows.map((r) => r['target_language_id']), ['lang_de', 'lang_fr']);
    expect(rows.every((r) => r['game_code'] == 'wh3'), isTrue);
  });

  test('provisionForGame is idempotent', () async {
    await service.provisionForGame('wh3');
    await service.provisionForGame('wh3');
    final rows = await DatabaseService.database
        .rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 2);
  });

  test('provisionForProjectLanguage creates a single glossary', () async {
    await service.provisionForProjectLanguage(
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
    );
    final rows = await DatabaseService.database.rawQuery('SELECT * FROM glossaries');
    expect(rows, hasLength(1));
    expect(rows.first['game_code'], 'wh3');
    expect(rows.first['target_language_id'], 'lang_fr');
    expect(rows.first['name'], contains('fr'));
  });

  test('provisionForProjectLanguage no-op when glossary already exists', () async {
    await service.provisionForProjectLanguage(
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
    );
    await service.provisionForProjectLanguage(
      gameCode: 'wh3',
      targetLanguageId: 'lang_fr',
    );
    final rows = await DatabaseService.database
        .rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 1);
  });

  test('provisionForProject resolves gameCode and provisions per language',
      () async {
    await service.provisionForProject(
      projectId: 'p1',
      targetLanguageIds: ['lang_fr', 'lang_de'],
    );
    final rows = await DatabaseService.database.rawQuery(
      'SELECT game_code, target_language_id FROM glossaries '
      'ORDER BY target_language_id',
    );
    expect(rows, hasLength(2));
    expect(rows.map((r) => r['target_language_id']), ['lang_de', 'lang_fr']);
    expect(rows.every((r) => r['game_code'] == 'wh3'), isTrue);
  });

  test('provisionForProject is idempotent', () async {
    await service.provisionForProject(
      projectId: 'p1',
      targetLanguageIds: ['lang_fr'],
    );
    await service.provisionForProject(
      projectId: 'p1',
      targetLanguageIds: ['lang_fr'],
    );
    final rows = await DatabaseService.database
        .rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 1);
  });

  test('provisionForProject swallows unknown projectId (no throw, no rows)',
      () async {
    await service.provisionForProject(
      projectId: 'does-not-exist',
      targetLanguageIds: ['lang_fr'],
    );
    final rows = await DatabaseService.database
        .rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 0);
  });

  test('provisionForProject with empty target list is a no-op', () async {
    await service.provisionForProject(
      projectId: 'p1',
      targetLanguageIds: const [],
    );
    final rows = await DatabaseService.database
        .rawQuery('SELECT COUNT(*) as cnt FROM glossaries');
    expect(rows.first['cnt'], 0);
  });
}
