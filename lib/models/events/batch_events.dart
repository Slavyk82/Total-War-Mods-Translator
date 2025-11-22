import 'domain_event.dart';

/// Event emitted when a translation batch is started
class BatchStartedEvent extends DomainEvent {
  final String batchId;
  final String projectLanguageId;
  final String providerId;
  final int batchNumber;
  final int totalUnits;

  BatchStartedEvent({
    required this.batchId,
    required this.projectLanguageId,
    required this.providerId,
    required this.batchNumber,
    required this.totalUnits,
  }) : super.now();

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'projectLanguageId': projectLanguageId,
        'providerId': providerId,
        'batchNumber': batchNumber,
        'totalUnits': totalUnits,
      };

  @override
  String toString() =>
      'BatchStartedEvent(batchId: $batchId, number: $batchNumber, units: $totalUnits)';
}

/// Event emitted periodically during batch processing
class BatchProgressEvent extends DomainEvent {
  final String batchId;
  final int totalUnits;
  final int completedUnits;
  final int failedUnits;
  final double progressPercent;

  BatchProgressEvent({
    required this.batchId,
    required this.totalUnits,
    required this.completedUnits,
    required this.failedUnits,
  })  : progressPercent = totalUnits > 0 ? (completedUnits / totalUnits) * 100 : 0,
        super.now();

  int get remainingUnits => totalUnits - completedUnits - failedUnits;

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'totalUnits': totalUnits,
        'completedUnits': completedUnits,
        'failedUnits': failedUnits,
        'progressPercent': progressPercent,
      };

  @override
  String toString() =>
      'BatchProgressEvent(batchId: $batchId, progress: ${progressPercent.toStringAsFixed(1)}%, '
      'completed: $completedUnits/$totalUnits, failed: $failedUnits)';
}

/// Event emitted when a batch completes successfully
class BatchCompletedEvent extends DomainEvent {
  final String batchId;
  final String projectLanguageId;
  final int batchNumber;
  final int totalUnits;
  final int completedUnits;
  final int failedUnits;
  final Duration processingDuration;

  BatchCompletedEvent({
    required this.batchId,
    required this.projectLanguageId,
    required this.batchNumber,
    required this.totalUnits,
    required this.completedUnits,
    required this.failedUnits,
    required this.processingDuration,
  }) : super.now();

  bool get hasFailures => failedUnits > 0;
  double get successRate => totalUnits > 0 ? (completedUnits / totalUnits) * 100 : 0;

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'projectLanguageId': projectLanguageId,
        'batchNumber': batchNumber,
        'totalUnits': totalUnits,
        'completedUnits': completedUnits,
        'failedUnits': failedUnits,
        'processingDurationMs': processingDuration.inMilliseconds,
      };

  @override
  String toString() =>
      'BatchCompletedEvent(batchId: $batchId, success: ${successRate.toStringAsFixed(1)}%, '
      'duration: ${processingDuration.inSeconds}s)';
}

/// Event emitted when a batch fails
class BatchFailedEvent extends DomainEvent {
  final String batchId;
  final String projectLanguageId;
  final int batchNumber;
  final String errorMessage;
  final int completedBeforeFailure;
  final int totalUnits;
  final int retryCount;

  BatchFailedEvent({
    required this.batchId,
    required this.projectLanguageId,
    required this.batchNumber,
    required this.errorMessage,
    required this.completedBeforeFailure,
    required this.totalUnits,
    required this.retryCount,
  }) : super.now();

  bool get canRetry => retryCount < 3; // Max 3 retries

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'projectLanguageId': projectLanguageId,
        'batchNumber': batchNumber,
        'errorMessage': errorMessage,
        'completedBeforeFailure': completedBeforeFailure,
        'totalUnits': totalUnits,
        'retryCount': retryCount,
      };

  @override
  String toString() =>
      'BatchFailedEvent(batchId: $batchId, error: $errorMessage, '
      'completed: $completedBeforeFailure/$totalUnits, retries: $retryCount)';
}

/// Event emitted when a batch is paused by user
class BatchPausedEvent extends DomainEvent {
  final String batchId;
  final String projectLanguageId;
  final int completedUnits;
  final int totalUnits;

  BatchPausedEvent({
    required this.batchId,
    required this.projectLanguageId,
    required this.completedUnits,
    required this.totalUnits,
  }) : super.now();

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'projectLanguageId': projectLanguageId,
        'completedUnits': completedUnits,
        'totalUnits': totalUnits,
      };

  @override
  String toString() =>
      'BatchPausedEvent(batchId: $batchId, '
      'completed: $completedUnits/$totalUnits)';
}

/// Event emitted when a batch is resumed after pause
class BatchResumedEvent extends DomainEvent {
  final String batchId;
  final String projectLanguageId;
  final int completedUnits;
  final int totalUnits;

  BatchResumedEvent({
    required this.batchId,
    required this.projectLanguageId,
    required this.completedUnits,
    required this.totalUnits,
  }) : super.now();

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'projectLanguageId': projectLanguageId,
        'completedUnits': completedUnits,
        'totalUnits': totalUnits,
      };

  @override
  String toString() =>
      'BatchResumedEvent(batchId: $batchId, '
      'completed: $completedUnits/$totalUnits)';
}

/// Event emitted when a batch is cancelled by user
class BatchCancelledEvent extends DomainEvent {
  final String batchId;
  final String projectLanguageId;
  final int completedUnits;
  final int totalUnits;
  final String reason;

  BatchCancelledEvent({
    required this.batchId,
    required this.projectLanguageId,
    required this.completedUnits,
    required this.totalUnits,
    required this.reason,
  }) : super.now();

  int get completedBeforeCancellation => completedUnits;
  int get batchNumber => 0; // Default value, should be provided in real implementation

  @override
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'batchId': batchId,
        'projectLanguageId': projectLanguageId,
        'completedUnits': completedUnits,
        'totalUnits': totalUnits,
        'reason': reason,
      };

  @override
  String toString() =>
      'BatchCancelledEvent(batchId: $batchId, reason: $reason, '
      'completed: $completedUnits/$totalUnits)';
}
