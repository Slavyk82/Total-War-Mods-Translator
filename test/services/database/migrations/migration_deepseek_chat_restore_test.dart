import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/services/database/migrations/migration_deepseek_chat_restore.dart';
import '../../../helpers/test_database.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Full production schema + migrations, keeping schema.sql seed rows
    // (llm_provider_models including deepseek-chat).
    db = await TestDatabase.openMigrated(clearSeeds: false);
    // Clear any marker the registry run may have written so each test
    // stages its own starting state.
    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: ['migration_deepseek_chat_restore_applied'],
    );
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  /// Simulates one app startup pass of the migration runner
  /// (MigrationService.ensurePerformanceIndexes) for this migration only.
  Future<void> runStartupPass(DeepSeekChatRestoreMigration migration) async {
    if (await migration.isApplied()) return;
    await migration.execute();
  }

  Future<Map<String, Object?>> deepseekChatRow() async {
    final rows = await db.rawQuery(
      "SELECT is_enabled, is_archived FROM llm_provider_models "
      "WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'",
    );
    expect(rows, hasLength(1));
    return rows.first;
  }

  group('DeepSeekChatRestoreMigration', () {
    test('does NOT re-enable deepseek-chat after the user disabled it',
        () async {
      final migration = DeepSeekChatRestoreMigration();

      // User disables the model in Settings
      // (LlmProviderModelRepository.disable sets is_enabled = 0).
      await db.rawUpdate(
        "UPDATE llm_provider_models SET is_enabled = 0 "
        "WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'",
      );

      // Next app startup re-evaluates the migration.
      expect(await migration.isApplied(), isTrue,
          reason: 'An existing non-archived row means the restore already '
              'happened (or was never needed); user disable must not '
              'retrigger it.');
      await runStartupPass(migration);

      final row = await deepseekChatRow();
      expect(row['is_enabled'], 0,
          reason: 'Startup must not silently revert the user disable.');
    });

    test('still restores a row archived by the v4 migration, exactly once',
        () async {
      final migration = DeepSeekChatRestoreMigration();

      // State left behind by DeepSeekV4ModelsMigration on a pre-restore DB.
      await db.rawUpdate(
        "UPDATE llm_provider_models SET is_enabled = 0, is_archived = 1 "
        "WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'",
      );

      expect(await migration.isApplied(), isFalse);
      await runStartupPass(migration);

      var row = await deepseekChatRow();
      expect(row['is_enabled'], 1);
      expect(row['is_archived'], 0);

      // The run is recorded persistently: even if the user disables the
      // model afterwards, later startups never resurrect it.
      await db.rawUpdate(
        "UPDATE llm_provider_models SET is_enabled = 0 "
        "WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'",
      );
      expect(await migration.isApplied(), isTrue);
      await runStartupPass(migration);

      row = await deepseekChatRow();
      expect(row['is_enabled'], 0);
    });

    test('inserts the row when it was never seeded', () async {
      final migration = DeepSeekChatRestoreMigration();

      await db.delete(
        'llm_provider_models',
        where: "provider_code = 'deepseek' AND model_id = 'deepseek-chat'",
      );

      expect(await migration.isApplied(), isFalse);
      await runStartupPass(migration);

      final row = await deepseekChatRow();
      expect(row['is_enabled'], 1);
      expect(row['is_archived'], 0);
    });
  });
}
