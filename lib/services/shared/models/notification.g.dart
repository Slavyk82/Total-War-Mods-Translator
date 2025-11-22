// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Notification _$NotificationFromJson(Map<String, dynamic> json) => Notification(
  id: json['id'] as String,
  title: json['title'] as String,
  message: json['message'] as String,
  severity: $enumDecode(_$NotificationSeverityEnumMap, json['severity']),
  type: $enumDecode(_$NotificationTypeEnumMap, json['type']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  actionText: json['actionText'] as String?,
  actionId: json['actionId'] as String?,
  dismissText: json['dismissText'] as String?,
  autoDismiss: json['autoDismiss'] == null
      ? null
      : Duration(microseconds: (json['autoDismiss'] as num).toInt()),
  dismissible: json['dismissible'] as bool? ?? true,
  isRead: json['isRead'] as bool? ?? false,
  iconName: json['iconName'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$NotificationToJson(Notification instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'message': instance.message,
      'severity': _$NotificationSeverityEnumMap[instance.severity]!,
      'type': _$NotificationTypeEnumMap[instance.type]!,
      'createdAt': instance.createdAt.toIso8601String(),
      'actionText': instance.actionText,
      'actionId': instance.actionId,
      'dismissText': instance.dismissText,
      'autoDismiss': instance.autoDismiss?.inMicroseconds,
      'dismissible': instance.dismissible,
      'isRead': instance.isRead,
      'iconName': instance.iconName,
      'metadata': instance.metadata,
    };

const _$NotificationSeverityEnumMap = {
  NotificationSeverity.info: 'info',
  NotificationSeverity.success: 'success',
  NotificationSeverity.warning: 'warning',
  NotificationSeverity.error: 'error',
};

const _$NotificationTypeEnumMap = {
  NotificationType.toast: 'toast',
  NotificationType.dialog: 'dialog',
  NotificationType.persistent: 'persistent',
  NotificationType.success: 'success',
  NotificationType.error: 'error',
  NotificationType.warning: 'warning',
  NotificationType.info: 'info',
};

NotificationStatistics _$NotificationStatisticsFromJson(
  Map<String, dynamic> json,
) => NotificationStatistics(
  total: (json['total'] as num).toInt(),
  unread: (json['unread'] as num).toInt(),
  bySeverity: Map<String, int>.from(json['bySeverity'] as Map),
  byType: Map<String, int>.from(json['byType'] as Map),
  recent: (json['recent'] as num).toInt(),
);

Map<String, dynamic> _$NotificationStatisticsToJson(
  NotificationStatistics instance,
) => <String, dynamic>{
  'total': instance.total,
  'unread': instance.unread,
  'bySeverity': instance.bySeverity,
  'byType': instance.byType,
  'recent': instance.recent,
};
