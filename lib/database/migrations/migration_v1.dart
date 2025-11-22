import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../services/database/migration_service.dart';

/// Migration V1: Initial database schema
///
/// Creates all tables, indexes, triggers, views, and seed data from schema.sql.
///
/// This migration includes:
/// - 15+ tables (languages, translation_providers, projects, etc.)
/// - 30+ indexes for performance optimization
/// - FTS5 virtual tables for full-text search
/// - Triggers for auto-updates (timestamps, progress, FTS sync, cache)
/// - Views for statistics
/// - Seed data (6 languages, 3 providers, default settings)
class MigrationV1 extends Migration {
  @override
  int get version => 1;

  @override
  String get description => 'Initial database schema with all tables, indexes, triggers, and seed data';

  @override
  Future<void> up(Transaction txn) async {
    // Load schema.sql from assets
    final schema = await rootBundle.loadString('lib/database/schema.sql');

    // Execute the complete schema script
    await executeSqlScript(txn, schema);
  }

  @override
  Future<void> verify(Database db) async {
    // Verify tables exist
    await _verifyTablesExist(db);

    // Verify indexes exist
    await _verifyIndexesExist(db);

    // Verify triggers exist
    await _verifyTriggersExist(db);

    // Verify views exist
    await _verifyViewsExist(db);

    // Verify seed data
    await _verifySeedData(db);

    // Verify PRAGMA settings
    await _verifyPragmaSettings(db);
  }

  /// Verify all required tables exist
  Future<void> _verifyTablesExist(Database db) async {
    final requiredTables = [
      'languages',
      'translation_providers',
      'game_installations',
      'projects',
      'project_languages',
      'mod_versions',
      'mod_version_changes',
      'translation_units',
      'translation_versions',
      'translation_version_history',
      'translation_batches',
      'translation_batch_units',
      'translation_memory',
      'translation_version_tm_usage',
      'settings',
      'translation_view_cache',
    ];

    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );

    final existingTables = result.map((row) => row['name'] as String).toSet();

    for (final table in requiredTables) {
      if (!existingTables.contains(table)) {
        throw Exception('Required table not found: $table');
      }
    }
  }

  /// Verify FTS5 virtual tables exist
  Future<void> _verifyIndexesExist(Database db) async {
    // Verify FTS5 tables
    final ftsResult = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts'",
    );

    final ftsTables = ftsResult.map((row) => row['name'] as String).toSet();

    if (!ftsTables.contains('translation_units_fts')) {
      throw Exception('FTS5 table not found: translation_units_fts');
    }

    if (!ftsTables.contains('translation_versions_fts')) {
      throw Exception('FTS5 table not found: translation_versions_fts');
    }

    // Verify regular indexes exist (sample check)
    final indexResult = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );

    final indexes = indexResult.map((row) => row['name'] as String).toSet();

    final sampleIndexes = [
      'idx_projects_game',
      'idx_translation_units_project',
      'idx_translation_versions_unit',
      'idx_batches_proj_lang',
      'idx_tm_hash_lang_context',
    ];

    for (final index in sampleIndexes) {
      if (!indexes.contains(index)) {
        throw Exception('Required index not found: $index');
      }
    }
  }

  /// Verify triggers exist
  Future<void> _verifyTriggersExist(Database db) async {
    final requiredTriggers = [
      'trg_translation_units_fts_insert',
      'trg_translation_units_fts_update',
      'trg_translation_units_fts_delete',
      'trg_translation_versions_fts_insert',
      'trg_translation_versions_fts_update',
      'trg_translation_versions_fts_delete',
      'trg_update_cache_on_unit_change',
      'trg_update_cache_on_version_change',
      'trg_insert_cache_on_version_insert',
      'trg_delete_cache_on_version_delete',
      'trg_update_project_language_progress',
      'trg_projects_updated_at',
      'trg_translation_units_updated_at',
      'trg_translation_versions_updated_at',
    ];

    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger'",
    );

    final existingTriggers = result.map((row) => row['name'] as String).toSet();

    for (final trigger in requiredTriggers) {
      if (!existingTriggers.contains(trigger)) {
        throw Exception('Required trigger not found: $trigger');
      }
    }
  }

  /// Verify views exist
  Future<void> _verifyViewsExist(Database db) async {
    final requiredViews = [
      'v_project_language_stats',
      'v_translations_needing_review',
    ];

    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='view'",
    );

    final existingViews = result.map((row) => row['name'] as String).toSet();

    for (final view in requiredViews) {
      if (!existingViews.contains(view)) {
        throw Exception('Required view not found: $view');
      }
    }
  }

  /// Verify seed data exists
  Future<void> _verifySeedData(Database db) async {
    // Verify languages (should have 6)
    final languages = await db.query('languages');
    if (languages.length != 6) {
      throw Exception('Expected 6 languages, found ${languages.length}');
    }

    final expectedLanguageCodes = {'de', 'en', 'zh', 'es', 'fr', 'ru'};
    final actualLanguageCodes =
        languages.map((l) => l['code'] as String).toSet();

    if (!actualLanguageCodes.containsAll(expectedLanguageCodes)) {
      throw Exception(
        'Missing expected language codes. Expected: $expectedLanguageCodes, Got: $actualLanguageCodes',
      );
    }

    // Verify translation providers (should have 3)
    final providers = await db.query('translation_providers');
    if (providers.length != 3) {
      throw Exception('Expected 3 providers, found ${providers.length}');
    }

    final expectedProviderCodes = {'anthropic', 'deepl', 'openai'};
    final actualProviderCodes =
        providers.map((p) => p['code'] as String).toSet();

    if (!actualProviderCodes.containsAll(expectedProviderCodes)) {
      throw Exception(
        'Missing expected provider codes. Expected: $expectedProviderCodes, Got: $actualProviderCodes',
      );
    }

    // Verify settings (should have 5)
    final settings = await db.query('settings');
    if (settings.length != 5) {
      throw Exception('Expected 5 settings, found ${settings.length}');
    }

    final expectedSettingKeys = {
      'active_translation_provider_id',
      'default_game_installation_id',
      'default_game_context_prompts',
      'default_batch_size',
      'default_parallel_batches',
    };

    final actualSettingKeys = settings.map((s) => s['key'] as String).toSet();

    if (!actualSettingKeys.containsAll(expectedSettingKeys)) {
      throw Exception(
        'Missing expected setting keys. Expected: $expectedSettingKeys, Got: $actualSettingKeys',
      );
    }
  }

  /// Verify PRAGMA settings
  Future<void> _verifyPragmaSettings(Database db) async {
    // Verify foreign keys are enabled
    final fkResult = await db.rawQuery('PRAGMA foreign_keys');
    final foreignKeysEnabled = fkResult.first['foreign_keys'] == 1;

    if (!foreignKeysEnabled) {
      throw Exception('Foreign keys are not enabled');
    }

    // Verify WAL mode is enabled
    final walResult = await db.rawQuery('PRAGMA journal_mode');
    final journalMode = walResult.first['journal_mode'] as String;

    if (journalMode.toLowerCase() != 'wal') {
      throw Exception('Journal mode is not WAL: $journalMode');
    }
  }

  @override
  Future<void> down(Transaction txn) async {
    // Drop all tables in reverse order of dependencies
    final tables = [
      'translation_version_tm_usage',
      'translation_memory',
      'translation_batch_units',
      'translation_batches',
      'translation_version_history',
      'translation_versions',
      'translation_units',
      'mod_version_changes',
      'mod_versions',
      'project_languages',
      'projects',
      'game_installations',
      'translation_providers',
      'languages',
      'settings',
      'translation_view_cache',
    ];

    // Drop views
    await txn.execute('DROP VIEW IF EXISTS v_project_language_stats');
    await txn.execute('DROP VIEW IF EXISTS v_translations_needing_review');

    // Drop FTS5 tables
    await txn.execute('DROP TABLE IF EXISTS translation_units_fts');
    await txn.execute('DROP TABLE IF EXISTS translation_versions_fts');

    // Drop regular tables
    for (final table in tables) {
      await txn.execute('DROP TABLE IF EXISTS $table');
    }
  }
}
