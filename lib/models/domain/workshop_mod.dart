import 'dart:convert';

/// Domain model for Steam Workshop mod metadata
///
/// Stores complete Workshop item information retrieved from Steam Web API
class WorkshopMod {
  /// Internal UUID
  final String id;

  /// Steam Workshop item ID
  final String workshopId;

  /// Mod title
  final String title;

  /// Steam app ID (e.g., 594570 for Total War: Warhammer II)
  final int appId;

  /// Workshop page URL
  final String workshopUrl;

  /// File size in bytes
  final int? fileSize;

  /// Creation timestamp (Unix epoch seconds)
  final int? timeCreated;

  /// Last update timestamp (Unix epoch seconds)
  final int? timeUpdated;

  /// Number of subscribers
  final int? subscriptions;

  /// Tags/categories (JSON encoded list)
  final List<String>? tags;

  /// When this record was created in database
  final int createdAt;

  /// When this record was last updated
  final int updatedAt;

  /// When metadata was last checked against Steam API
  final int? lastCheckedAt;

  /// Whether the mod is hidden from the main mod list
  final bool isHidden;

  const WorkshopMod({
    required this.id,
    required this.workshopId,
    required this.title,
    required this.appId,
    required this.workshopUrl,
    this.fileSize,
    this.timeCreated,
    this.timeUpdated,
    this.subscriptions,
    this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.lastCheckedAt,
    this.isHidden = false,
  });

  /// Convert from JSON map (database)
  factory WorkshopMod.fromJson(Map<String, dynamic> json) {
    return WorkshopMod(
      id: json['id'] as String,
      workshopId: json['workshop_id'] as String,
      title: json['title'] as String,
      appId: json['app_id'] as int,
      workshopUrl: json['workshop_url'] as String,
      fileSize: json['file_size'] as int?,
      timeCreated: json['time_created'] as int?,
      timeUpdated: json['time_updated'] as int?,
      subscriptions: json['subscriptions'] as int?,
      tags: json['tags'] != null 
          ? List<String>.from(jsonDecode(json['tags'] as String))
          : null,
      createdAt: json['created_at'] as int,
      updatedAt: json['updated_at'] as int,
      lastCheckedAt: json['last_checked_at'] as int?,
      isHidden: (json['is_hidden'] as int?) == 1,
    );
  }

  /// Convert to JSON map (database)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workshop_id': workshopId,
      'title': title,
      'app_id': appId,
      'workshop_url': workshopUrl,
      'file_size': fileSize,
      'time_created': timeCreated,
      'time_updated': timeUpdated,
      'subscriptions': subscriptions,
      'tags': tags != null ? jsonEncode(tags) : null,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_checked_at': lastCheckedAt,
      'is_hidden': isHidden ? 1 : 0,
    };
  }

  /// Create copy with updated fields
  WorkshopMod copyWith({
    String? id,
    String? workshopId,
    String? title,
    int? appId,
    String? workshopUrl,
    int? fileSize,
    int? timeCreated,
    int? timeUpdated,
    int? subscriptions,
    List<String>? tags,
    int? createdAt,
    int? updatedAt,
    int? lastCheckedAt,
    bool? isHidden,
  }) {
    return WorkshopMod(
      id: id ?? this.id,
      workshopId: workshopId ?? this.workshopId,
      title: title ?? this.title,
      appId: appId ?? this.appId,
      workshopUrl: workshopUrl ?? this.workshopUrl,
      fileSize: fileSize ?? this.fileSize,
      timeCreated: timeCreated ?? this.timeCreated,
      timeUpdated: timeUpdated ?? this.timeUpdated,
      subscriptions: subscriptions ?? this.subscriptions,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkshopMod &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          workshopId == other.workshopId;

  @override
  int get hashCode => Object.hash(id, workshopId);

  @override
  String toString() =>
      'WorkshopMod(id: $id, workshopId: $workshopId, title: $title, updated: $timeUpdated)';
}

