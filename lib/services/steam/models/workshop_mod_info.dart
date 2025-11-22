import 'package:json_annotation/json_annotation.dart';

part 'workshop_mod_info.g.dart';

/// Information about a Steam Workshop mod
@JsonSerializable()
class WorkshopModInfo {
  /// Workshop item ID
  final String workshopId;

  /// Mod title
  final String title;

  /// Workshop item URL
  final String workshopUrl;

  /// File size in bytes
  final int? fileSize;

  /// Last update timestamp (Unix epoch)
  final int? timeUpdated;

  /// Creation timestamp (Unix epoch)
  final int? timeCreated;

  /// Number of subscribers
  final int? subscriptions;

  /// Tags/categories
  final List<String>? tags;

  /// Game app ID (e.g., 594570 for Total War: Warhammer II)
  final int appId;

  const WorkshopModInfo({
    required this.workshopId,
    required this.title,
    required this.workshopUrl,
    this.fileSize,
    this.timeUpdated,
    this.timeCreated,
    this.subscriptions,
    this.tags,
    required this.appId,
  });

  /// Convert from JSON
  factory WorkshopModInfo.fromJson(Map<String, dynamic> json) =>
      _$WorkshopModInfoFromJson(json);

  /// Convert to JSON
  Map<String, dynamic> toJson() => _$WorkshopModInfoToJson(this);

  /// Create a copy with updated fields
  WorkshopModInfo copyWith({
    String? workshopId,
    String? title,
    String? workshopUrl,
    int? fileSize,
    int? timeUpdated,
    int? timeCreated,
    int? subscriptions,
    List<String>? tags,
    int? appId,
  }) {
    return WorkshopModInfo(
      workshopId: workshopId ?? this.workshopId,
      title: title ?? this.title,
      workshopUrl: workshopUrl ?? this.workshopUrl,
      fileSize: fileSize ?? this.fileSize,
      timeUpdated: timeUpdated ?? this.timeUpdated,
      timeCreated: timeCreated ?? this.timeCreated,
      subscriptions: subscriptions ?? this.subscriptions,
      tags: tags ?? this.tags,
      appId: appId ?? this.appId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkshopModInfo &&
          runtimeType == other.runtimeType &&
          workshopId == other.workshopId &&
          title == other.title &&
          workshopUrl == other.workshopUrl &&
          fileSize == other.fileSize &&
          timeUpdated == other.timeUpdated &&
          timeCreated == other.timeCreated &&
          subscriptions == other.subscriptions &&
          appId == other.appId;

  @override
  int get hashCode => Object.hash(
        workshopId,
        title,
        workshopUrl,
        fileSize,
        timeUpdated,
        timeCreated,
        subscriptions,
        appId,
      );

  @override
  String toString() => 'WorkshopModInfo(id: $workshopId, title: $title, '
      'size: ${fileSize ?? 0} bytes)';
}
