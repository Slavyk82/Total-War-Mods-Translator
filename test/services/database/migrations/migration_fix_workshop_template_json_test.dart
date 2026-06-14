import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migrations/migration_fix_workshop_template_json.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';

/// Regression tests for [FixWorkshopTemplateJsonMigration]. A Workshop
/// title/description template stored as a localized JSON map (`{"fr":"..."}`)
/// crashes steamcmd's KeyValues VDF parser (exit code 9). The migration heals
/// the stored value to plain text for upgraded databases.
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
      CREATE TABLE settings (
        id TEXT PRIMARY KEY,
        key TEXT UNIQUE NOT NULL,
        value TEXT NOT NULL,
        value_type TEXT NOT NULL DEFAULT 'string',
        updated_at INTEGER NOT NULL,
        CHECK (value_type IN ('string', 'integer', 'boolean', 'json'))
      )
    ''');
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  Future<void> putSetting(String key, String value) async {
    await db.insert('settings', {
      'id': 'id-$key',
      'key': key,
      'value': value,
      'value_type': 'string',
      'updated_at': 0,
    });
  }

  Future<String?> readSetting(String key) async {
    final rows = await db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  test('unwraps JSON-localized title and description templates to plain text',
      () async {
    await putSetting('workshop_title_template',
        '{"fr":"Français - \$modName par Slavyk"}');
    await putSetting('workshop_description_template',
        '{"fr":"[h1]Traduction[/h1]\\r\\n[i]abo[/i]"}');

    final changed =
        await FixWorkshopTemplateJsonMigration(logger: FakeLogger()).execute();

    expect(changed, isTrue);
    expect(await readSetting('workshop_title_template'),
        'Français - \$modName par Slavyk');
    expect(await readSetting('workshop_description_template'),
        '[h1]Traduction[/h1]\r\n[i]abo[/i]');
  });

  test('is a no-op (returns false) when templates are already plain text',
      () async {
    await putSetting('workshop_title_template', 'Plain - \$modName');
    await putSetting('workshop_description_template', '[h1]Already plain[/h1]');

    final changed =
        await FixWorkshopTemplateJsonMigration(logger: FakeLogger()).execute();

    expect(changed, isFalse);
    expect(await readSetting('workshop_title_template'), 'Plain - \$modName');
    expect(await readSetting('workshop_description_template'),
        '[h1]Already plain[/h1]');
  });

  test('is idempotent — a second run changes nothing', () async {
    await putSetting('workshop_title_template', '{"fr":"Texte"}');

    final first =
        await FixWorkshopTemplateJsonMigration(logger: FakeLogger()).execute();
    final second =
        await FixWorkshopTemplateJsonMigration(logger: FakeLogger()).execute();

    expect(first, isTrue);
    expect(second, isFalse);
    expect(await readSetting('workshop_title_template'), 'Texte');
  });

  test('skips cleanly when the settings rows are absent', () async {
    final changed =
        await FixWorkshopTemplateJsonMigration(logger: FakeLogger()).execute();
    expect(changed, isFalse);
  });
}
