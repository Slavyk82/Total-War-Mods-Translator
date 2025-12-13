import 'migration_base.dart';
import 'migration_performance_indexes.dart';
import 'migration_performance_indexes_v2.dart';
import 'migration_mod_update_cache.dart';
import 'migration_translation_source.dart';
import 'migration_compilation_tables.dart';
import 'migration_fix_escaped_newlines.dart';
import 'migration_fix_backslash_newlines.dart';
import 'migration_workshop_mods_hidden.dart';
import 'migration_llm_custom_rules.dart';
import 'migration_languages_custom.dart';
import 'migration_mod_update_impact.dart';
import 'migration_ignored_source_texts.dart';

/// Registry of all database migrations.
///
/// Migrations are applied in priority order (lower numbers first).
/// Each migration should be idempotent (safe to run multiple times).
class MigrationRegistry {
  MigrationRegistry._();

  /// Get all registered migrations sorted by priority.
  static List<Migration> getAllMigrations() {
    final migrations = <Migration>[
      PerformanceIndexesMigration(),
      PerformanceIndexesV2Migration(),
      ModUpdateCacheMigration(),
      TranslationSourceMigration(),
      CompilationTablesMigration(),
      FixEscapedNewlinesMigration(),
      FixBackslashNewlinesMigration(),
      WorkshopModsHiddenMigration(),
      LlmCustomRulesMigration(),
      LanguagesCustomMigration(),
      ModUpdateImpactMigration(),
      IgnoredSourceTextsMigration(),
    ];

    // Sort by priority (lower numbers first)
    migrations.sort((a, b) => a.priority.compareTo(b.priority));

    return migrations;
  }

  /// Get migration by ID.
  static Migration? getMigration(String id) {
    return getAllMigrations().where((m) => m.id == id).firstOrNull;
  }

  /// Get migrations that should run after a specific priority.
  static List<Migration> getMigrationsAfterPriority(int priority) {
    return getAllMigrations().where((m) => m.priority > priority).toList();
  }
}
