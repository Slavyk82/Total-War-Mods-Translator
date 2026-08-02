import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_llm_models_2026_08.dart';
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

  /// Stages the pre-migration (upgraded database) state: the seven rows now
  /// seeded by schema.sql are removed and the two Gemini 3 previews restored,
  /// with `gemini-3-flash-preview` optionally still flagged as the model-level
  /// default (it was always the provider-level one).
  Future<void> stageUpgradedDb({required bool legacyIsDefault}) async {
    await db.delete(
      'llm_provider_models',
      where: "model_id IN ('gpt-5.6-terra', 'gpt-5.4-nano', 'claude-sonnet-5', "
          "'claude-opus-5', 'gemini-3.6-flash', 'gemini-3.5-flash', "
          "'gemini-3.5-flash-lite')",
    );
    for (final row in [
      ('model_gemini_3_pro', 'gemini-3-pro-preview', 'Gemini 3 Pro', 0),
      (
        'model_gemini_3_flash',
        'gemini-3-flash-preview',
        'Gemini 3 Flash',
        legacyIsDefault ? 1 : 0,
      ),
    ]) {
      await db.insert('llm_provider_models', {
        'id': row.$1,
        'provider_code': 'gemini',
        'model_id': row.$2,
        'display_name': row.$3,
        'is_enabled': 1,
        'is_default': row.$4,
        'is_archived': 0,
        'created_at': 1700000000,
        'updated_at': 1700000000,
        'last_fetched_at': 1700000000,
      });
    }
    await db.rawUpdate(
      "UPDATE translation_providers SET default_model = 'gemini-3-flash-preview' "
      "WHERE code = 'gemini'",
    );
  }

  Future<List<Map<String, Object?>>> geminiDefaults() => db.rawQuery(
        "SELECT model_id FROM llm_provider_models "
        "WHERE provider_code = 'gemini' AND is_default = 1",
      );

  Future<Map<String, Object?>> modelRow(String modelId) async {
    final rows = await db.rawQuery(
      'SELECT * FROM llm_provider_models WHERE model_id = ?',
      [modelId],
    );
    expect(rows, hasLength(1), reason: 'Expected exactly one $modelId row.');
    return rows.first;
  }

  group('LlmModels202608Migration', () {
    test('adds the new OpenAI, Anthropic and Gemini models as enabled',
        () async {
      await stageUpgradedDb(legacyIsDefault: false);

      final migration = LlmModels202608Migration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      const expected = {
        'gpt-5.6-terra': ('openai', 'GPT-5.6 Terra'),
        'gpt-5.4-nano': ('openai', 'GPT-5.4 nano'),
        'claude-sonnet-5': ('anthropic', 'Claude Sonnet 5'),
        'claude-opus-5': ('anthropic', 'Claude Opus 5'),
        'gemini-3.6-flash': ('gemini', 'Gemini 3.6 Flash'),
        'gemini-3.5-flash': ('gemini', 'Gemini 3.5 Flash'),
        'gemini-3.5-flash-lite': ('gemini', 'Gemini 3.5 Flash-Lite'),
      };

      for (final entry in expected.entries) {
        final row = await modelRow(entry.key);
        expect(row['provider_code'], entry.value.$1);
        expect(row['display_name'], entry.value.$2);
        expect(row['is_enabled'], 1, reason: '${entry.key} must be selectable');
        expect(row['is_archived'], 0);
      }

      expect(await migration.isApplied(), isTrue);
    });

    test('archives the Gemini 3 previews and repoints the provider default',
        () async {
      await stageUpgradedDb(legacyIsDefault: false);

      expect(await LlmModels202608Migration().execute(), isTrue);

      for (final retired in ['gemini-3-pro-preview', 'gemini-3-flash-preview']) {
        final row = await modelRow(retired);
        expect(row['is_enabled'], 0, reason: '$retired must leave the picker');
        expect(row['is_archived'], 1);
        expect(row['is_default'], 0);
      }

      final provider = await db.rawQuery(
        "SELECT default_model FROM translation_providers WHERE code = 'gemini'",
      );
      expect(provider.first['default_model'], 'gemini-3.6-flash',
          reason: 'The provider default must not keep naming an archived '
              'model, or translation requests target a retired preview.');
    });

    test('promotes Gemini 3.6 Flash when a retired preview was the default',
        () async {
      await stageUpgradedDb(legacyIsDefault: true);

      expect(await LlmModels202608Migration().execute(), isTrue);

      final defaults = await geminiDefaults();
      expect(defaults, hasLength(1),
          reason: 'Exactly one Gemini model must be flagged as default.');
      expect(defaults.first['model_id'], 'gemini-3.6-flash');
    });

    test('preserves a user-starred Gemini default', () async {
      await stageUpgradedDb(legacyIsDefault: false);
      // User starred Gemini 3 Pro in Settings before the upgrade.
      await db.rawUpdate(
        "UPDATE llm_provider_models SET is_default = 1 "
        "WHERE model_id = 'gemini-3-pro-preview'",
      );

      expect(await LlmModels202608Migration().execute(), isTrue);

      final defaults = await geminiDefaults();
      expect(defaults, hasLength(1),
          reason: 'The migration must not create a second Gemini default '
              '(INSERT bypasses the single-default trigger).');
      // The starred model is being retired, so 3.6 Flash inherits the flag
      // rather than leaving the provider with no default at all.
      expect(defaults.first['model_id'], 'gemini-3.6-flash');
    });

    test('leaves the OpenAI and Anthropic defaults untouched', () async {
      await stageUpgradedDb(legacyIsDefault: true);

      expect(await LlmModels202608Migration().execute(), isTrue);

      final providers = await db.rawQuery(
        "SELECT code, default_model FROM translation_providers "
        "WHERE code IN ('openai', 'anthropic')",
      );
      final byCode = {
        for (final row in providers) row['code'] as String: row['default_model']
      };
      expect(byCode['openai'], 'gpt-5.5');
      expect(byCode['anthropic'], 'claude-sonnet-4-6');

      // The new rows must not steal the model-level default either.
      for (final modelId in [
        'gpt-5.6-terra',
        'gpt-5.4-nano',
        'claude-sonnet-5',
        'claude-opus-5',
      ]) {
        expect((await modelRow(modelId))['is_default'], 0);
      }
    });

    test('is a no-op on a fresh schema.sql database', () async {
      // No staging: openMigrated already seeded the new rows.
      final migration = LlmModels202608Migration();
      expect(await migration.isApplied(), isTrue);

      final retired = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM llm_provider_models "
        "WHERE model_id IN ('gemini-3-pro-preview', 'gemini-3-flash-preview')",
      );
      expect(retired.first['cnt'], 0,
          reason: 'Fresh installs must never seed the retired previews.');
    });
  });
}
