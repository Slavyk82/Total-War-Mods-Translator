/// Result of a successful Workshop publish/update operation
class WorkshopPublishResult {
  /// The Workshop item ID (new or existing)
  final String workshopId;

  /// Whether this was an update to an existing item
  final bool wasUpdate;

  /// Duration of the publish operation in milliseconds
  final int durationMs;

  /// Timestamp of the operation
  final DateTime timestamp;

  /// Raw steamcmd output for debugging
  final String rawOutput;

  const WorkshopPublishResult({
    required this.workshopId,
    required this.wasUpdate,
    required this.durationMs,
    required this.timestamp,
    required this.rawOutput,
  });
}
