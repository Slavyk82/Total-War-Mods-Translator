import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/repositories/base_repository.dart';

/// Repository for export history operations
class ExportHistoryRepository extends BaseRepository<ExportHistory> {
  @override
  String get tableName => 'export_history';

  @override
  ExportHistory fromMap(Map<String, dynamic> map) {
    return ExportHistory.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(ExportHistory item) {
    return item.toJson();
  }

  @override
  Future<Result<ExportHistory, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Export history not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<ExportHistory>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'exported_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<ExportHistory, TWMTDatabaseException>> insert(
      ExportHistory entity) async {
    return executeQuery(() async {
      await database.insert(tableName, toMap(entity));
      return entity;
    });
  }

  @override
  Future<Result<ExportHistory, TWMTDatabaseException>> update(
      ExportHistory entity) async {
    return executeQuery(() async {
      await database.update(
        tableName,
        toMap(entity),
        where: 'id = ?',
        whereArgs: [entity.id],
      );
      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Get export history for a specific project
  ///
  /// Returns all export records for the given project, ordered by most recent first
  Future<List<ExportHistory>> getByProject(String projectId) async {
    final db = database;

    final maps = await db.query(
      tableName,
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'exported_at DESC',
    );

    return maps.map((map) => fromMap(map)).toList();
  }

  /// Get export history for a specific format
  ///
  /// Returns all export records for the given format, ordered by most recent first
  Future<List<ExportHistory>> getByFormat(ExportFormat format) async {
    final db = database;

    final formatValue = format.toString().split('.').last;

    final maps = await db.query(
      tableName,
      where: 'format = ?',
      whereArgs: [formatValue],
      orderBy: 'exported_at DESC',
    );

    return maps.map((map) => fromMap(map)).toList();
  }

  /// Get recent export history
  ///
  /// Returns the N most recent exports across all projects
  Future<List<ExportHistory>> getRecent({int limit = 10}) async {
    final db = database;

    final maps = await db.query(
      tableName,
      orderBy: 'exported_at DESC',
      limit: limit,
    );

    return maps.map((map) => fromMap(map)).toList();
  }

  /// Delete old export history records
  ///
  /// Removes export history records older than the specified number of days
  Future<int> deleteOlderThan({required int days}) async {
    final db = database;

    final cutoffTimestamp =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/
            1000;

    return await db.delete(
      tableName,
      where: 'exported_at < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  /// Ensure the export_history table exists
  ///
  /// Creates the table if it doesn't exist
  Future<void> ensureTableExists() async {
    final db = database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS export_history (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        languages TEXT NOT NULL,
        format TEXT NOT NULL,
        validated_only INTEGER NOT NULL DEFAULT 0,
        output_path TEXT NOT NULL,
        file_size INTEGER,
        entry_count INTEGER NOT NULL,
        exported_at INTEGER NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        CHECK (format IN ('pack', 'csv', 'excel', 'tmx')),
        CHECK (validated_only IN (0, 1))
      )
    ''');

    // Create indexes for better query performance
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_export_history_project
      ON export_history(project_id, exported_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_export_history_format
      ON export_history(format, exported_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_export_history_exported_at
      ON export_history(exported_at DESC)
    ''');
  }
}
