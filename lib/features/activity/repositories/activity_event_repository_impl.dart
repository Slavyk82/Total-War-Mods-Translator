import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../../../repositories/base_repository.dart';
import '../models/activity_event.dart';
import 'activity_event_repository.dart';

/// SQLite-backed implementation of [ActivityEventRepository].
///
/// Extends [BaseRepository] to reuse the shared [executeQuery] error-
/// handling wrapper and database-initialization guard. Activity events
/// are append-only from the application's point of view: `getById`,
/// `getAll`, `update`, and `delete` are therefore not part of the
/// public repository contract and throw [UnsupportedError] if invoked.
class ActivityEventRepositoryImpl extends BaseRepository<ActivityEvent>
    implements ActivityEventRepository {
  @override
  String get tableName => 'activity_events';

  @override
  ActivityEvent fromMap(Map<String, dynamic> map) {
    return ActivityEvent.fromMap(map);
  }

  @override
  Map<String, dynamic> toMap(ActivityEvent entity) {
    return Map<String, dynamic>.from(entity.toMap());
  }

  @override
  Future<Result<ActivityEvent, TWMTDatabaseException>> insert(
    ActivityEvent event,
  ) async {
    return executeQuery(() async {
      // Strip the placeholder id so SQLite assigns a new AUTOINCREMENT value.
      final row = Map<String, Object?>.from(event.toMap())..remove('id');
      final newId = await database.insert(tableName, row);
      return ActivityEvent(
        id: newId,
        type: event.type,
        timestamp: event.timestamp,
        projectId: event.projectId,
        gameCode: event.gameCode,
        payload: event.payload,
      );
    });
  }

  @override
  Future<Result<List<ActivityEvent>, TWMTDatabaseException>> getRecent({
    String? gameCode,
    int limit = 20,
  }) async {
    return executeQuery(() async {
      final where = gameCode != null ? 'game_code = ?' : null;
      final whereArgs = gameCode != null ? <Object?>[gameCode] : null;
      final rows = await database.query(
        tableName,
        where: where,
        whereArgs: whereArgs,
        orderBy: 'timestamp DESC, id DESC',
        limit: limit,
      );
      return rows.map(ActivityEvent.fromMap).toList();
    });
  }

  // --- Unsupported CRUD operations ------------------------------------------
  //
  // Activity events are append-only; mutation and single-row lookup are not
  // part of the Home dashboard use case. These overrides satisfy the
  // [BaseRepository] contract while making accidental misuse fail loudly.

  @override
  Future<Result<ActivityEvent, TWMTDatabaseException>> getById(String id) {
    throw UnsupportedError(
      'ActivityEventRepository does not support getById.',
    );
  }

  @override
  Future<Result<List<ActivityEvent>, TWMTDatabaseException>> getAll() {
    throw UnsupportedError(
      'ActivityEventRepository does not support getAll; use getRecent instead.',
    );
  }

  @override
  Future<Result<ActivityEvent, TWMTDatabaseException>> update(
    ActivityEvent entity,
  ) {
    throw UnsupportedError(
      'ActivityEventRepository does not support update; events are immutable.',
    );
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) {
    throw UnsupportedError(
      'ActivityEventRepository does not support delete.',
    );
  }
}
