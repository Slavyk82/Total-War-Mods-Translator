import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/language.dart';
import 'base_repository.dart';

/// Repository for managing Language entities.
///
/// Provides CRUD operations and custom queries for languages,
/// including filtering by code and active status.
class LanguageRepository extends BaseRepository<Language> {
  @override
  String get tableName => 'languages';

  @override
  Language fromMap(Map<String, dynamic> map) {
    return Language.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(Language entity) {
    return entity.toJson();
  }

  @override
  Future<Result<Language, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Language not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<Language>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'name ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<Language, TWMTDatabaseException>> insert(Language entity) async {
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
  Future<Result<Language, TWMTDatabaseException>> update(Language entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('Language not found for update: ${entity.id}');
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
        throw TWMTDatabaseException('Language not found for deletion: $id');
      }
    });
  }

  /// Get a language by its ISO code.
  ///
  /// Returns [Ok] with the language if found, [Err] with exception if not found.
  Future<Result<Language, TWMTDatabaseException>> getByCode(String code) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Language not found with code: $code');
      }

      return fromMap(maps.first);
    });
  }

  /// Get all active languages.
  ///
  /// Returns [Ok] with list of active languages, ordered by name.
  Future<Result<List<Language>, TWMTDatabaseException>> getActive() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get multiple languages by their IDs.
  ///
  /// Optimized batch retrieval to avoid N+1 query problems.
  /// Batches queries to stay within SQLite's parameter limit (999 max).
  /// Returns [Ok] with list of found languages (may be less than requested if some IDs don't exist).
  Future<Result<List<Language>, TWMTDatabaseException>> getByIds(
    List<String> ids,
  ) async {
    return executeQuery(() async {
      if (ids.isEmpty) {
        return <Language>[];
      }

      // SQLite has a limit on number of parameters (default 999)
      // Process in batches of 500 to stay well under the limit
      const batchSize = 500;
      final results = <Language>[];

      for (var i = 0; i < ids.length; i += batchSize) {
        final batch = ids.skip(i).take(batchSize).toList();
        final placeholders = List.filled(batch.length, '?').join(', ');

        final maps = await database.query(
          tableName,
          where: 'id IN ($placeholders)',
          whereArgs: batch,
          orderBy: 'name ASC',
        );

        results.addAll(maps.map((map) => fromMap(map)));
      }

      return results;
    });
  }

  /// Check if a language code already exists.
  ///
  /// Returns [Ok] with true if the code exists, false otherwise.
  Future<Result<bool, TWMTDatabaseException>> codeExists(String code) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        columns: ['id'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );

      return maps.isNotEmpty;
    });
  }

  /// Get all custom languages (user-added).
  ///
  /// Returns [Ok] with list of languages where is_custom = 1, ordered by name.
  Future<Result<List<Language>, TWMTDatabaseException>> getCustomLanguages() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_custom = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }
}
