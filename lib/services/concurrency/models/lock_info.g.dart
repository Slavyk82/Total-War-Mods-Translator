// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lock_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LockInfo _$LockInfoFromJson(Map<String, dynamic> json) => LockInfo(
  id: json['id'] as String,
  lockType: $enumDecode(_$LockTypeEnumMap, json['lockType']),
  resourceId: json['resourceId'] as String,
  resourceType: json['resourceType'] as String,
  ownerId: json['ownerId'] as String,
  ownerType: json['ownerType'] as String,
  status: $enumDecode(_$LockStatusEnumMap, json['status']),
  acquiredAt: DateTime.parse(json['acquiredAt'] as String),
  expiresAt: DateTime.parse(json['expiresAt'] as String),
  releasedAt: json['releasedAt'] == null
      ? null
      : DateTime.parse(json['releasedAt'] as String),
  reason: json['reason'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$LockInfoToJson(LockInfo instance) => <String, dynamic>{
  'id': instance.id,
  'lockType': _$LockTypeEnumMap[instance.lockType]!,
  'resourceId': instance.resourceId,
  'resourceType': instance.resourceType,
  'ownerId': instance.ownerId,
  'ownerType': instance.ownerType,
  'status': _$LockStatusEnumMap[instance.status]!,
  'acquiredAt': instance.acquiredAt.toIso8601String(),
  'expiresAt': instance.expiresAt.toIso8601String(),
  'releasedAt': instance.releasedAt?.toIso8601String(),
  'reason': instance.reason,
  'metadata': instance.metadata,
};

const _$LockTypeEnumMap = {
  LockType.pessimistic: 'pessimistic',
  LockType.batchReservation: 'batchReservation',
};

const _$LockStatusEnumMap = {
  LockStatus.active: 'active',
  LockStatus.expired: 'expired',
  LockStatus.released: 'released',
  LockStatus.broken: 'broken',
};

LockRequest _$LockRequestFromJson(Map<String, dynamic> json) => LockRequest(
  resourceId: json['resourceId'] as String,
  resourceType: json['resourceType'] as String,
  ownerId: json['ownerId'] as String,
  ownerType: json['ownerType'] as String,
  lockType:
      $enumDecodeNullable(_$LockTypeEnumMap, json['lockType']) ??
      LockType.pessimistic,
  timeout: json['timeout'] == null
      ? const Duration(minutes: 5)
      : Duration(microseconds: (json['timeout'] as num).toInt()),
  reason: json['reason'] as String?,
  force: json['force'] as bool? ?? false,
);

Map<String, dynamic> _$LockRequestToJson(LockRequest instance) =>
    <String, dynamic>{
      'resourceId': instance.resourceId,
      'resourceType': instance.resourceType,
      'ownerId': instance.ownerId,
      'ownerType': instance.ownerType,
      'lockType': _$LockTypeEnumMap[instance.lockType]!,
      'timeout': instance.timeout.inMicroseconds,
      'reason': instance.reason,
      'force': instance.force,
    };

BatchReservation _$BatchReservationFromJson(Map<String, dynamic> json) =>
    BatchReservation(
      id: json['id'] as String,
      batchId: json['batchId'] as String,
      translationUnitId: json['translationUnitId'] as String,
      languageCode: json['languageCode'] as String,
      reservedAt: DateTime.parse(json['reservedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      status: json['status'] as String,
    );

Map<String, dynamic> _$BatchReservationToJson(BatchReservation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'batchId': instance.batchId,
      'translationUnitId': instance.translationUnitId,
      'languageCode': instance.languageCode,
      'reservedAt': instance.reservedAt.toIso8601String(),
      'expiresAt': instance.expiresAt.toIso8601String(),
      'status': instance.status,
    };
