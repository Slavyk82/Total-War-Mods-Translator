import 'package:json_annotation/json_annotation.dart';

part 'lock_info.g.dart';

/// Type of lock
enum LockType {
  /// Pessimistic lock for manual editing
  pessimistic,

  /// Batch reservation lock
  batchReservation,
}

/// Status of a lock
enum LockStatus {
  /// Lock is active
  active,

  /// Lock has expired (timeout)
  expired,

  /// Lock was released normally
  released,

  /// Lock was forcefully broken
  broken,
}

/// Information about a pessimistic lock on a translation entry
///
/// Used to prevent concurrent editing of the same entry by multiple users
/// or simultaneous manual editing and batch translation.
@JsonSerializable()
class LockInfo {
  /// Unique lock identifier
  final String id;

  /// Type of lock
  final LockType lockType;

  /// ID of the locked resource (translation_unit_id or translation_version_id)
  final String resourceId;

  /// Type of resource being locked (e.g., 'translation_unit', 'translation_version')
  final String resourceType;

  /// ID of the entity that acquired the lock (user_id, batch_id, etc.)
  final String ownerId;

  /// Type of owner (e.g., 'user', 'batch', 'system')
  final String ownerType;

  /// Lock status
  final LockStatus status;

  /// When the lock was acquired
  final DateTime acquiredAt;

  /// When the lock expires (for timeout management)
  final DateTime expiresAt;

  /// When the lock was released (if released)
  final DateTime? releasedAt;

  /// Reason for lock (optional, for debugging)
  final String? reason;

  /// Additional metadata (optional)
  final Map<String, dynamic>? metadata;

  const LockInfo({
    required this.id,
    required this.lockType,
    required this.resourceId,
    required this.resourceType,
    required this.ownerId,
    required this.ownerType,
    required this.status,
    required this.acquiredAt,
    required this.expiresAt,
    this.releasedAt,
    this.reason,
    this.metadata,
  });

  /// JSON serialization
  factory LockInfo.fromJson(Map<String, dynamic> json) =>
      _$LockInfoFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$LockInfoToJson(this);

  /// Check if lock is currently active (not expired or released)
  bool get isActive {
    if (status != LockStatus.active) return false;
    return DateTime.now().isBefore(expiresAt);
  }

  /// Check if lock has expired
  bool get isExpired {
    if (status == LockStatus.expired) return true;
    if (status != LockStatus.active) return false;
    return DateTime.now().isAfter(expiresAt);
  }

  /// Time remaining until lock expires
  Duration get timeRemaining {
    if (isExpired || status != LockStatus.active) {
      return Duration.zero;
    }
    return expiresAt.difference(DateTime.now());
  }

  /// Create copy with updated fields
  LockInfo copyWith({
    String? id,
    LockType? lockType,
    String? resourceId,
    String? resourceType,
    String? ownerId,
    String? ownerType,
    LockStatus? status,
    DateTime? acquiredAt,
    DateTime? expiresAt,
    DateTime? releasedAt,
    String? reason,
    Map<String, dynamic>? metadata,
  }) {
    return LockInfo(
      id: id ?? this.id,
      lockType: lockType ?? this.lockType,
      resourceId: resourceId ?? this.resourceId,
      resourceType: resourceType ?? this.resourceType,
      ownerId: ownerId ?? this.ownerId,
      ownerType: ownerType ?? this.ownerType,
      status: status ?? this.status,
      acquiredAt: acquiredAt ?? this.acquiredAt,
      expiresAt: expiresAt ?? this.expiresAt,
      releasedAt: releasedAt ?? this.releasedAt,
      reason: reason ?? this.reason,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          lockType == other.lockType &&
          resourceId == other.resourceId &&
          resourceType == other.resourceType &&
          ownerId == other.ownerId &&
          ownerType == other.ownerType &&
          status == other.status &&
          acquiredAt == other.acquiredAt &&
          expiresAt == other.expiresAt &&
          releasedAt == other.releasedAt &&
          reason == other.reason &&
          metadata == other.metadata;

  @override
  int get hashCode =>
      id.hashCode ^
      lockType.hashCode ^
      resourceId.hashCode ^
      resourceType.hashCode ^
      ownerId.hashCode ^
      ownerType.hashCode ^
      status.hashCode ^
      acquiredAt.hashCode ^
      expiresAt.hashCode ^
      releasedAt.hashCode ^
      reason.hashCode ^
      metadata.hashCode;

  @override
  String toString() {
    return 'LockInfo(id: $id, lockType: $lockType, resourceId: $resourceId, '
        'ownerId: $ownerId, status: $status, isActive: $isActive, '
        'timeRemaining: ${timeRemaining.inMinutes}min)';
  }
}

/// Request to acquire a lock
@JsonSerializable()
class LockRequest {
  /// ID of the resource to lock
  final String resourceId;

  /// Type of resource being locked
  final String resourceType;

  /// ID of the entity requesting the lock
  final String ownerId;

  /// Type of owner
  final String ownerType;

  /// Type of lock to acquire
  final LockType lockType;

  /// Lock timeout duration (default: 5 minutes)
  final Duration timeout;

  /// Reason for lock (optional)
  final String? reason;

  /// Force lock acquisition even if already locked
  final bool force;

  const LockRequest({
    required this.resourceId,
    required this.resourceType,
    required this.ownerId,
    required this.ownerType,
    this.lockType = LockType.pessimistic,
    this.timeout = const Duration(minutes: 5),
    this.reason,
    this.force = false,
  });

  /// JSON serialization
  factory LockRequest.fromJson(Map<String, dynamic> json) =>
      _$LockRequestFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$LockRequestToJson(this);

  @override
  String toString() {
    return 'LockRequest(resourceId: $resourceId, ownerId: $ownerId, '
        'lockType: $lockType, timeout: ${timeout.inMinutes}min)';
  }
}

/// Batch reservation information
///
/// Used to reserve translation units for batch processing to prevent
/// duplicate processing by concurrent batches.
@JsonSerializable()
class BatchReservation {
  /// Unique reservation identifier
  final String id;

  /// Batch ID that reserved the units
  final String batchId;

  /// Translation unit ID
  final String translationUnitId;

  /// Language code being translated
  final String languageCode;

  /// When the reservation was made
  final DateTime reservedAt;

  /// When the reservation expires
  final DateTime expiresAt;

  /// Reservation status
  final String status;

  const BatchReservation({
    required this.id,
    required this.batchId,
    required this.translationUnitId,
    required this.languageCode,
    required this.reservedAt,
    required this.expiresAt,
    required this.status,
  });

  /// JSON serialization
  factory BatchReservation.fromJson(Map<String, dynamic> json) =>
      _$BatchReservationFromJson(json);

  /// JSON deserialization
  Map<String, dynamic> toJson() => _$BatchReservationToJson(this);

  /// Check if reservation is still active
  bool get isActive {
    return status == 'active' && DateTime.now().isBefore(expiresAt);
  }

  /// Create copy with updated fields
  BatchReservation copyWith({
    String? id,
    String? batchId,
    String? translationUnitId,
    String? languageCode,
    DateTime? reservedAt,
    DateTime? expiresAt,
    String? status,
  }) {
    return BatchReservation(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      translationUnitId: translationUnitId ?? this.translationUnitId,
      languageCode: languageCode ?? this.languageCode,
      reservedAt: reservedAt ?? this.reservedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchReservation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          batchId == other.batchId &&
          translationUnitId == other.translationUnitId &&
          languageCode == other.languageCode &&
          reservedAt == other.reservedAt &&
          expiresAt == other.expiresAt &&
          status == other.status;

  @override
  int get hashCode =>
      id.hashCode ^
      batchId.hashCode ^
      translationUnitId.hashCode ^
      languageCode.hashCode ^
      reservedAt.hashCode ^
      expiresAt.hashCode ^
      status.hashCode;

  @override
  String toString() {
    return 'BatchReservation(id: $id, batchId: $batchId, '
        'translationUnitId: $translationUnitId, languageCode: $languageCode, '
        'isActive: $isActive)';
  }
}
