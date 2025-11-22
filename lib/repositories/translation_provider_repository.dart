import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_provider.dart';
import 'base_repository.dart';

/// Repository for managing TranslationProvider entities.
///
/// Provides CRUD operations and custom queries for translation providers,
/// including filtering by code and active status.
class TranslationProviderRepository
    extends BaseRepository<TranslationProvider> {
  @override
  String get tableName => 'translation_providers';

  @override
  TranslationProvider fromMap(Map<String, dynamic> map) {
    return TranslationProvider.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationProvider entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationProvider, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Translation provider not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationProvider>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'name ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationProvider, TWMTDatabaseException>> insert(
      TranslationProvider entity) async {
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
  Future<Result<TranslationProvider, TWMTDatabaseException>> update(
      TranslationProvider entity) async {
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
            'Translation provider not found for update: ${entity.id}');
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
        throw TWMTDatabaseException(
            'Translation provider not found for deletion: $id');
      }
    });
  }

  /// Get a translation provider by its code.
  ///
  /// Returns [Ok] with the provider if found, [Err] with exception if not found.
  Future<Result<TranslationProvider, TWMTDatabaseException>> getByCode(
      String code) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation provider not found with code: $code');
      }

      return fromMap(maps.first);
    });
  }

  /// Get all active translation providers.
  ///
  /// Returns [Ok] with list of active providers, ordered by name.
  Future<Result<List<TranslationProvider>, TWMTDatabaseException>>
      getActive() async {
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
}
