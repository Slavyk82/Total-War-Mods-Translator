import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/project_publication.dart';
import 'base_repository.dart';

/// Repository for `project_publication` rows — the published Workshop id of a
/// project's translation, keyed by (project_id, language_code).
class ProjectPublicationRepository
    extends BaseRepository<ProjectPublication> {
  @override
  String get tableName => 'project_publication';

  @override
  ProjectPublication fromMap(Map<String, dynamic> map) =>
      ProjectPublication.fromJson(map);

  @override
  Map<String, dynamic> toMap(ProjectPublication entity) => entity.toJson();

  @override
  Future<Result<ProjectPublication, TWMTDatabaseException>> getById(
      String id) async {
    return Err(TWMTDatabaseException(
        'getById is not supported: project_publication has a composite key'));
  }

  @override
  Future<Result<List<ProjectPublication>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(tableName);
      return maps.map(fromMap).toList();
    });
  }

  @override
  Future<Result<ProjectPublication, TWMTDatabaseException>> insert(
      ProjectPublication entity) async {
    return executeQuery(() async {
      await database.insert(tableName, toMap(entity));
      return entity;
    });
  }

  @override
  Future<Result<ProjectPublication, TWMTDatabaseException>> update(
      ProjectPublication entity) async {
    return setPublication(entity.projectId, entity.languageCode,
            entity.steamId ?? '', entity.publishedAt ?? 0)
        .then((r) => r.isOk
            ? Ok<ProjectPublication, TWMTDatabaseException>(entity)
            : Err<ProjectPublication, TWMTDatabaseException>(r.error));
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return Err(TWMTDatabaseException(
        'delete(id) is not supported: project_publication has a composite key'));
  }

  /// All publication rows for one project (usually one per target language).
  Future<Result<List<ProjectPublication>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      return maps.map(fromMap).toList();
    });
  }

  /// Upsert the published Workshop id AND publish timestamp for a
  /// (project, language). Used after a successful publish.
  Future<Result<void, TWMTDatabaseException>> setPublication(
      String projectId, String languageCode, String steamId,
      int publishedAt) async {
    return executeQuery(() async {
      await database.execute('''
        INSERT INTO project_publication
          (project_id, language_code, steam_id, published_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(project_id, language_code) DO UPDATE SET
          steam_id = excluded.steam_id,
          published_at = excluded.published_at
      ''', [projectId, languageCode, steamId, publishedAt]);
    });
  }

  /// Upsert ONLY the Workshop id for a (project, language), preserving any
  /// existing publish timestamp. Used by the manual "set Workshop ID" editor,
  /// which must not stamp a publish time (that would mark the item outdated).
  Future<Result<void, TWMTDatabaseException>> setSteamId(
      String projectId, String languageCode, String steamId) async {
    return executeQuery(() async {
      await database.execute('''
        INSERT INTO project_publication
          (project_id, language_code, steam_id)
        VALUES (?, ?, ?)
        ON CONFLICT(project_id, language_code) DO UPDATE SET
          steam_id = excluded.steam_id
      ''', [projectId, languageCode, steamId]);
    });
  }
}
