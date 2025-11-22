import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/game_installation.dart';
import 'base_repository.dart';

/// Repository for managing GameInstallation entities.
///
/// Provides CRUD operations and custom queries for game installations,
/// including filtering by game code and validation status.
class GameInstallationRepository extends BaseRepository<GameInstallation> {
  @override
  String get tableName => 'game_installations';

  @override
  GameInstallation fromMap(Map<String, dynamic> map) {
    return GameInstallation.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(GameInstallation entity) {
    return entity.toJson();
  }

  @override
  Future<Result<GameInstallation, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Game installation not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<GameInstallation>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'game_name ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<GameInstallation, TWMTDatabaseException>> insert(
      GameInstallation entity) async {
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
  Future<Result<GameInstallation, TWMTDatabaseException>> update(
      GameInstallation entity) async {
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
            'Game installation not found for update: ${entity.id}');
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
            'Game installation not found for deletion: $id');
      }
    });
  }

  /// Get a game installation by its game code.
  ///
  /// Returns [Ok] with the installation if found, [Err] with exception if not found.
  Future<Result<GameInstallation, TWMTDatabaseException>> getByGameCode(
      String gameCode) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'game_code = ?',
        whereArgs: [gameCode],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Game installation not found with game code: $gameCode');
      }

      return fromMap(maps.first);
    });
  }

  /// Get all valid game installations.
  ///
  /// Returns [Ok] with list of valid installations, ordered by game name.
  Future<Result<List<GameInstallation>, TWMTDatabaseException>> getValid() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_valid = ?',
        whereArgs: [1],
        orderBy: 'game_name ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }
}
