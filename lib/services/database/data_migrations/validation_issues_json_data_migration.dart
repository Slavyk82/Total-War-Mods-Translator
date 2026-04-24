import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';

/// Post-`runApp` data migration that rewrites legacy `validation_issues`
/// payloads (Dart `List.toString()` / `Map.toString()` output) as proper
/// JSON arrays. Invoked from `DataMigration.runMigrations()`.
class ValidationIssuesJsonDataMigration {
  final ILoggingService _logger;

  ValidationIssuesJsonDataMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// Stable identifier — reused from the old pre-runApp migration so existing
  /// markers in already-migrated databases short-circuit [isApplied] on the
  /// first call.
  static const String id = 'validation_issues_json';

  static const String _markerTable = '_migration_markers';

  /// Fast-path applicability check.
  ///
  /// Order:
  /// 1. Marker row present => applied.
  /// 2. No legacy-shaped row remaining => write marker and return applied.
  /// 3. Otherwise => not applied; caller should invoke [run].
  Future<bool> isApplied() async {
    await _ensureMarkerTable();
    final marker = await DatabaseService.database.rawQuery(
      'SELECT 1 FROM $_markerTable WHERE id = ? LIMIT 1',
      [id],
    );
    if (marker.isNotEmpty) return true;

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

  Future<void> _ensureMarkerTable() async {
    await DatabaseService.database.execute('''
      CREATE TABLE IF NOT EXISTS $_markerTable (
        id TEXT PRIMARY KEY,
        applied_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _writeMarker() async {
    await _ensureMarkerTable();
    await DatabaseService.database.insert(
      _markerTable,
      {'id': id, 'applied_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Page size for the keyset-paginated rewrite loop. Sized to give the
  /// progress callback frequent updates on a 30k-row database without
  /// incurring per-statement transaction overhead.
  static const int _batchSize = 500;

  /// Rewrite legacy payloads and restore triggers inside a single
  /// transaction. FTS rebuild and marker write are the caller's
  /// responsibility (see [run]).
  Future<void> execute({
    required void Function(int processed, int total) onProgress,
  }) async {
    final db = DatabaseService.database;

    final totalRow = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM translation_versions
      WHERE validation_issues IS NOT NULL
        AND TRIM(validation_issues) <> ''
    ''');
    final total = (totalRow.first['cnt'] as int?) ?? 0;
    if (total == 0) {
      _logger.debug('validation_issues: no candidate rows');
      onProgress(0, 0);
      return;
    }

    _logger.info('validation_issues: rewriting $total rows');

    await db.transaction((txn) async {
      for (final name in _triggerDdl.keys) {
        await txn.execute('DROP TRIGGER IF EXISTS $name');
      }

      String? cursor;
      var processed = 0;
      var splitOnCommaSamples = 0;

      while (true) {
        final whereCursor = cursor == null ? '' : 'AND id > ?';
        final args = cursor == null ? <Object?>[] : <Object?>[cursor];

        final rows = await txn.rawQuery('''
          SELECT id, validation_issues FROM translation_versions
          WHERE validation_issues IS NOT NULL
            AND TRIM(validation_issues) <> ''
            $whereCursor
          ORDER BY id
          LIMIT $_batchSize
        ''', args);

        if (rows.isEmpty) break;

        for (final row in rows) {
          final rowId = row['id'] as String;
          final raw = row['validation_issues'] as String;

          if (!_isAlreadyJson(raw)) {
            final decoded = _parseDartListToString(raw);
            if (decoded != null) {
              if (raw.contains(', ') && splitOnCommaSamples < 5) {
                splitOnCommaSamples++;
                _logger.debug(
                  'validation_issues row contained `, ` — messages may have '
                  'been split by the heuristic parser',
                  {'id': rowId, 'raw': raw},
                );
              }
              await txn.update(
                'translation_versions',
                {'validation_issues': jsonEncode(decoded)},
                where: 'id = ?',
                whereArgs: [rowId],
              );
            } else {
              _logger.warning(
                'Could not parse validation_issues; leaving as-is',
                {'id': rowId},
              );
            }
          }
          cursor = rowId;
        }

        processed += rows.length;
        onProgress(processed, total);
      }

      for (final entry in _triggerDdl.entries) {
        await txn.execute(entry.value);
      }
    });
  }

  /// Top-level entry point: performs the rewrite transaction, then attempts
  /// an FTS5 rebuild (best-effort — contentless FTS5 rebuild is not always
  /// supported; stale FTS is tolerable since the field is advisory), and
  /// finally writes the marker. The marker is the last write: if any step
  /// above throws, the marker is not written and the next startup re-runs
  /// the migration.
  Future<void> run({
    required void Function(int processed, int total) onProgress,
  }) async {
    await execute(onProgress: onProgress);
    try {
      await DatabaseService.database.execute(
        "INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')",
      );
    } catch (e) {
      _logger.warning(
        'validation_issues: FTS rebuild skipped (non-fatal)',
        {'error': e.toString()},
      );
    }
    await _writeMarker();
    _logger.info('validation_issues: migration finished');
  }

  /// DDL for the 3 triggers the rewrite drops. Copied verbatim from
  /// `schema.sql` (lines 729-737, 791-803, 877-882) minus `IF NOT EXISTS`,
  /// which would silently suppress recreation failures.
  static const Map<String, String> _triggerDdl = {
    'trg_translation_versions_fts_update': '''
CREATE TRIGGER trg_translation_versions_fts_update
AFTER UPDATE OF translated_text, validation_issues ON translation_versions
BEGIN
    DELETE FROM translation_versions_fts WHERE version_id = old.id;
    INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
    SELECT new.translated_text, new.validation_issues, new.id
    WHERE new.translated_text IS NOT NULL;
END
''',
    'trg_update_cache_on_version_change': '''
CREATE TRIGGER trg_update_cache_on_version_change
AFTER UPDATE ON translation_versions
BEGIN
    UPDATE translation_view_cache
    SET translated_text = new.translated_text,
        status = new.status,
        confidence_score = NULL,
        is_manually_edited = new.is_manually_edited,
        version_id = new.id,
        version_updated_at = new.updated_at
    WHERE unit_id = new.unit_id
      AND project_language_id = new.project_language_id;
END
''',
    'trg_translation_versions_updated_at': '''
CREATE TRIGGER trg_translation_versions_updated_at
AFTER UPDATE ON translation_versions
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END
''',
  };

  bool _isAlreadyJson(String raw) {
    final trimmed = raw.trimLeft();
    if (!trimmed.startsWith('[')) return false;
    try {
      return jsonDecode(raw) is List;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort conversion of `List.toString()` / `Map.toString()` output
  /// into a list of string messages. Prefers a real `jsonDecode` when the
  /// payload happens to be valid JSON with non-string elements; falls back
  /// to splitting on `, ` — the exact separator `List.toString()` uses.
  /// Returns null only when the shape is unrecognizable (missing brackets).
  List<String>? _parseDartListToString(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Fall through to heuristic split.
    }

    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return <String>[];
    return inner.split(', ').map((s) => s.trim()).toList();
  }
}
