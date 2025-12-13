import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure llm_custom_rules table exists.
///
/// This table stores custom rules that users can add to LLM translation prompts.
/// Rules can be global (project_id = NULL) or project-specific.
class LlmCustomRulesMigration extends Migration {
  @override
  String get id => 'llm_custom_rules_table';

  @override
  String get description => 'Create llm_custom_rules table for custom LLM prompt rules';

  @override
  int get priority => 70;

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS llm_custom_rules (
          id TEXT PRIMARY KEY,
          rule_text TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          project_id TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          CHECK (is_enabled IN (0, 1)),
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        )
      ''');

      // Add project_id column if it doesn't exist (for older databases)
      await _ensureProjectIdColumn(logging);

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_llm_custom_rules_enabled_order
        ON llm_custom_rules(is_enabled, sort_order)
      ''');

      // Index for project-specific rules queries
      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_llm_custom_rules_project
        ON llm_custom_rules(project_id)
      ''');

      logging.debug('llm_custom_rules table verified/created');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create llm_custom_rules table', e, stackTrace);
      // Non-fatal: custom rules feature will be unavailable but app still works
      return false;
    }
  }

  Future<void> _ensureProjectIdColumn(LoggingService logging) async {
    final rulesColumns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(llm_custom_rules)"
    );
    final hasProjectIdColumn = rulesColumns.any((col) => col['name'] == 'project_id');

    if (!hasProjectIdColumn) {
      await DatabaseService.execute('''
        ALTER TABLE llm_custom_rules ADD COLUMN project_id TEXT
          REFERENCES projects(id) ON DELETE CASCADE
      ''');
      logging.info('Added project_id column to llm_custom_rules');
    }
  }
}
