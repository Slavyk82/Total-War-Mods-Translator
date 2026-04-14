import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  /// Name of the lightweight marker table used to record completion.
  ///
  /// A dedicated table (rather than `PRAGMA user_version`, which is reserved
  /// for the schema version) lets data migrations record "we already ran"
  /// without re-scanning large tables at every startup.
  static const String _markerTable = '_migration_markers';

  @override
  Future<bool> isApplied() async {
    await _ensureMarkerTable();

    // Fast path: a marker was written by a previous successful run.
    final marker = await DatabaseService.database.rawQuery(
      'SELECT 1 FROM $_markerTable WHERE id = ? LIMIT 1',
      [id],
    );
    if (marker.isNotEmpty) return true;

    // Fallback for databases migrated before the marker existed: if no
    // legacy-shaped rows remain, treat as applied and write the marker so
    // future startups skip the scan entirely.
    //
    // Legacy `List.toString()` rows start with `[` but not with `["`, `[]`,
    // or `[{"` — the three shapes produced by `jsonEncode` for this field.
    // This check is O(N) over an indexed-less scan but uses no decoding.
    final legacy = await DatabaseService.database.rawQuery('''
      SELECT 1 FROM translation_versions
      WHERE validation_issues IS NOT NULL
        AND TRIM(validation_issues) <> ''
        AND validation_issues NOT LIKE '["%'
        AND validation_issues NOT LIKE '[]'
        AND validation_issues NOT LIKE '[{"%'
      LIMIT 1
    ''');
    if (legacy.isEmpty) {
      await _writeMarker();
      return true;
    }
    return false;
  }

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
        await _writeMarker();
        return false;
      }

      _logger.info(
          'Evaluating ${rows.length} validation_issues rows for migration...');

      const batchSize = 500;
      var migrated = 0;
      var skipped = 0;
      var failed = 0;
      var splitOnCommaSamples = 0;

      for (var i = 0; i < rows.length; i += batchSize) {
        final end = (i + batchSize < rows.length) ? i + batchSize : rows.length;

        // Wrap each chunk in a transaction so the rewrites commit atomically
        // per batch. Individual row errors are swallowed inside the loop so
        // a single bad row does not abort its entire batch.
        await DatabaseService.database.transaction((txn) async {
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

            // Track a few samples of rows whose messages contained `, `,
            // which the heuristic split would have fragmented.
            if (raw.contains(', ') && splitOnCommaSamples < 5) {
              splitOnCommaSamples++;
              _logger.debug(
                'validation_issues row contained `, ` — messages may have '
                'been split by the heuristic parser',
                {'id': id, 'raw': raw},
              );
            }

            try {
              await txn.update(
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
        });

        // Yield between batches to avoid blocking the UI thread.
        await Future.delayed(Duration.zero);
      }

      _logger.info('validation_issues migration finished', {
        'migrated': migrated,
        'skipped': skipped,
        'failed': failed,
        'total': rows.length,
      });

      // Write the marker unconditionally: we scanned every row and handled
      // what could be handled. Rows that failed to parse will stay legacy
      // forever, but re-running the scan on every startup would not rescue
      // them — it would just re-confirm the same failure at a large cost.
      await _writeMarker();

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

  /// Create the marker table if it does not yet exist.
  Future<void> _ensureMarkerTable() async {
    await DatabaseService.database.execute('''
      CREATE TABLE IF NOT EXISTS $_markerTable (
        id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL
      )
    ''');
  }

  /// Record that this migration has completed its work on this database.
  Future<void> _writeMarker() async {
    await _ensureMarkerTable();
    await DatabaseService.database.insert(
      _markerTable,
      {
        'id': id,
        'applied_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
  /// Attempts `jsonDecode` first: some rows were written by newer code
  /// in valid JSON but with non-string elements, which [_isAlreadyJson]
  /// accepts only when elements are strings. Falls back to splitting on
  /// `, ` — the exact separator used by `List.toString()`. Messages that
  /// themselves contain `, ` will be split into multiple entries; this is
  /// documented on the class doc comment and considered acceptable for
  /// this advisory field.
  ///
  /// Returns null if the shape is unrecognisable (missing brackets).
  /// An empty list is returned for `[]`.
  List<String>? _parseDartListToString(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      return null;
    }

    // Prefer valid JSON when possible to avoid fragmenting messages on `, `.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Fall through to the heuristic split.
    }

    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) {
      return <String>[];
    }
    return inner.split(', ').map((s) => s.trim()).toList();
  }
}
