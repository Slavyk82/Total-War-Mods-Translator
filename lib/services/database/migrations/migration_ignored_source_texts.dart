import 'package:uuid/uuid.dart';

import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure ignored_source_texts table exists.
///
/// This table stores user-configurable source texts that should be skipped
/// during translation (e.g., placeholders, markers). Users can add, edit,
/// delete, and reset to defaults through the Settings screen.
class IgnoredSourceTextsMigration extends Migration {
  @override
  String get id => 'ignored_source_texts_table';

  @override
  String get description => 'Create ignored_source_texts table for translation skip filter';

  @override
  int get priority => 100;

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      // Create table
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS ignored_source_texts (
          id TEXT PRIMARY KEY,
          source_text TEXT NOT NULL,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          CHECK (is_enabled IN (0, 1))
        )
      ''');

      // Create indexes
      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_ignored_source_texts_enabled
        ON ignored_source_texts(is_enabled)
      ''');

      // Unique constraint on lowercase text to prevent duplicates
      await DatabaseService.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_ignored_source_texts_text_lower
        ON ignored_source_texts(LOWER(source_text))
      ''');

      // Seed default values if table is empty
      await _seedDefaults(logging);

      logging.debug('ignored_source_texts table verified/created');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create ignored_source_texts table', e, stackTrace);
      // Non-fatal: skip filter will fall back to hardcoded defaults
      return false;
    }
  }

  Future<void> _seedDefaults(LoggingService logging) async {
    final countResult = await DatabaseService.database.rawQuery(
      'SELECT COUNT(*) as cnt FROM ignored_source_texts'
    );
    final count = (countResult.first['cnt'] as int?) ?? 0;

    if (count == 0) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const defaults = ['placeholder', '[placeholder]', '[unseen]', '[do not localise]'];

      for (final text in defaults) {
        final id = const Uuid().v4();
        await DatabaseService.database.rawInsert(
          '''
          INSERT INTO ignored_source_texts
          (id, source_text, is_enabled, created_at, updated_at)
          VALUES (?, ?, 1, ?, ?)
          ''',
          [id, text, now, now],
        );
      }
      logging.info('Seeded ${defaults.length} default ignored source texts');
    }
  }
}
