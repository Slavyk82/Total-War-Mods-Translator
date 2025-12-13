import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to fix escaped newline sequences in existing translations.
///
/// Prior versions incorrectly stored `\n` (backslash + n) instead of actual
/// newline characters in translation_versions.translated_text. This causes
/// double-escaping at export time, resulting in `\\n` in game which displays
/// as `//` in-game.
///
/// This migration converts stored `\n` sequences to actual newline characters
/// to match how source texts are stored.
class FixEscapedNewlinesMigration extends Migration {
  @override
  String get id => 'fix_escaped_newlines';

  @override
  String get description => 'Fix escaped newline sequences in translations';

  @override
  int get priority => 50;

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      logging.debug('Checking for escaped newlines in translations...');

      // Check if there are any translations with escaped newlines
      final countResult = await DatabaseService.database.rawQuery('''
        SELECT COUNT(*) as cnt FROM translation_versions
        WHERE INSTR(translated_text, char(92) || 'n') > 0
      ''');
      final count = countResult.first['cnt'] as int;

      logging.debug('Found $count translations with potential escaped newlines');

      if (count == 0) {
        return false; // Nothing to fix
      }

      logging.info('Fixing escaped newlines in $count translation records...');

      // Process in batches
      const batchSize = 500;
      var totalProcessed = 0;

      while (true) {
        final updated = await DatabaseService.database.rawUpdate('''
          UPDATE translation_versions
          SET translated_text = REPLACE(
            REPLACE(translated_text, char(92) || 'r' || char(92) || 'n', char(10)),
            char(92) || 'n',
            char(10)
          )
          WHERE id IN (
            SELECT id FROM translation_versions
            WHERE INSTR(translated_text, char(92) || 'n') > 0
            LIMIT $batchSize
          )
        ''');

        if (updated == 0) break;

        totalProcessed += updated;
        logging.debug('Processed $totalProcessed / $count translations');

        // Yield to UI thread
        await Future.delayed(Duration.zero);
      }

      logging.info('Fixed escaped newlines, rebuilding search index...');

      // FTS rebuild
      await _rebuildFtsIndex(logging);

      logging.info('Fixed escaped newlines in $count translation records');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to fix escaped newlines', e, stackTrace);
      // Non-fatal: translations will still work, just display incorrectly
      return false;
    }
  }

  Future<void> _rebuildFtsIndex(LoggingService logging) async {
    try {
      await DatabaseService.execute('''
        INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')
      ''').timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          logging.warning('FTS rebuild timed out, will be done lazily');
        },
      );
    } catch (e) {
      logging.warning('FTS rebuild skipped: $e');
    }
  }
}
