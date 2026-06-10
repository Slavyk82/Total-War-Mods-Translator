import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_anthropic_opus47_sonnet46.dart';
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

  /// Stages the pre-migration (upgraded database) state: the 4.7/4.6 rows
  /// seeded by the current schema.sql are removed and the legacy Sonnet 4.5
  /// snapshot is restored, optionally as the provider default. Haiku 4.5
  /// ('model_claude_4_5_haiku') is already seeded by schema.sql.
  Future<void> stageUpgradedDb({required bool legacyIsDefault}) async {
    await db.delete(
      'llm_provider_models',
      where: "provider_code = 'anthropic' "
          "AND model_id IN ('claude-sonnet-4-6', 'claude-opus-4-7')",
    );
    await db.insert('llm_provider_models', {
      'id': 'model_claude_sonnet_4_5',
      'provider_code': 'anthropic',
      'model_id': 'claude-sonnet-4-5-20250929',
      'display_name': 'Claude Sonnet 4.5',
      'is_enabled': 1,
      'is_default': legacyIsDefault ? 1 : 0,
      'is_archived': 0,
      'created_at': 1700000000,
      'updated_at': 1700000000,
      'last_fetched_at': 1700000000,
    });
  }

  Future<List<Map<String, Object?>>> anthropicDefaults() => db.rawQuery(
        "SELECT model_id FROM llm_provider_models "
        "WHERE provider_code = 'anthropic' AND is_default = 1",
      );

  group('AnthropicOpus47Sonnet46Migration', () {
    test('promotes Sonnet 4.6 to single default when Sonnet 4.5 was default',
        () async {
      await stageUpgradedDb(legacyIsDefault: true);

      final migration = AnthropicOpus47Sonnet46Migration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      final defaults = await anthropicDefaults();
      expect(defaults, hasLength(1),
          reason: 'Exactly one Anthropic model must be flagged as default.');
      expect(defaults.first['model_id'], 'claude-sonnet-4-6');

      final legacy = await db.rawQuery(
        "SELECT is_enabled, is_archived, is_default FROM llm_provider_models "
        "WHERE model_id = 'claude-sonnet-4-5-20250929'",
      );
      expect(legacy, hasLength(1));
      expect(legacy.first['is_enabled'], 0);
      expect(legacy.first['is_archived'], 1);
      expect(legacy.first['is_default'], 0);
    });

    test('preserves a user-starred Haiku 4.5 default (the L1 regression)',
        () async {
      await stageUpgradedDb(legacyIsDefault: false);
      // User starred Haiku 4.5 in Settings before the upgrade
      // (setAsDefault cleared the Sonnet 4.5 flag and set Haiku).
      await db.rawUpdate(
        "UPDATE llm_provider_models SET is_default = 1 "
        "WHERE id = 'model_claude_4_5_haiku'",
      );

      final migration = AnthropicOpus47Sonnet46Migration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      final defaults = await anthropicDefaults();
      expect(defaults, hasLength(1),
          reason: 'The migration must not create a second Anthropic default '
              '(INSERT bypasses the single-default trigger).');
      expect(defaults.first['model_id'], 'claude-haiku-4-5-20251001',
          reason: 'The user-starred default must be preserved.');

      // New rows present regardless.
      final newRows = await db.rawQuery(
        "SELECT model_id FROM llm_provider_models "
        "WHERE provider_code = 'anthropic' "
        "AND model_id IN ('claude-sonnet-4-6', 'claude-opus-4-7')",
      );
      expect(newRows, hasLength(2));
    });
  });
}
