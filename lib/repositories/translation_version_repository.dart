import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_version.dart';
import 'base_repository.dart';
import 'mixins/translation_version_batch_mixin.dart';
import 'mixins/translation_version_statistics_mixin.dart';

/// Repository for managing TranslationVersion entities.
///
/// Provides CRUD operations and custom queries for translation versions,
/// including filtering by unit, project language, and status.
///
/// Complex operations are delegated to mixins:
/// - [TranslationVersionBatchMixin]: Batch insert/upsert operations
/// - [TranslationVersionStatisticsMixin]: Statistics and counting queries
class TranslationVersionRepository extends BaseRepository<TranslationVersion>
    with TranslationVersionBatchMixin, TranslationVersionStatisticsMixin {
  @override
  String get tableName => 'translation_versions';

  @override
  TranslationVersion fromMap(Map<String, dynamic> map) {
    return TranslationVersion.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationVersion entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationVersion, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation version not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationVersion, TWMTDatabaseException>> insert(
      TranslationVersion entity) async {
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
  Future<Result<TranslationVersion, TWMTDatabaseException>> update(
      TranslationVersion entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      // Remove id from map - we cannot update PRIMARY KEY
      map.remove('id');

      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Translation version not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  /// Upsert (INSERT or UPDATE) a single translation version.
  ///
  /// If translation exists for (unitId, projectLanguageId), UPDATE it.
  /// If not, INSERT new translation.
  ///
  /// Uses a transaction to ensure atomicity of the read-modify-write pattern.
  Future<Result<TranslationVersion, TWMTDatabaseException>> upsert(
      TranslationVersion entity) async {
    return executeTransaction((txn) async {
      // Check if translation exists (within transaction for atomicity)
      final existingMaps = await txn.query(
        tableName,
        where: 'unit_id = ? AND project_language_id = ?',
        whereArgs: [entity.unitId, entity.projectLanguageId],
        columns: ['id', 'created_at'],
        limit: 1,
      );

      if (existingMaps.isNotEmpty) {
        // UPDATE: Preserve original ID and createdAt
        final existing = existingMaps.first;
        final existingId = existing['id'] as String;
        final existingCreatedAt = existing['created_at'] as int;

        final map = toMap(entity);
        map['id'] = existingId;
        map['created_at'] = existingCreatedAt;
        map.remove('id'); // Remove from UPDATE fields

        await txn.update(
          tableName,
          map,
          where: 'id = ?',
          whereArgs: [existingId],
        );

        return entity;
      } else {
        // INSERT: Use entity's ID and timestamps
        final map = toMap(entity);
        await txn.insert(
          tableName,
          map,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        return entity;
      }
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
        throw TWMTDatabaseException(
            'Translation version not found for deletion: $id');
      }
    });
  }

  /// Get all translation versions for a specific unit.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> getByUnit(
      String unitId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'unit_id = ?',
        whereArgs: [unitId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all translation versions for a specific project language.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>>
      getByProjectLanguage(String projectLanguageId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_language_id = ?',
        whereArgs: [projectLanguageId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all translation versions with a specific status.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> getByStatus(
      String status) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'status = ?',
        whereArgs: [status],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all untranslated unit IDs for a specific project language.
  Future<Result<List<String>, TWMTDatabaseException>> getUntranslatedIds({
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.rawQuery(
        '''
        SELECT tu.id
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = ?
          AND (tv.translated_text IS NULL OR tv.translated_text = '')
          AND tu.is_obsolete = 0
        ORDER BY tu.key
        ''',
        [projectLanguageId],
      );

      return maps.map((map) => map['id'] as String).toList();
    });
  }

  /// Filter a list of IDs to only include untranslated ones.
  ///
  /// Requires [projectLanguageId] to avoid returning duplicates when
  /// the same unit has multiple translation versions (one per language).
  Future<Result<List<String>, TWMTDatabaseException>> filterUntranslatedIds({
    required List<String> ids,
    required String projectLanguageId,
  }) async {
    if (ids.isEmpty) {
      return Ok([]);
    }

    return executeQuery(() async {
      final placeholders = List.filled(ids.length, '?').join(',');

      final maps = await database.rawQuery(
        '''
        SELECT unit_id
        FROM translation_versions
        WHERE unit_id IN ($placeholders)
          AND project_language_id = ?
          AND (translated_text IS NULL OR translated_text = '')
        ''',
        [...ids, projectLanguageId],
      );

      return maps.map((map) => map['unit_id'] as String).toList();
    });
  }

  /// Get IDs of units that are already translated.
  ///
  /// Performance optimization: Single batch query instead of N individual queries.
  /// Returns only unit IDs that have non-empty translated_text.
  Future<Result<Set<String>, TWMTDatabaseException>> getTranslatedUnitIds({
    required List<String> unitIds,
    required String projectLanguageId,
  }) async {
    if (unitIds.isEmpty) {
      return Ok(<String>{});
    }

    return executeQuery(() async {
      final placeholders = List.filled(unitIds.length, '?').join(',');
      final maps = await database.rawQuery(
        '''
        SELECT unit_id FROM $tableName
        WHERE unit_id IN ($placeholders)
          AND project_language_id = ?
          AND translated_text IS NOT NULL
          AND translated_text != ''
        ''',
        [...unitIds, projectLanguageId],
      );

      return maps.map((m) => m['unit_id'] as String).toSet();
    });
  }

  /// Get translation version by unit and project language.
  Future<Result<TranslationVersion, TWMTDatabaseException>>
      getByUnitAndProjectLanguage({
    required String unitId,
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'unit_id = ? AND project_language_id = ?',
        whereArgs: [unitId, projectLanguageId],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
          'Translation version not found for unit $unitId and project language $projectLanguageId',
        );
      }

      return fromMap(maps.first);
    });
  }

  /// Clear translations for multiple versions in a single SQL query.
  ///
  /// Sets translated_text to empty, status to pending, and updates timestamp.
  /// Returns the count of affected rows.
  Future<Result<int, TWMTDatabaseException>> clearBatch(
      List<String> versionIds) async {
    if (versionIds.isEmpty) {
      return Ok(0);
    }

    return executeQuery(() async {
      final placeholders = List.filled(versionIds.length, '?').join(',');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final rowsAffected = await database.rawUpdate(
        '''
        UPDATE $tableName
        SET translated_text = '',
            status = 'pending',
            updated_at = ?
        WHERE id IN ($placeholders)
        ''',
        [now, ...versionIds],
      );

      return rowsAffected;
    });
  }
}
