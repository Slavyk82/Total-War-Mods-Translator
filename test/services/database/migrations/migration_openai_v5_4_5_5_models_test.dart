import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_openai_v5_4_5_5_models.dart';
import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Full production schema + migrations, keeping schema.sql seed rows.
    db = await TestDatabase.openMigrated(clearSeeds: false);
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  /// Stages the pre-migration (upgraded database) state: the gpt-5.x rows
  /// seeded by the current schema.sql are removed and the legacy
  /// gpt-5.1-2025-11-13 row is restored, optionally as the provider default.
  Future<void> stageUpgradedDb({required bool legacyIsDefault}) async {
    await db.delete(
      'llm_provider_models',
      where: "provider_code = 'openai' AND model_id IN ('gpt-5.5', 'gpt-5.4')",
    );
    await db.insert('llm_provider_models', {
      'id': 'model_gpt_5_1',
      'provider_code': 'openai',
      'model_id': 'gpt-5.1-2025-11-13',
      'display_name': 'GPT-5.1',
      'is_enabled': 1,
      'is_default': legacyIsDefault ? 1 : 0,
      'is_archived': 0,
      'created_at': 1700000000,
      'updated_at': 1700000000,
      'last_fetched_at': 1700000000,
    });
  }

  Future<List<Map<String, Object?>>> openaiDefaults() => db.rawQuery(
        "SELECT model_id FROM llm_provider_models "
        "WHERE provider_code = 'openai' AND is_default = 1",
      );

  group('OpenAiGpt5xModelsMigration', () {
    test('promotes gpt-5.5 to single default when legacy gpt-5.1 was default',
        () async {
      await stageUpgradedDb(legacyIsDefault: true);

      final migration = OpenAiGpt5xModelsMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      final defaults = await openaiDefaults();
      expect(defaults, hasLength(1),
          reason: 'Exactly one OpenAI model must be flagged as default.');
      expect(defaults.first['model_id'], 'gpt-5.5');

      // Legacy snapshot archived, disabled and no longer default.
      final legacy = await db.rawQuery(
        "SELECT is_enabled, is_archived, is_default FROM llm_provider_models "
        "WHERE model_id = 'gpt-5.1-2025-11-13'",
      );
      expect(legacy, hasLength(1));
      expect(legacy.first['is_enabled'], 0);
      expect(legacy.first['is_archived'], 1);
      expect(legacy.first['is_default'], 0);

      // Provider-level default still updated.
      final provider = await db.rawQuery(
        "SELECT default_model FROM translation_providers WHERE code = 'openai'",
      );
      expect(provider.first['default_model'], 'gpt-5.5');
    });

    test('preserves a user-chosen default elsewhere (no duplicate defaults)',
        () async {
      await stageUpgradedDb(legacyIsDefault: false);
      // User had starred a model in another provider (setAsDefault clears
      // defaults globally, so the legacy OpenAI row lost its flag).
      await db.rawUpdate(
        "UPDATE llm_provider_models SET is_default = 1 "
        "WHERE id = 'model_claude_4_5_haiku'",
      );

      final migration = OpenAiGpt5xModelsMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      // The user's choice was not an OpenAI model, so gpt-5.5 must NOT
      // grab the default flag (INSERT bypasses the single-default trigger).
      expect(await openaiDefaults(), isEmpty,
          reason: 'gpt-5.5 must not be inserted with is_default = 1 when the '
              'legacy row was not the default.');

      final haiku = await db.rawQuery(
        "SELECT is_default FROM llm_provider_models "
        "WHERE id = 'model_claude_4_5_haiku'",
      );
      expect(haiku.first['is_default'], 1,
          reason: 'The user-chosen default must be preserved.');

      // New rows present and enabled regardless.
      final newRows = await db.rawQuery(
        "SELECT model_id FROM llm_provider_models "
        "WHERE provider_code = 'openai' AND model_id IN ('gpt-5.5', 'gpt-5.4')",
      );
      expect(newRows, hasLength(2));
    });
  });
}
