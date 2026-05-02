import 'migration_base.dart';
import 'migration_performance_indexes.dart';
import 'migration_performance_indexes_v2.dart';
import 'migration_drop_redundant_tm_indexes.dart';
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
import 'migration_fix_cache_triggers.dart';
import 'migration_project_type.dart';
import 'migration_deepseek_provider.dart';
import 'migration_gemini_provider.dart';
import 'migration_deepl_glossary_sync.dart';
import 'migration_published_steam_id.dart';
import 'migration_published_at.dart';
import 'migration_compilation_publish_fields.dart';
import 'migration_validation_schema_version.dart';
import 'migration_activity_events.dart';
import 'migration_projects_filter_indexes.dart';
import 'migration_glossary_game_code_partial.dart';
import 'migration_cascade_project_updated_at.dart';
import 'migration_projects_updated_at_trigger_scope.dart';
import 'migration_deepseek_v4_models.dart';
import 'migration_openai_v5_4_5_5_models.dart';
import 'migration_anthropic_opus47_sonnet46.dart';
import 'migration_deepseek_chat_restore.dart';

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
      DropRedundantTmIndexesMigration(), // NEW — runs right after v2
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
      FixCacheTriggersMigration(),
      ProjectTypeMigration(),
      DeepSeekProviderMigration(),
      GeminiProviderMigration(),
      DeepLGlossarySyncMigration(),
      PublishedSteamIdMigration(),
      PublishedAtMigration(),
      CompilationPublishFieldsMigration(),
      ValidationSchemaVersionMigration(),
      ActivityEventsMigration(),
      ProjectsFilterIndexesMigration(), // Priority 120 — must run after column-adding migrations
      GlossaryGameCodePartialMigration(), // Priority 130 — game-specific glossary refactor
      CascadeProjectUpdatedAtMigration(), // Priority 140 — adds projects.updated_at cascade to progress trigger
      ProjectsUpdatedAtTriggerScopeMigration(), // Priority 150 — restricts trg_projects_updated_at to content columns
      DeepSeekV4ModelsMigration(), // Priority 160 — DeepSeek v3.2 → v4 (flash + pro), archives deepseek-chat
      OpenAiGpt5xModelsMigration(), // Priority 170 — OpenAI gpt-5.1 → gpt-5.5 (default) + gpt-5.4
      AnthropicOpus47Sonnet46Migration(), // Priority 180 — Anthropic adds Opus 4.7 + Sonnet 4.6 (default), archives Sonnet 4.5
      DeepSeekChatRestoreMigration(), // Priority 190 — re-expose deepseek-chat (V3.2) alongside the V4 family
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
