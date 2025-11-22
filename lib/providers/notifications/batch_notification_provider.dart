import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../services/shared/notification_service.dart';
import '../../services/shared/models/notification.dart';
import '../../services/service_locator.dart';
import '../../models/events/batch_events.dart';
import '../events/event_stream_providers.dart';

part 'batch_notification_provider.g.dart';

/// Listens to batch events and triggers appropriate notifications
///
/// This provider handles side effects (notifications) separately from state management.
/// It's kept alive for the entire app lifecycle to ensure notifications work globally.
@Riverpod(keepAlive: true)
class BatchNotifications extends _$BatchNotifications {
  NotificationService get _notificationService =>
      ServiceLocator.get<NotificationService>();

  /// Processed event IDs to prevent duplicate notifications
  final Set<String> _processedEvents = {};

  @override
  void build() {
    // Listen to batch completion events
    ref.listen(
      batchCompletedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          if (!_wasProcessed(event.eventId)) {
            _showCompletionNotification(event);
            _markProcessed(event.eventId);
          }
        }
      },
    );

    // Listen to batch failure events
    ref.listen(
      batchFailedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          if (!_wasProcessed(event.eventId)) {
            _showFailureNotification(event);
            _markProcessed(event.eventId);
          }
        }
      },
    );

    // Listen to batch cancelled events
    ref.listen(
      batchCancelledEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          if (!_wasProcessed(event.eventId)) {
            _showCancelledNotification(event);
            _markProcessed(event.eventId);
          }
        }
      },
    );
  }

  void _showCompletionNotification(BatchCompletedEvent event) {
    final successRate = event.successRate.toStringAsFixed(1);
    final hasFailures = event.failedUnits > 0;

    final message = hasFailures
        ? 'Batch ${event.batchNumber} completed: ${event.completedUnits}/${event.totalUnits} units translated ($successRate% success)'
        : 'Batch ${event.batchNumber} completed successfully: ${event.completedUnits} units translated';

    final notificationType = hasFailures
        ? NotificationType.warning
        : NotificationType.success;

    _notificationService.show(
      message: message,
      type: notificationType,
      duration: const Duration(seconds: 5),
    );
  }

  void _showFailureNotification(BatchFailedEvent event) {
    final message = event.completedBeforeFailure > 0
        ? 'Batch ${event.batchNumber} failed after translating ${event.completedBeforeFailure}/${event.totalUnits} units'
        : 'Batch ${event.batchNumber} failed: ${event.errorMessage}';

    _notificationService.show(
      message: message,
      type: NotificationType.error,
      duration: const Duration(seconds: 8),
      details: event.errorMessage,
    );
  }

  void _showCancelledNotification(BatchCancelledEvent event) {
    final message = event.completedBeforeCancellation > 0
        ? 'Batch ${event.batchNumber} cancelled after translating ${event.completedBeforeCancellation} units'
        : 'Batch ${event.batchNumber} cancelled';

    _notificationService.show(
      message: message,
      type: NotificationType.info,
      duration: const Duration(seconds: 4),
    );
  }

  bool _wasProcessed(String eventId) {
    return _processedEvents.contains(eventId);
  }

  void _markProcessed(String eventId) {
    _processedEvents.add(eventId);

    // Clean up old event IDs after 1 minute to prevent memory growth
    Future.delayed(const Duration(minutes: 1), () {
      _processedEvents.remove(eventId);
    });
  }
}
