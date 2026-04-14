import 'dart:convert';

import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to convert legacy `validation_issues` payloads from Dart's
/// default `List.toString()` format into proper JSON arrays.
///
/// Prior versions wrote `result.allMessages.toString()` into
/// `translation_versions.validation_issues`, producing strings like
/// `[msg1, msg2]` that cannot be round-tripped through `jsonDecode`.
/// New code writes `jsonEncode(result.allMessages)`; this migration
/// rewrites the existing rows so consumers can rely on JSON everywhere.
///
/// Idempotency: a row whose value already starts with '[' AND decodes as
/// a JSON list is left untouched. Re-running the migration on a database
/// that has already been migrated is therefore a no-op.
///
/// Limitations of the legacy parser: `List.toString()` is not a
/// reversible format. The original messages were separated by `, `
/// (comma + space), so any individual message that itself contained
/// `, ` will be split into multiple entries by this migration. This
/// loss is considered acceptable because the field is advisory
/// (displayed to the user as a hint list); messages are short and
/// contain `, ` only rarely. Rows that fail to parse for any other
/// reason are logged and left alone rather than crashing the migration.
class ValidationIssuesJsonMigration extends Migration {
  final ILoggingService _logger;

  ValidationIssuesJsonMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'validation_issues_json';

  @override
  String get description =>
      'Re-encode legacy validation_issues payloads as JSON arrays';

  @override
  int get priority => 110;

  @override
  Future<bool> execute() async {
    try {
      _logger.debug('Scanning translation_versions for legacy '
          'validation_issues payloads...');

      final rows = await DatabaseService.database.rawQuery('''
        SELECT id, validation_issues FROM translation_versions
        WHERE validation_issues IS NOT NULL
          AND TRIM(validation_issues) <> ''
      ''');

      if (rows.isEmpty) {
        _logger.debug('No validation_issues rows to migrate.');
        return false;
      }

      _logger.info(
          'Evaluating ${rows.length} validation_issues rows for migration...');

      const batchSize = 500;
      var migrated = 0;
      var skipped = 0;
      var failed = 0;

      for (var i = 0; i < rows.length; i += batchSize) {
        final end = (i + batchSize < rows.length) ? i + batchSize : rows.length;

        for (var j = i; j < end; j++) {
          final row = rows[j];
          final id = row['id'] as String;
          final raw = row['validation_issues'] as String;

          if (_isAlreadyJson(raw)) {
            skipped++;
            continue;
          }

          final decoded = _parseDartListToString(raw);
          if (decoded == null) {
            failed++;
            _logger.warning(
              'Could not parse validation_issues for row; leaving as-is',
              {'id': id},
            );
            continue;
          }

          try {
            await DatabaseService.database.update(
              'translation_versions',
              {'validation_issues': jsonEncode(decoded)},
              where: 'id = ?',
              whereArgs: [id],
            );
            migrated++;
          } catch (e) {
            failed++;
            _logger.warning(
              'Failed to update validation_issues for row; leaving as-is',
              {'id': id, 'error': e.toString()},
            );
          }
        }

        // Yield between batches to avoid blocking the UI thread.
        await Future.delayed(Duration.zero);
      }

      _logger.info('validation_issues migration finished', {
        'migrated': migrated,
        'skipped': skipped,
        'failed': failed,
        'total': rows.length,
      });

      // Report "applied" only when we actually rewrote at least one row.
      return migrated > 0;
    } catch (e, stackTrace) {
      _logger.error(
          'validation_issues JSON migration failed (non-fatal)', e, stackTrace);
      // Non-fatal: translations continue to work; UI can still display
      // the legacy string even if parsing fails downstream.
      return false;
    }
  }

  /// Returns true if [raw] is already a valid JSON array payload.
  bool _isAlreadyJson(String raw) {
    final trimmed = raw.trimLeft();
    if (!trimmed.startsWith('[')) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort conversion of Dart's default `List.toString()` format
  /// (e.g. `[msg1, msg2, msg3]`) into a list of string messages.
  ///
  /// Returns null if the shape is unrecognisable (missing brackets).
  /// An empty list is returned for `[]`.
  ///
  /// Splitting is done on `, ` (comma + space) — the exact separator
  /// used by `List.toString()`. Messages that themselves contain `, `
  /// will be split into multiple entries; this is documented on the
  /// class doc comment and considered acceptable for this advisory field.
  List<String>? _parseDartListToString(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      return null;
    }
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) {
      return <String>[];
    }
    return inner.split(', ').map((s) => s.trim()).toList();
  }
}
