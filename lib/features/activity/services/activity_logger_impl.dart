import '../../../services/service_locator.dart';
import '../../../services/shared/i_logging_service.dart';
import '../models/activity_event.dart';
import '../repositories/activity_event_repository.dart';
import 'activity_logger.dart';

/// Default [ActivityLogger] implementation backed by an
/// [ActivityEventRepository].
///
/// Fire-and-forget semantics: any `Err` returned by the repository and
/// any exception thrown (synchronously or asynchronously) are caught
/// and forwarded to the injected [ILoggingService]. `log` always
/// completes normally.
class ActivityLoggerImpl implements ActivityLogger {
  final ActivityEventRepository _repository;
  final ILoggingService _logger;

  ActivityLoggerImpl({
    required ActivityEventRepository repository,
    ILoggingService? logger,
  })  : _repository = repository,
        _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  Future<void> log(
    ActivityEventType type, {
    String? projectId,
    String? gameCode,
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      final event = ActivityEvent(
        id: 0,
        type: type,
        timestamp: DateTime.now(),
        projectId: projectId,
        gameCode: gameCode,
        payload: payload,
      );
      final result = await _repository.insert(event);
      if (result.isErr) {
        _logger.error(
          'ActivityLogger: failed to persist event',
          result.error,
          StackTrace.current,
        );
      }
    } catch (e, st) {
      // Swallow everything: activity logging must never break the caller.
      _logger.error('ActivityLogger: unexpected error', e, st);
    }
  }
}
