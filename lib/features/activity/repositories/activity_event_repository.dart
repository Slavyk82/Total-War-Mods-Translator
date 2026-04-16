import '../../../models/common/result.dart';
import '../../../models/common/service_exception.dart';
import '../models/activity_event.dart';

/// Repository interface for persistent activity events.
///
/// Backs the Home dashboard feed by providing append (insert) and
/// query (getRecent) operations. Events are immutable; there is
/// intentionally no update or delete in this interface.
abstract class ActivityEventRepository {
  /// Insert a new activity event and return it with its assigned id.
  Future<Result<ActivityEvent, TWMTDatabaseException>> insert(
    ActivityEvent event,
  );

  /// Return the most recent events ordered by timestamp DESC (ties broken
  /// by id DESC). If [gameCode] is provided, results are filtered to that
  /// game; otherwise all events are returned.
  Future<Result<List<ActivityEvent>, TWMTDatabaseException>> getRecent({
    String? gameCode,
    int limit = 20,
  });
}
