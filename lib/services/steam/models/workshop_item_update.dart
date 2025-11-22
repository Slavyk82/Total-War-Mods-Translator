/// Represents an update status for a Workshop item.
///
/// Compares the last known update time with the latest update time
/// from Steam Workshop to determine if an update is available.
class WorkshopItemUpdate {
  /// Workshop item ID
  final String workshopId;

  /// Mod name
  final String modName;

  /// Last known update timestamp from local database
  final DateTime lastKnownUpdate;

  /// Latest update timestamp from Steam Workshop
  final DateTime latestUpdate;

  /// Whether an update is available
  final bool hasUpdate;

  const WorkshopItemUpdate({
    required this.workshopId,
    required this.modName,
    required this.lastKnownUpdate,
    required this.latestUpdate,
    required this.hasUpdate,
  });

  /// Calculate if update is available by comparing timestamps
  factory WorkshopItemUpdate.fromTimestamps({
    required String workshopId,
    required String modName,
    required DateTime lastKnownUpdate,
    required DateTime latestUpdate,
  }) {
    return WorkshopItemUpdate(
      workshopId: workshopId,
      modName: modName,
      lastKnownUpdate: lastKnownUpdate,
      latestUpdate: latestUpdate,
      hasUpdate: latestUpdate.isAfter(lastKnownUpdate),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkshopItemUpdate &&
          runtimeType == other.runtimeType &&
          workshopId == other.workshopId &&
          modName == other.modName &&
          lastKnownUpdate == other.lastKnownUpdate &&
          latestUpdate == other.latestUpdate &&
          hasUpdate == other.hasUpdate;

  @override
  int get hashCode => Object.hash(
        workshopId,
        modName,
        lastKnownUpdate,
        latestUpdate,
        hasUpdate,
      );

  @override
  String toString() => 'WorkshopItemUpdate(id: $workshopId, '
      'name: $modName, hasUpdate: $hasUpdate)';
}
