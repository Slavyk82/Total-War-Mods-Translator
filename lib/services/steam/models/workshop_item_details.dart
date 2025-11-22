/// Detailed information about a Steam Workshop item.
///
/// Contains metadata returned from Steam Web API's GetPublishedFileDetails endpoint.
class WorkshopItemDetails {
  /// Published file ID (Workshop ID)
  final String publishedFileId;

  /// Item title
  final String title;

  /// Last update timestamp (Unix epoch)
  final DateTime timeUpdated;

  /// File size in bytes
  final int fileSize;

  /// Creation timestamp (Unix epoch)
  final DateTime? timeCreated;

  /// Number of subscribers
  final int? subscriptions;

  /// Tags/categories
  final List<String>? tags;

  const WorkshopItemDetails({
    required this.publishedFileId,
    required this.title,
    required this.timeUpdated,
    required this.fileSize,
    this.timeCreated,
    this.subscriptions,
    this.tags,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkshopItemDetails &&
          runtimeType == other.runtimeType &&
          publishedFileId == other.publishedFileId &&
          title == other.title &&
          timeUpdated == other.timeUpdated &&
          fileSize == other.fileSize &&
          timeCreated == other.timeCreated &&
          subscriptions == other.subscriptions;

  @override
  int get hashCode => Object.hash(
        publishedFileId,
        title,
        timeUpdated,
        fileSize,
        timeCreated,
        subscriptions,
      );

  @override
  String toString() => 'WorkshopItemDetails(id: $publishedFileId, '
      'title: $title, updated: $timeUpdated, size: $fileSize bytes)';
}
