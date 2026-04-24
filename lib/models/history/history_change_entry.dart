/// Input payload for a single history entry in a batch record.
///
/// Used by [IHistoryService.recordChangesBatch] to keep the method signature
/// stable while bundling many entries into one transaction.
class HistoryChangeEntry {
  final String versionId;
  final String translatedText;
  final String status;
  final String changedBy;
  final String? changeReason;

  const HistoryChangeEntry({
    required this.versionId,
    required this.translatedText,
    required this.status,
    required this.changedBy,
    this.changeReason,
  });
}
