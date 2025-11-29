import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/glossary_entry.dart';
import '../services/glossary/models/glossary.dart';
import 'base_repository.dart';

/// Repository for managing Glossary and GlossaryEntry entities.
///
/// Provides CRUD operations for both glossaries and their entries,
/// including filtering by project and language.
class GlossaryRepository extends BaseRepository<GlossaryEntry> {
  @override
  String get tableName => 'glossary_entries';

  /// Table name for glossaries (not entries)
  String get glossaryTableName => 'glossaries';

  @override
  GlossaryEntry fromMap(Map<String, dynamic> map) {
    return GlossaryEntry.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(GlossaryEntry entity) {
    return entity.toJson();
  }

  @override
  Future<Result<GlossaryEntry, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Glossary entry not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<GlossaryEntry>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'source_term ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<GlossaryEntry, TWMTDatabaseException>> insert(
      GlossaryEntry entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      await database.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return entity;
    });
  }

  @override
  Future<Result<GlossaryEntry, TWMTDatabaseException>> update(
      GlossaryEntry entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Glossary entry not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('Glossary entry not found for deletion: $id');
      }
    });
  }

  /// Get all glossary entries for a specific project.
  ///
  /// This includes both project-specific entries (where project_id matches)
  /// and global entries (where project_id is NULL).
  ///
  /// Returns [Ok] with list of entries, ordered by source term.
  Future<Result<List<GlossaryEntry>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? OR project_id IS NULL',
        whereArgs: [projectId],
        orderBy: 'source_term ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all glossary entries for a specific project and language.
  ///
  /// This includes both project-specific entries (where project_id matches)
  /// and global entries (where project_id is NULL), filtered by language.
  ///
  /// Returns [Ok] with list of entries, ordered by source term.
  Future<Result<List<GlossaryEntry>, TWMTDatabaseException>>
      getByProjectAndLanguage(String projectId, String languageId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: '(project_id = ? OR project_id IS NULL) AND language_id = ?',
        whereArgs: [projectId, languageId],
        orderBy: 'source_term ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  // ============================================================================
  // Glossary (not Entry) Methods
  // ============================================================================

  /// Get glossary by name
  Future<Glossary?> getByName(String name) async {
    final maps = await database.rawQuery('''
      SELECT 
        g.*,
        COALESCE(COUNT(ge.id), 0) as entry_count
      FROM $glossaryTableName g
      LEFT JOIN $tableName ge ON g.id = ge.glossary_id
      WHERE g.name = ?
      GROUP BY g.id
      LIMIT 1
    ''', [name]);
    return maps.isEmpty ? null : Glossary.fromJson(maps.first);
  }

  /// Get glossary by ID (returns Glossary, not GlossaryEntry)
  Future<Glossary?> getGlossaryById(String id) async {
    final maps = await database.rawQuery('''
      SELECT 
        g.*,
        COALESCE(COUNT(ge.id), 0) as entry_count
      FROM $glossaryTableName g
      LEFT JOIN $tableName ge ON g.id = ge.glossary_id
      WHERE g.id = ?
      GROUP BY g.id
      LIMIT 1
    ''', [id]);
    return maps.isEmpty ? null : Glossary.fromJson(maps.first);
  }

  /// Get all glossaries
  ///
  /// [gameInstallationId] - If specified, returns universal + game-specific glossaries
  /// [includeUniversal] - Include universal glossaries (is_global = 1) in result
  Future<List<Glossary>> getAllGlossaries({
    String? gameInstallationId,
    bool includeUniversal = true,
  }) async {
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (gameInstallationId != null) {
      if (includeUniversal) {
        whereClause = ' WHERE g.is_global = 1 OR g.game_installation_id = ?';
        whereArgs = [gameInstallationId];
      } else {
        whereClause = ' WHERE g.game_installation_id = ?';
        whereArgs = [gameInstallationId];
      }
    } else if (!includeUniversal) {
      whereClause = ' WHERE g.is_global = 0';
    }

    // Query with LEFT JOIN to count entries
    final maps = await database.rawQuery('''
      SELECT 
        g.*,
        COALESCE(COUNT(ge.id), 0) as entry_count
      FROM $glossaryTableName g
      LEFT JOIN $tableName ge ON g.id = ge.glossary_id
      $whereClause
      GROUP BY g.id
      ORDER BY g.name ASC
    ''', whereArgs);

    return maps.map((map) => Glossary.fromJson(map)).toList();
  }

  /// Get glossaries by IDs
  Future<List<Glossary>> getGlossariesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = ids.map((_) => '?').join(',');
    final maps = await database.rawQuery('''
      SELECT 
        g.*,
        COALESCE(COUNT(ge.id), 0) as entry_count
      FROM $glossaryTableName g
      LEFT JOIN $tableName ge ON g.id = ge.glossary_id
      WHERE g.id IN ($placeholders)
      GROUP BY g.id
    ''', ids);
    return maps.map((map) => Glossary.fromJson(map)).toList();
  }

  /// Insert glossary
  Future<void> insertGlossary(Glossary glossary) async {
    await database.insert(
      glossaryTableName,
      glossary.toJson(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Update glossary
  Future<void> updateGlossary(Glossary glossary) async {
    await database.update(
      glossaryTableName,
      glossary.toJson(),
      where: 'id = ?',
      whereArgs: [glossary.id],
    );
  }

  /// Delete glossary
  Future<void> deleteGlossary(String id) async {
    await database.delete(
      glossaryTableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ============================================================================
  // GlossaryEntry Methods
  // ============================================================================

  /// Get entry by ID
  Future<GlossaryEntry?> getEntryById(String id) async {
    final maps = await database.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : fromMap(maps.first);
  }

  /// Get entries by glossary
  Future<List<GlossaryEntry>> getEntriesByGlossary({
    required String glossaryId,
    String? targetLanguageCode,
  }) async {
    print('[GlossaryRepository.getEntriesByGlossary] Fetching entries:');
    print('  glossaryId: $glossaryId');
    print('  targetLanguageCode: $targetLanguageCode');
    
    final conditions = ['glossary_id = ?'];
    final args = <dynamic>[glossaryId];

    if (targetLanguageCode != null) {
      conditions.add('target_language_code = ?');
      args.add(targetLanguageCode);
    }

    print('[GlossaryRepository.getEntriesByGlossary] Query: WHERE ${conditions.join(' AND ')}');
    print('[GlossaryRepository.getEntriesByGlossary] Args: $args');

    final maps = await database.query(
      tableName,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'source_term ASC',
    );
    
    print('[GlossaryRepository.getEntriesByGlossary] Found ${maps.length} entries');
    if (maps.isNotEmpty) {
      print('[GlossaryRepository.getEntriesByGlossary] First entry: ${maps.first}');
    }
    
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Insert entry
  Future<void> insertEntry(GlossaryEntry entry) async {
    print('[GlossaryRepository.insertEntry] Inserting entry: ${entry.id}');
    print('  glossaryId: ${entry.glossaryId}');
    print('  sourceTerm: "${entry.sourceTerm}"');
    print('  targetTerm: "${entry.targetTerm}"');
    print('  Entry map: ${toMap(entry)}');
    
    try {
      final result = await database.insert(
        tableName,
        toMap(entry),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      print('[GlossaryRepository.insertEntry] Insert successful, rowId: $result');
    } catch (e, stackTrace) {
      print('[GlossaryRepository.insertEntry] ERROR inserting entry: $e');
      print('[GlossaryRepository.insertEntry] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Update entry
  Future<void> updateEntry(GlossaryEntry entry) async {
    await database.update(
      tableName,
      toMap(entry),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  /// Delete entry
  Future<void> deleteEntry(String id) async {
    await database.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Find duplicate entry
  Future<GlossaryEntry?> findDuplicateEntry({
    required String glossaryId,
    required String targetLanguageCode,
    required String sourceTerm,
  }) async {
    final maps = await database.query(
      tableName,
      where: 'glossary_id = ? AND target_language_code = ? AND source_term = ?',
      whereArgs: [glossaryId, targetLanguageCode, sourceTerm],
      limit: 1,
    );
    return maps.isEmpty ? null : fromMap(maps.first);
  }

  /// Search entries
  Future<List<GlossaryEntry>> searchEntries({
    required String query,
    List<String>? glossaryIds,
    String? targetLanguageCode,
  }) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    // Search in source_term or target_term
    conditions.add('(source_term LIKE ? OR target_term LIKE ?)');
    args.add('%$query%');
    args.add('%$query%');

    if (glossaryIds != null && glossaryIds.isNotEmpty) {
      final placeholders = glossaryIds.map((_) => '?').join(',');
      conditions.add('glossary_id IN ($placeholders)');
      args.addAll(glossaryIds);
    }
    if (targetLanguageCode != null) {
      conditions.add('target_language_code = ?');
      args.add(targetLanguageCode);
    }

    final maps = await database.query(
      tableName,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'source_term ASC',
    );
    return maps.map((map) => fromMap(map)).toList();
  }

  /// Get entry count for glossary
  Future<int> getEntryCount(String glossaryId) async {
    final result = await database.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE glossary_id = ?',
      [glossaryId],
    );
    final count = result.firstOrNull?['count'];
    return count is int ? count : 0;
  }

  /// Increment usage count for a list of entry IDs
  ///
  /// [entryIds] - List of glossary entry IDs to increment usage count for
  Future<void> incrementUsageCount(List<String> entryIds) async {
    if (entryIds.isEmpty) return;

    final placeholders = entryIds.map((_) => '?').join(',');
    await database.rawUpdate('''
      UPDATE $tableName
      SET usage_count = usage_count + 1
      WHERE id IN ($placeholders)
    ''', entryIds);
  }

  /// Get usage statistics for a glossary
  ///
  /// Returns map with:
  /// - usedCount: Number of entries with usage_count > 0
  /// - unusedCount: Number of entries with usage_count = 0
  /// - totalUsage: Sum of all usage_count values
  Future<Map<String, int>> getUsageStats(String glossaryId) async {
    final result = await database.rawQuery('''
      SELECT
        COUNT(CASE WHEN usage_count > 0 THEN 1 END) as used_count,
        COUNT(CASE WHEN usage_count = 0 THEN 1 END) as unused_count,
        COALESCE(SUM(usage_count), 0) as total_usage
      FROM $tableName
      WHERE glossary_id = ?
    ''', [glossaryId]);

    if (result.isEmpty) {
      return {'usedCount': 0, 'unusedCount': 0, 'totalUsage': 0};
    }

    final row = result.first;
    return {
      'usedCount': (row['used_count'] as int?) ?? 0,
      'unusedCount': (row['unused_count'] as int?) ?? 0,
      'totalUsage': (row['total_usage'] as int?) ?? 0,
    };
  }
}
