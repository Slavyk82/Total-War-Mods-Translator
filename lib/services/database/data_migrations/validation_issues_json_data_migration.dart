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
}
