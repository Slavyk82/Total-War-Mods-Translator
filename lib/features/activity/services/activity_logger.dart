import '../models/activity_event.dart';

/// Fire-and-forget service that persists [ActivityEvent]s for the Home
/// dashboard feed.
///
/// Implementations must never throw: failures to persist are logged via
/// the app logger and otherwise swallowed. Callers should treat this as
/// a best-effort side-channel and not block user-visible flows on it.
abstract class ActivityLogger {
  /// Record an activity of the given [type].
  ///
  /// The current wall-clock time is used as the event timestamp.
  Future<void> log(
    ActivityEventType type, {
    String? projectId,
    String? gameCode,
    Map<String, dynamic> payload = const {},
  });
}
