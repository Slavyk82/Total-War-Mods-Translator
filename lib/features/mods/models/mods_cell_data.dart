import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_status.dart';

/// Data class for imported status cell
class ImportedData implements Comparable<ImportedData> {
  final bool isImported;

  const ImportedData({required this.isImported});

  @override
  int compareTo(ImportedData other) {
    // Sort imported items first (true = 0, false = 1)
    return (isImported ? 0 : 1).compareTo(other.isImported ? 0 : 1);
  }
}

/// Data class for last updated cell
class LastUpdatedData implements Comparable<LastUpdatedData> {
  final int? timeUpdated;
  final int? localFileLastModified;
  final ModUpdateStatus updateStatus;

  const LastUpdatedData({
    this.timeUpdated,
    this.localFileLastModified,
    this.updateStatus = ModUpdateStatus.unknown,
  });

  @override
  int compareTo(LastUpdatedData other) {
    // Sort by timeUpdated (most recent first), nulls last
    final thisTime = timeUpdated ?? 0;
    final otherTime = other.timeUpdated ?? 0;
    return otherTime.compareTo(thisTime);
  }
}

/// Data class for changes cell
class ChangesData implements Comparable<ChangesData> {
  final ModUpdateAnalysis? analysis;
  final ModUpdateStatus updateStatus;
  final String packFilePath;

  const ChangesData({
    this.analysis,
    this.updateStatus = ModUpdateStatus.unknown,
    required this.packFilePath,
  });

  @override
  int compareTo(ChangesData other) {
    // Sort by update status priority (hasChanges > needsDownload > upToDate > unknown)
    final statusPriority = {
      ModUpdateStatus.hasChanges: 0,
      ModUpdateStatus.needsDownload: 1,
      ModUpdateStatus.upToDate: 2,
      ModUpdateStatus.unknown: 3,
    };
    final thisPriority = statusPriority[updateStatus] ?? 3;
    final otherPriority = statusPriority[other.updateStatus] ?? 3;
    if (thisPriority != otherPriority) {
      return thisPriority.compareTo(otherPriority);
    }
    // If same status, sort by total changes count
    final thisCount = _getTotalChanges(analysis);
    final otherCount = _getTotalChanges(other.analysis);
    return otherCount.compareTo(thisCount);
  }

  int _getTotalChanges(ModUpdateAnalysis? analysis) {
    if (analysis == null) return 0;
    return analysis.newUnitsCount +
        analysis.removedUnitsCount +
        analysis.modifiedUnitsCount;
  }
}

/// Data class for hide cell
class HideData implements Comparable<HideData> {
  final String workshopId;
  final bool isHidden;

  const HideData({
    required this.workshopId,
    required this.isHidden,
  });

  @override
  int compareTo(HideData other) {
    // Sort hidden items first (true = 0, false = 1)
    return (isHidden ? 0 : 1).compareTo(other.isHidden ? 0 : 1);
  }
}
