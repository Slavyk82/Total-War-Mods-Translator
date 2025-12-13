import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to fix backslash-before-newline pattern in translations.
///
/// Some LLM translations incorrectly produced backslash + newline sequences
/// like `text.\<newline>` instead of just `text.<newline>`.
/// This causes `\\` to appear before line breaks in game.
///
/// This migration removes spurious backslashes before newlines.
class FixBackslashNewlinesMigration extends Migration {
  @override
  String get id => 'fix_backslash_newlines';

  @override
  String get description => 'Fix backslash-before-newline patterns in translations';

  @override
  int get priority => 51; // Run right after escaped newlines fix

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      logging.debug('Checking for backslash-before-newline patterns...');

      // Check for backslash followed by newline (char 92 + char 10)
      final countResult = await DatabaseService.database.rawQuery('''
        SELECT COUNT(*) as cnt FROM translation_versions
        WHERE INSTR(translated_text, char(92) || char(10)) > 0
      ''');
      final count = countResult.first['cnt'] as int;

      logging.debug('Found $count translations with backslash-before-newline');

      if (count == 0) {
        return false; // Nothing to fix
      }

      logging.info('Fixing backslash-before-newline in $count translations...');

      // Process in batches
      const batchSize = 500;
      var totalProcessed = 0;

      while (true) {
        final updated = await DatabaseService.database.rawUpdate('''
          UPDATE translation_versions
          SET translated_text = REPLACE(translated_text, char(92) || char(10), char(10))
          WHERE id IN (
            SELECT id FROM translation_versions
            WHERE INSTR(translated_text, char(92) || char(10)) > 0
            LIMIT $batchSize
          )
        ''');

        if (updated == 0) break;

        totalProcessed += updated;
        logging.debug('Processed $totalProcessed / $count translations');

        // Yield to UI thread
        await Future.delayed(Duration.zero);
      }

      logging.info('Fixed backslash-before-newline in $totalProcessed translations');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to fix backslash-before-newline', e, stackTrace);
      // Non-fatal
      return false;
    }
  }
}
