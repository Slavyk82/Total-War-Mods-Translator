import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_default_model_dedup.dart';
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

  /// Stages the duplicate-default state the buggy migrations left behind on
  /// upgraded databases: the user starred Haiku 4.5 (single default), then
  /// the Anthropic migration INSERTed Sonnet 4.6 with is_default = 1 —
  /// INSERT bypasses trg_llm_models_single_default, creating a duplicate.
  Future<void> stageAnthropicDoubleDefault() async {
    // User stars Haiku (UPDATE path — trigger clears the seeded Sonnet 4.6
    // default, exactly like setAsDefault).
    await db.rawUpdate(
      "UPDATE llm_provider_models SET is_default = 1, updated_at = 1700000000 "
      "WHERE id = 'model_claude_4_5_haiku'",
    );
    // Re-insert Sonnet 4.6 with is_default = 1 (the buggy migration INSERT;
    // newer updated_at, like a post-star app upgrade).
    await db.delete('llm_provider_models',
        where: "id = 'model_claude_sonnet_4_6'");
    await db.insert('llm_provider_models', {
      'id': 'model_claude_sonnet_4_6',
      'provider_code': 'anthropic',
      'model_id': 'claude-sonnet-4-6',
      'display_name': 'Claude Sonnet 4.6',
      'is_enabled': 1,
      'is_default': 1,
      'is_archived': 0,
      'created_at': 1800000000,
      'updated_at': 1800000000,
      'last_fetched_at': 1800000000,
    });
  }

  Future<List<Map<String, Object?>>> defaultsFor(String provider) =>
      db.rawQuery(
        'SELECT id FROM llm_provider_models '
        'WHERE provider_code = ? AND is_default = 1',
        [provider],
      );

  group('DefaultModelDedupMigration', () {
    test('isApplied is true on a healthy database (one default per provider)',
        () async {
      final migration = DefaultModelDedupMigration();
      expect(await migration.isApplied(), isTrue);
      expect(await migration.execute(), isFalse,
          reason: 'Nothing to repair on a healthy database.');
    });

    test('collapses a pre-existing double default, preserving the user star',
        () async {
      await stageAnthropicDoubleDefault();
      expect(await defaultsFor('anthropic'), hasLength(2),
          reason: 'Staging must reproduce the duplicate-default state.');

      final migration = DefaultModelDedupMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      final defaults = await defaultsFor('anthropic');
      expect(defaults, hasLength(1));
      expect(defaults.first['id'], 'model_claude_4_5_haiku',
          reason: 'The user-starred row must win over the migration-inserted '
              'row even though the latter has a newer updated_at.');

      // Other providers untouched.
      expect(await defaultsFor('openai'), hasLength(1));

      // Idempotent: a second startup pass sees a healthy state.
      expect(await migration.isApplied(), isTrue);
      expect(await migration.execute(), isFalse);
    });

    test('keeps the most recently updated row among generic duplicates',
        () async {
      // Two non-migration-seeded duplicates (deepl has no seeded default).
      for (final (id, updatedAt) in [('model_deepl_free', 100), ('model_deepl_pro', 200)]) {
        await db.delete('llm_provider_models', where: 'id = ?', whereArgs: [id]);
        await db.insert('llm_provider_models', {
          'id': id,
          'provider_code': 'deepl',
          'model_id': id,
          'display_name': id,
          'is_enabled': 1,
          'is_default': 1,
          'is_archived': 0,
          'created_at': updatedAt,
          'updated_at': updatedAt,
          'last_fetched_at': updatedAt,
        });
      }

      final migration = DefaultModelDedupMigration();
      expect(await migration.isApplied(), isFalse);
      expect(await migration.execute(), isTrue);

      final defaults = await defaultsFor('deepl');
      expect(defaults, hasLength(1));
      expect(defaults.first['id'], 'model_deepl_pro',
          reason: 'The most recently updated duplicate must be kept.');
    });

    test('prefers a non-archived duplicate over an archived one', () async {
      await db.delete('llm_provider_models',
          where: "provider_code = 'deepl'");
      for (final (id, archived) in [('model_a', 1), ('model_b', 0)]) {
        await db.insert('llm_provider_models', {
          'id': id,
          'provider_code': 'deepl',
          'model_id': id,
          'display_name': id,
          'is_enabled': 1,
          'is_default': 1,
          'is_archived': archived,
          'created_at': 100,
          'updated_at': archived == 1 ? 200 : 100,
          'last_fetched_at': 100,
        });
      }

      final migration = DefaultModelDedupMigration();
      expect(await migration.execute(), isTrue);

      final defaults = await defaultsFor('deepl');
      expect(defaults, hasLength(1));
      expect(defaults.first['id'], 'model_b',
          reason: 'A non-archived row must win even with an older '
              'updated_at.');
    });
  });
}
