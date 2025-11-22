import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../models/common/result.dart';
import '../database/database_service.dart';
import 'models/notification.dart' as models;
import 'logging_service.dart';

/// Service for managing user notifications
///
/// Provides:
/// - Toast notifications (temporary, bottom-right)
/// - Dialog notifications (modal, requires user action)
/// - Persistent notifications (notification center)
/// - Notification queue management
/// - Action callbacks
///
/// Example:
/// ```dart
/// final service = NotificationService.instance;
///
/// // Show toast
/// service.showToast(
///   title: 'File Saved',
///   message: 'Translation file saved successfully',
///   severity: NotificationSeverity.success,
/// );
///
/// // Show dialog
/// await service.showDialog(
///   title: 'Confirm Delete',
///   message: 'Are you sure you want to delete this project?',
///   severity: NotificationSeverity.warning,
///   actionText: 'Delete',
///   actionId: 'delete_project_123',
/// );
/// ```
class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  final Uuid _uuid = const Uuid();

  /// Stream controller for notifications
  final StreamController<models.Notification> _notificationController =
      StreamController<models.Notification>.broadcast();

  /// Stream controller for action callbacks
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  /// Maximum notifications in queue
  static const int maxQueueSize = 100;

  /// Maximum persistent notifications to keep
  static const int maxPersistent = 500;

  Database get _db => DatabaseService.database;

  /// Stream of notifications to display
  Stream<models.Notification> get notifications => _notificationController.stream;

  /// Stream of action button clicks (emits actionId)
  Stream<String> get actionClicks => _actionController.stream;

  /// Show a toast notification
  ///
  /// Toast notifications appear in the bottom-right corner
  /// and auto-dismiss after a short duration (default: 4 seconds).
  ///
  /// Parameters:
  /// - [title]: Notification title
  /// - [message]: Notification message
  /// - [severity]: Severity level (info, success, warning, error)
  /// - [autoDismiss]: Auto-dismiss duration (default: 4 seconds)
  /// - [iconName]: Optional icon from FluentIcons
  ///
  /// Returns notification ID
  String showToast({
    required String title,
    required String message,
    models.NotificationSeverity severity = models.NotificationSeverity.info,
    Duration? autoDismiss,
    String? iconName,
  }) {
    final notification = models.Notification(
      id: _uuid.v4(),
      title: title,
      message: message,
      severity: severity,
      type: models.NotificationType.toast,
      createdAt: DateTime.now(),
      autoDismiss: autoDismiss ?? const Duration(seconds: 4),
      dismissible: true,
      iconName: iconName ?? _getDefaultIcon(severity),
    );

    _notificationController.add(notification);

    return notification.id;
  }

  /// Show a dialog notification
  ///
  /// Dialog notifications are modal and require user interaction.
  /// They block the UI until dismissed or acted upon.
  ///
  /// Parameters:
  /// - [title]: Dialog title
  /// - [message]: Dialog message
  /// - [severity]: Severity level
  /// - [actionText]: Optional action button text
  /// - [actionId]: Optional action callback identifier
  /// - [dismissText]: Dismiss button text (default: "OK")
  /// - [dismissible]: Whether user can dismiss (default: true)
  ///
  /// Returns notification ID
  Future<String> showDialog({
    required String title,
    required String message,
    models.NotificationSeverity severity = models.NotificationSeverity.info,
    String? actionText,
    String? actionId,
    String? dismissText,
    bool dismissible = true,
  }) async {
    final notification = models.Notification(
      id: _uuid.v4(),
      title: title,
      message: message,
      severity: severity,
      type: models.NotificationType.dialog,
      createdAt: DateTime.now(),
      actionText: actionText,
      actionId: actionId,
      dismissText: dismissText ?? 'OK',
      dismissible: dismissible,
      iconName: _getDefaultIcon(severity),
    );

    _notificationController.add(notification);

    // Store in database for persistence
    await _persistNotification(notification);

    return notification.id;
  }

  /// Create a persistent notification
  ///
  /// Persistent notifications stay in the notification center
  /// until explicitly dismissed by the user.
  ///
  /// Parameters:
  /// - [title]: Notification title
  /// - [message]: Notification message
  /// - [severity]: Severity level
  /// - [actionText]: Optional action button text
  /// - [actionId]: Optional action callback identifier
  ///
  /// Returns notification ID
  Future<String> createPersistent({
    required String title,
    required String message,
    models.NotificationSeverity severity = models.NotificationSeverity.info,
    String? actionText,
    String? actionId,
    Map<String, dynamic>? metadata,
  }) async {
    final notification = models.Notification(
      id: _uuid.v4(),
      title: title,
      message: message,
      severity: severity,
      type: models.NotificationType.persistent,
      createdAt: DateTime.now(),
      actionText: actionText,
      actionId: actionId,
      dismissible: true,
      iconName: _getDefaultIcon(severity),
      metadata: metadata,
    );

    _notificationController.add(notification);

    // Store in database
    await _persistNotification(notification);

    // Cleanup old notifications if limit exceeded
    await _cleanupOldNotifications();

    return notification.id;
  }

  /// Trigger an action callback
  ///
  /// Called when user clicks an action button.
  /// Emits the actionId via the actionClicks stream.
  void triggerAction(String actionId) {
    _actionController.add(actionId);
  }

  /// Dismiss a notification
  ///
  /// Marks the notification as read in the database.
  Future<Result<bool, Exception>> dismiss(String notificationId) async {
    try {
      final count = await _db.update(
        'notifications',
        {'is_read': 1},
        where: 'id = ?',
        whereArgs: [notificationId],
      );

      return Ok(count > 0);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to dismiss notification: ${e.toString()}'));
    }
  }

  /// Get all persistent notifications
  ///
  /// Parameters:
  /// - [includeRead]: Include read notifications (default: false)
  /// - [limit]: Maximum results (default: 50)
  ///
  /// Returns list of notifications ordered by creation time (newest first)
  Future<Result<List<models.Notification>, Exception>> getNotifications({
    bool includeRead = false,
    int limit = 50,
  }) async {
    try {
      final results = await _db.query(
        'notifications',
        where: includeRead ? null : 'is_read = 0',
        orderBy: 'created_at DESC',
        limit: limit,
      );

      final notifications = results.map(_parseNotification).toList();
      return Ok(notifications);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to get notifications: ${e.toString()}'));
    }
  }

  /// Get unread notification count
  Future<Result<int, Exception>> getUnreadCount() async {
    try {
      final results = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM notifications WHERE is_read = 0',
      );

      final count = results.first['count'] as int;
      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to get unread count: ${e.toString()}'));
    }
  }

  /// Mark all notifications as read
  Future<Result<int, Exception>> markAllAsRead() async {
    try {
      final count = await _db.update(
        'notifications',
        {'is_read': 1},
        where: 'is_read = 0',
      );

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to mark all as read: ${e.toString()}'));
    }
  }

  /// Delete a notification
  Future<Result<bool, Exception>> delete(String notificationId) async {
    try {
      final count = await _db.delete(
        'notifications',
        where: 'id = ?',
        whereArgs: [notificationId],
      );

      return Ok(count > 0);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to delete notification: ${e.toString()}'));
    }
  }

  /// Delete all read notifications
  Future<Result<int, Exception>> deleteAllRead() async {
    try {
      final count = await _db.delete(
        'notifications',
        where: 'is_read = 1',
      );

      return Ok(count);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to delete read notifications: ${e.toString()}'));
    }
  }

  /// Get notification statistics
  Future<Result<models.NotificationStatistics, Exception>> getStatistics() async {
    try {
      // Total
      final totalResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM notifications',
      );
      final total = totalResult.first['count'] as int;

      // Unread
      final unreadResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM notifications WHERE is_read = 0',
      );
      final unread = unreadResult.first['count'] as int;

      // By severity
      final severityResult = await _db.rawQuery('''
        SELECT severity, COUNT(*) as count
        FROM notifications
        GROUP BY severity
      ''');
      final bySeverity = <String, int>{};
      for (final row in severityResult) {
        bySeverity[row['severity'] as String] = row['count'] as int;
      }

      // By type
      final typeResult = await _db.rawQuery('''
        SELECT type, COUNT(*) as count
        FROM notifications
        GROUP BY type
      ''');
      final byType = <String, int>{};
      for (final row in typeResult) {
        byType[row['type'] as String] = row['count'] as int;
      }

      // Recent (last 24h)
      final dayAgo = DateTime.now().subtract(const Duration(days: 1));
      final recentResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM notifications WHERE created_at >= ?',
        [dayAgo.millisecondsSinceEpoch],
      );
      final recent = recentResult.first['count'] as int;

      final stats = models.NotificationStatistics(
        total: total,
        unread: unread,
        bySeverity: bySeverity,
        byType: byType,
        recent: recent,
      );

      return Ok(stats);
    } on DatabaseException catch (e) {
      return Err(Exception('Failed to get statistics: ${e.toString()}'));
    }
  }

  /// Show a notification (generic method)
  ///
  /// This is a convenience wrapper that shows a toast notification.
  /// For more control, use showToast(), showDialog(), or createPersistent().
  String show({
    required String message,
    required models.NotificationType type,
    Duration? duration,
    String? details,
  }) {
    // Map NotificationType to NotificationSeverity
    final severity = _severityFromType(type);

    return showToast(
      title: _titleFromType(type),
      message: message,
      severity: severity,
      autoDismiss: duration,
    );
  }

  models.NotificationSeverity _severityFromType(models.NotificationType type) {
    return switch (type) {
      models.NotificationType.success => models.NotificationSeverity.success,
      models.NotificationType.error => models.NotificationSeverity.error,
      models.NotificationType.warning => models.NotificationSeverity.warning,
      models.NotificationType.info ||
      models.NotificationType.toast ||
      models.NotificationType.dialog ||
      models.NotificationType.persistent => models.NotificationSeverity.info,
    };
  }

  String _titleFromType(models.NotificationType type) {
    return switch (type) {
      models.NotificationType.success => 'Success',
      models.NotificationType.error => 'Error',
      models.NotificationType.warning => 'Warning',
      models.NotificationType.info => 'Info',
      models.NotificationType.toast ||
      models.NotificationType.dialog ||
      models.NotificationType.persistent => 'Notification',
    };
  }

  /// Convenience methods for common notification types

  /// Show success toast
  String showSuccess(String title, String message) {
    return showToast(
      title: title,
      message: message,
      severity: models.NotificationSeverity.success,
    );
  }

  /// Show error toast
  String showError(String title, String message) {
    return showToast(
      title: title,
      message: message,
      severity: models.NotificationSeverity.error,
      autoDismiss: const Duration(seconds: 6), // Longer for errors
    );
  }

  /// Show warning toast
  String showWarning(String title, String message) {
    return showToast(
      title: title,
      message: message,
      severity: models.NotificationSeverity.warning,
      autoDismiss: const Duration(seconds: 5),
    );
  }

  /// Show info toast
  String showInfo(String title, String message) {
    return showToast(
      title: title,
      message: message,
      severity: models.NotificationSeverity.info,
    );
  }

  // Private helper methods

  Future<void> _persistNotification(models.Notification notification) async {
    try {
      await _db.insert('notifications', {
        'id': notification.id,
        'title': notification.title,
        'message': notification.message,
        'severity': notification.severity.name,
        'type': notification.type.name,
        'created_at': notification.createdAt.millisecondsSinceEpoch,
        'action_text': notification.actionText,
        'action_id': notification.actionId,
        'dismiss_text': notification.dismissText,
        'is_read': notification.isRead ? 1 : 0,
        'icon_name': notification.iconName,
      });
    } catch (e, stackTrace) {
      // Don't throw - notification persistence failure shouldn't break the app
      LoggingService.instance.error('Failed to persist notification', e, stackTrace);
    }
  }

  Future<void> _cleanupOldNotifications() async {
    try {
      // Get current count
      final countResult = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM notifications',
      );
      final count = countResult.first['count'] as int;

      if (count > maxPersistent) {
        // Delete oldest read notifications
        final toDelete = count - maxPersistent;

        await _db.rawDelete('''
          DELETE FROM notifications
          WHERE id IN (
            SELECT id FROM notifications
            WHERE is_read = 1
            ORDER BY created_at ASC
            LIMIT ?
          )
        ''', [toDelete]);
      }
    } catch (e, stackTrace) {
      LoggingService.instance.error('Failed to cleanup notifications', e, stackTrace);
    }
  }

  String _getDefaultIcon(models.NotificationSeverity severity) {
    return switch (severity) {
      models.NotificationSeverity.info => 'info_24_regular',
      models.NotificationSeverity.success => 'checkmark_circle_24_regular',
      models.NotificationSeverity.warning => 'warning_24_regular',
      models.NotificationSeverity.error => 'error_circle_24_regular',
    };
  }

  models.Notification _parseNotification(Map<String, dynamic> row) {
    return models.Notification(
      id: row['id'] as String,
      title: row['title'] as String,
      message: row['message'] as String,
      severity: models.NotificationSeverity.values.firstWhere(
        (s) => s.name == row['severity'],
      ),
      type: models.NotificationType.values.firstWhere(
        (t) => t.name == row['type'],
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      actionText: row['action_text'] as String?,
      actionId: row['action_id'] as String?,
      dismissText: row['dismiss_text'] as String?,
      isRead: (row['is_read'] as int) == 1,
      iconName: row['icon_name'] as String?,
    );
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _notificationController.close();
    await _actionController.close();
  }
}
