import 'package:json_annotation/json_annotation.dart';

part 'notification.g.dart';

/// Notification severity level
enum NotificationSeverity {
  /// Informational message
  info,

  /// Success message (green)
  success,

  /// Warning message (yellow/orange)
  warning,

  /// Error message (red)
  error,
}

/// Notification type
enum NotificationType {
  /// Toast notification (temporary, bottom-right)
  toast,

  /// Dialog notification (requires user action)
  dialog,

  /// Persistent notification (stays in notification center)
  persistent,

  /// Success notification (convenience, maps to success toast)
  success,

  /// Error notification (convenience, maps to error toast)
  error,

  /// Warning notification (convenience, maps to warning toast)
  warning,

  /// Info notification (convenience, maps to info toast)
  info,
}

/// A notification to display to the user
@JsonSerializable()
class Notification {
  /// Unique notification ID
  final String id;

  /// Notification title
  final String title;

  /// Notification message body
  final String message;

  /// Severity level
  final NotificationSeverity severity;

  /// Notification type
  final NotificationType type;

  /// When the notification was created
  final DateTime createdAt;

  /// Optional action button text
  final String? actionText;

  /// Optional action callback identifier
  final String? actionId;

  /// Optional dismiss button text (default: "Dismiss")
  final String? dismissText;

  /// Auto-dismiss duration (null = no auto-dismiss)
  final Duration? autoDismiss;

  /// Whether notification can be dismissed by user
  final bool dismissible;

  /// Whether notification has been read
  final bool isRead;

  /// Optional icon name (from FluentIcons)
  final String? iconName;

  /// Optional metadata
  final Map<String, dynamic>? metadata;

  const Notification({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.type,
    required this.createdAt,
    this.actionText,
    this.actionId,
    this.dismissText,
    this.autoDismiss,
    this.dismissible = true,
    this.isRead = false,
    this.iconName,
    this.metadata,
  });

  factory Notification.fromJson(Map<String, dynamic> json) =>
      _$NotificationFromJson(json);

  Map<String, dynamic> toJson() => _$NotificationToJson(this);

  Notification copyWith({
    String? id,
    String? title,
    String? message,
    NotificationSeverity? severity,
    NotificationType? type,
    DateTime? createdAt,
    String? actionText,
    String? actionId,
    String? dismissText,
    Duration? autoDismiss,
    bool? dismissible,
    bool? isRead,
    String? iconName,
    Map<String, dynamic>? metadata,
  }) {
    return Notification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      actionText: actionText ?? this.actionText,
      actionId: actionId ?? this.actionId,
      dismissText: dismissText ?? this.dismissText,
      autoDismiss: autoDismiss ?? this.autoDismiss,
      dismissible: dismissible ?? this.dismissible,
      isRead: isRead ?? this.isRead,
      iconName: iconName ?? this.iconName,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Notification && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Notification(id: $id, title: $title, severity: $severity, type: $type)';
  }
}

/// Notification statistics
@JsonSerializable()
class NotificationStatistics {
  /// Total notifications
  final int total;

  /// Unread notifications
  final int unread;

  /// Notifications by severity
  final Map<String, int> bySeverity;

  /// Notifications by type
  final Map<String, int> byType;

  /// Recent notification count (last 24h)
  final int recent;

  const NotificationStatistics({
    required this.total,
    required this.unread,
    required this.bySeverity,
    required this.byType,
    required this.recent,
  });

  factory NotificationStatistics.fromJson(Map<String, dynamic> json) =>
      _$NotificationStatisticsFromJson(json);

  Map<String, dynamic> toJson() => _$NotificationStatisticsToJson(this);
}
